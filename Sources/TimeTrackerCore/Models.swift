import Foundation

/// A named project that time is tracked against.
public struct Project: Codable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public var name: String
    public let createdAt: Date
    /// Optional goal for each day, e.g. 2 hours. `nil` means no goal.
    public var dailyTarget: TimeInterval?
    /// Optional goal for each week, e.g. 10 hours. `nil` means no goal.
    public var weeklyTarget: TimeInterval?

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date,
        dailyTarget: TimeInterval? = nil,
        weeklyTarget: TimeInterval? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.dailyTarget = dailyTarget
        self.weeklyTarget = weeklyTarget
    }
}

/// One continuous stretch of work on a project, from Start to Stop.
public struct TimeEntry: Codable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public let projectID: UUID
    public let start: Date
    /// `nil` while the timer is still running.
    public var end: Date?

    public init(id: UUID = UUID(), projectID: UUID, start: Date, end: Date? = nil) {
        self.id = id
        self.projectID = projectID
        self.start = start
        self.end = end
    }

    public var isRunning: Bool { end == nil }

    /// Length of the entry. A running entry is measured up to `now`.
    public func duration(asOf now: Date) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }

    /// How much of this entry falls inside `interval`.
    public func duration(within interval: DateInterval, asOf now: Date) -> TimeInterval {
        let entryEnd = end ?? now
        let overlapStart = max(start, interval.start)
        let overlapEnd = min(entryEnd, interval.end)
        return max(0, overlapEnd.timeIntervalSince(overlapStart))
    }
}

/// Everything the app saves to disk.
public struct TrackerData: Codable, Equatable {
    public var projects: [Project]
    public var entries: [TimeEntry]

    public init(projects: [Project] = [], entries: [TimeEntry] = []) {
        self.projects = projects
        self.entries = entries
    }
}

/// Daily, weekly and all-time totals for one project.
public struct ProjectSummary: Identifiable, Equatable {
    public let project: Project
    public let dayTotal: TimeInterval
    public let weekTotal: TimeInterval
    public let allTimeTotal: TimeInterval
    public let isRunning: Bool

    public var id: UUID { project.id }

    /// Time still needed today to reach the daily target, or `nil` if there is no target.
    public var dayRemaining: TimeInterval? {
        project.dailyTarget.map { max(0, $0 - dayTotal) }
    }

    /// Time still needed this week to reach the weekly target, or `nil` if there is no target.
    public var weekRemaining: TimeInterval? {
        project.weeklyTarget.map { max(0, $0 - weekTotal) }
    }

    /// 0...1 progress toward the daily target, or `nil` if there is no target.
    public var dayProgress: Double? {
        project.dailyTarget.map { Self.progress(dayTotal, of: $0) }
    }

    /// 0...1 progress toward the weekly target, or `nil` if there is no target.
    public var weekProgress: Double? {
        project.weeklyTarget.map { Self.progress(weekTotal, of: $0) }
    }

    private static func progress(_ done: TimeInterval, of target: TimeInterval) -> Double {
        target > 0 ? min(1, done / target) : 1
    }
}

/// Time spent on one calendar day.
public struct DayTotal: Equatable {
    /// Midnight at the start of the day.
    public let day: Date
    public let total: TimeInterval
}

/// Everything the hours view shows for one week: a row per project with
/// its time on each day, plus totals across all projects.
public struct WeekReport: Equatable {
    public struct Row: Identifiable, Equatable {
        /// Week total, all-time total and targets for the project.
        public let summary: ProjectSummary
        /// Time on each day of the week, in the same order as `WeekReport.days`.
        public let days: [TimeInterval]

        public var id: UUID { summary.project.id }
    }

    public let week: DateInterval
    /// Midnight at the start of each of the seven days.
    public let days: [Date]
    public let rows: [Row]
    /// Time across all projects on each day.
    public let dayTotals: [TimeInterval]
    /// Time across all projects for the whole week.
    public let weekTotal: TimeInterval
}
