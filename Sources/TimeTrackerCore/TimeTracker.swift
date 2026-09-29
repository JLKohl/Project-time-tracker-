import Foundation

public enum TimeTrackerError: Error, Equatable {
    case emptyProjectName
    /// Another project already has this name (the associated value is its name).
    case duplicateProjectName(String)
}

/// Starts and stops timers and answers "how much time did I spend?" questions.
///
/// Only one timer runs at a time. Every change is saved immediately, so a timer
/// left running when the app quits keeps counting when it is reopened.
public final class TimeTracker {
    public private(set) var data: TrackerData
    public let calendar: Calendar

    private let store: TrackerStore
    private let now: () -> Date

    public init(
        store: TrackerStore,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) throws {
        self.store = store
        self.calendar = calendar
        self.now = now
        self.data = try store.load()
    }

    // MARK: - Timer

    public var runningEntry: TimeEntry? {
        data.entries.last(where: { $0.isRunning })
    }

    public var runningProject: Project? {
        runningEntry.flatMap { project(withID: $0.projectID) }
    }

    /// Starts timing `name`, creating the project if it doesn't exist yet.
    /// Any timer already running is stopped first.
    @discardableResult
    public func start(projectNamed name: String) throws -> TimeEntry {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TimeTrackerError.emptyProjectName }

        let timestamp = now()
        stopRunningEntries(at: timestamp)

        let project = findProject(named: trimmed) ?? createProject(named: trimmed, at: timestamp)
        let entry = TimeEntry(projectID: project.id, start: timestamp)
        data.entries.append(entry)
        try store.save(data)
        return entry
    }

    /// Stops the running timer, if any, and returns the finished entry.
    @discardableResult
    public func stop() throws -> TimeEntry? {
        guard let running = runningEntry else { return nil }
        stopRunningEntries(at: now())
        try store.save(data)
        return data.entries.first(where: { $0.id == running.id })
    }

    // MARK: - Projects

    /// Adds a project without starting its timer, or returns the existing one with that name.
    @discardableResult
    public func addProject(named name: String) throws -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TimeTrackerError.emptyProjectName }
        if let existing = findProject(named: trimmed) { return existing }
        let project = createProject(named: trimmed, at: now())
        try store.save(data)
        return project
    }

    public var projects: [Project] { data.projects }

    public func project(withID id: UUID) -> Project? {
        data.projects.first(where: { $0.id == id })
    }

    /// Case-insensitive, whitespace-insensitive lookup so "Website" and " website " match.
    public func findProject(named name: String) -> Project? {
        let key = Self.normalized(name)
        return data.projects.first(where: { Self.normalized($0.name) == key })
    }

    /// Sets (or clears, with `nil`) a project's daily and weekly target hours.
    public func setTargets(for projectID: UUID, daily: TimeInterval?, weekly: TimeInterval?) throws {
        guard let index = data.projects.firstIndex(where: { $0.id == projectID }) else { return }
        data.projects[index].dailyTarget = daily.flatMap { $0 > 0 ? $0 : nil }
        data.projects[index].weeklyTarget = weekly.flatMap { $0 > 0 ? $0 : nil }
        try store.save(data)
    }

    /// Gives a project a new name. Its time and targets are kept.
    /// Changing only the capitals of its own name is allowed; taking another project's name is not.
    public func renameProject(withID projectID: UUID, to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TimeTrackerError.emptyProjectName }
        guard let index = data.projects.firstIndex(where: { $0.id == projectID }) else { return }
        if let existing = findProject(named: trimmed), existing.id != projectID {
            throw TimeTrackerError.duplicateProjectName(existing.name)
        }
        data.projects[index].name = trimmed
        try store.save(data)
    }

    /// Permanently removes a project and all of its tracked time,
    /// including a timer that's running for it.
    public func deleteProject(withID projectID: UUID) throws {
        guard data.projects.contains(where: { $0.id == projectID }) else { return }
        data.projects.removeAll { $0.id == projectID }
        data.entries.removeAll { $0.projectID == projectID }
        try store.save(data)
    }

    /// Projects ordered by when they were last worked on, most recent first.
    public func recentProjects(limit: Int = 5) -> [Project] {
        var lastUsed: [UUID: Date] = [:]
        for entry in data.entries {
            lastUsed[entry.projectID] = max(lastUsed[entry.projectID] ?? .distantPast, entry.start)
        }
        return data.projects
            .sorted { (lastUsed[$0.id] ?? $0.createdAt) > (lastUsed[$1.id] ?? $1.createdAt) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Totals

    /// The calendar day (midnight to midnight) that contains `date`.
    public func dayInterval(containing date: Date) -> DateInterval {
        calendar.dateInterval(of: .day, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 24 * 60 * 60)
    }

    /// The week (per the calendar's first weekday) that contains `date`.
    public func weekInterval(containing date: Date) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: date, duration: 7 * 24 * 60 * 60)
    }

    public func totalTime(for projectID: UUID) -> TimeInterval {
        let current = now()
        return entries(for: projectID).reduce(0) { $0 + $1.duration(asOf: current) }
    }

    /// Time spent on a project inside `interval`. Entries that cross the edge
    /// of the interval only count the part inside it.
    public func time(for projectID: UUID, in interval: DateInterval) -> TimeInterval {
        let current = now()
        return entries(for: projectID).reduce(0) { $0 + $1.duration(within: interval, asOf: current) }
    }

    /// Time spent on a project on the day containing `date`.
    public func dayTime(for projectID: UUID, dayContaining date: Date) -> TimeInterval {
        time(for: projectID, in: dayInterval(containing: date))
    }

    /// Time spent on a project during the week containing `date`.
    public func weekTime(for projectID: UUID, weekContaining date: Date) -> TimeInterval {
        time(for: projectID, in: weekInterval(containing: date))
    }

    /// Hours for each of the seven days in the week containing `date`, in order.
    public func dailyBreakdown(for projectID: UUID, weekContaining date: Date) -> [DayTotal] {
        let week = weekInterval(containing: date)
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: week.start) else { return nil }
            let interval = dayInterval(containing: day)
            return DayTotal(day: interval.start, total: time(for: projectID, in: interval))
        }
    }

    /// Today, this week and all-time totals for one project, relative to `date`.
    public func summary(for project: Project, on date: Date) -> ProjectSummary {
        ProjectSummary(
            project: project,
            dayTotal: dayTime(for: project.id, dayContaining: date),
            weekTotal: weekTime(for: project.id, weekContaining: date),
            allTimeTotal: totalTime(for: project.id),
            isRunning: project.id == runningEntry?.projectID
        )
    }

    /// Summaries for every project, busiest that week first.
    public func summaries(on date: Date) -> [ProjectSummary] {
        data.projects
            .map { summary(for: $0, on: date) }
            .sorted {
                if $0.weekTotal != $1.weekTotal { return $0.weekTotal > $1.weekTotal }
                if $0.allTimeTotal != $1.allTimeTotal { return $0.allTimeTotal > $1.allTimeTotal }
                return $0.project.name.localizedCaseInsensitiveCompare($1.project.name) == .orderedAscending
            }
    }

    /// The same date moved by whole weeks, e.g. `-1` for the week before.
    public func date(_ date: Date, movedByWeeks weeks: Int) -> Date {
        calendar.date(byAdding: .weekOfYear, value: weeks, to: date)
            ?? date.addingTimeInterval(TimeInterval(weeks) * 7 * 24 * 60 * 60)
    }

    /// A day-by-day report for the week containing `date`.
    /// Projects with no time that week are left out unless `includeEmpty` is true
    /// (a running project is always included).
    public func weekReport(containing date: Date, includeEmpty: Bool = false) -> WeekReport {
        let week = weekInterval(containing: date)
        let rows = summaries(on: date)
            .filter { includeEmpty || $0.weekTotal > 0 || $0.isRunning }
            .map { summary in
                WeekReport.Row(
                    summary: summary,
                    days: dailyBreakdown(for: summary.project.id, weekContaining: date).map(\.total)
                )
            }
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
            .map { dayInterval(containing: $0).start }
        return WeekReport(week: week, days: days, rows: rows)
    }

    // MARK: - Private

    private func entries(for projectID: UUID) -> [TimeEntry] {
        data.entries.filter { $0.projectID == projectID }
    }

    private func stopRunningEntries(at timestamp: Date) {
        for index in data.entries.indices where data.entries[index].isRunning {
            data.entries[index].end = max(timestamp, data.entries[index].start)
        }
    }

    private func createProject(named name: String, at timestamp: Date) -> Project {
        let project = Project(name: name, createdAt: timestamp)
        data.projects.append(project)
        return project
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
