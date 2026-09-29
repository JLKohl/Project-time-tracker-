import Combine
import Foundation
import TimeTrackerCore

/// Connects the tracking engine to the SwiftUI views and ticks once a second
/// so the live timer and totals stay current.
@MainActor
final class TrackerViewModel: ObservableObject {
    @Published var projectName = ""
    @Published private(set) var now = Date()
    @Published private(set) var errorMessage: String?
    /// Set once at launch if saved data couldn't be read. Stays visible.
    let storageWarning: String?

    private let tracker: TimeTracker
    private var ticker: AnyCancellable?

    init() {
        // Weeks run Sunday to Saturday.
        var calendar = Calendar.current
        calendar.firstWeekday = 1

        do {
            tracker = try TimeTracker(store: JSONFileStore(), calendar: calendar)
            storageWarning = nil
        } catch {
            // Don't overwrite a file we couldn't read. Keep it and work in memory instead.
            tracker = try! TimeTracker(store: InMemoryStore(), calendar: calendar)
            storageWarning = "Couldn't read saved data at \(JSONFileStore.defaultFileURL.path). "
                + "Nothing will be saved until this is fixed."
        }
        projectName = tracker.runningProject?.name ?? tracker.recentProjects(limit: 1).first?.name ?? ""

        // `.common` keeps the timer ticking while the menu bar panel is open.
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in self?.now = date }
    }

    var isRunning: Bool { tracker.runningEntry != nil }

    var runningProject: Project? { tracker.runningProject }

    var runningElapsed: TimeInterval? {
        tracker.runningEntry?.duration(asOf: now)
    }

    var recentProjects: [Project] { tracker.recentProjects() }

    /// Totals for the running project, or for the project whose name is typed in.
    var focusedSummary: ProjectSummary? {
        guard let project = tracker.runningProject ?? tracker.findProject(named: projectName) else {
            return nil
        }
        return tracker.summary(for: project, on: now)
    }

    func start() {
        perform { _ = try tracker.start(projectNamed: projectName) }
        if let name = tracker.runningProject?.name { projectName = name }
    }

    func stop() {
        perform { _ = try tracker.stop() }
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    /// Saves targets typed by the user. Empty text clears that target.
    /// Returns `false` (and shows a message) if either box can't be read.
    @discardableResult
    func setTargets(for project: Project, daily dailyText: String, weekly weeklyText: String) -> Bool {
        let daily = DurationFormat.parseHours(dailyText)
        let weekly = DurationFormat.parseHours(weeklyText)
        let isBlank = { (text: String) in text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard (daily != nil || isBlank(dailyText)), (weekly != nil || isBlank(weeklyText)) else {
            errorMessage = "Enter hours like 2, 1.5, 1:30 or 1h 30m."
            return false
        }
        perform { try tracker.setTargets(for: project.id, daily: daily, weekly: weekly) }
        return errorMessage == nil
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            errorMessage = nil
        } catch TimeTrackerError.emptyProjectName {
            errorMessage = "Type a project name first."
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
        }
        now = Date()
    }
}
