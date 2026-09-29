import Foundation

public enum TimeTrackerError: Error, Equatable {
    case emptyProjectName
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

    public var projects: [Project] { data.projects }

    public func project(withID id: UUID) -> Project? {
        data.projects.first(where: { $0.id == id })
    }

    /// Case-insensitive, whitespace-insensitive lookup so "Website" and " website " match.
    public func findProject(named name: String) -> Project? {
        let key = Self.normalized(name)
        return data.projects.first(where: { Self.normalized($0.name) == key })
    }

    // MARK: - Totals

    /// The week (per the calendar's first weekday) that contains `date`.
    public func weekInterval(containing date: Date) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: date, duration: 7 * 24 * 60 * 60)
    }

    public func totalTime(for projectID: UUID) -> TimeInterval {
        let current = now()
        return entries(for: projectID).reduce(0) { $0 + $1.duration(asOf: current) }
    }

    /// Time spent on a project during the week containing `date`.
    /// Entries that cross a week boundary are split at midnight of the boundary.
    public func weekTime(for projectID: UUID, weekContaining date: Date) -> TimeInterval {
        let current = now()
        let week = weekInterval(containing: date)
        return entries(for: projectID).reduce(0) { $0 + $1.duration(within: week, asOf: current) }
    }

    /// Weekly and all-time totals for every project, busiest this week first.
    public func summaries(weekContaining date: Date) -> [ProjectSummary] {
        let runningID = runningEntry?.projectID
        return data.projects
            .map { project in
                ProjectSummary(
                    project: project,
                    weekTotal: weekTime(for: project.id, weekContaining: date),
                    allTimeTotal: totalTime(for: project.id),
                    isRunning: project.id == runningID
                )
            }
            .sorted {
                if $0.weekTotal != $1.weekTotal { return $0.weekTotal > $1.weekTotal }
                if $0.allTimeTotal != $1.allTimeTotal { return $0.allTimeTotal > $1.allTimeTotal }
                return $0.project.name.localizedCaseInsensitiveCompare($1.project.name) == .orderedAscending
            }
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
