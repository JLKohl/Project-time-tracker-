import Foundation

/// A named project that time is tracked against.
public struct Project: Codable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public var name: String
    public let createdAt: Date

    public init(id: UUID = UUID(), name: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
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
}

/// Time spent on one calendar day.
public struct DayTotal: Equatable {
    /// Midnight at the start of the day.
    public let day: Date
    public let total: TimeInterval
}
