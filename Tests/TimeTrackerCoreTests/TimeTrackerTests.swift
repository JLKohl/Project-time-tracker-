import XCTest
@testable import TimeTrackerCore

/// A clock the tests can move forward by hand.
private final class TestClock {
    var now: Date
    init(_ iso: String) { now = TestClock.date(iso) }
    func advance(hours: Double = 0, minutes: Double = 0) {
        now = now.addingTimeInterval(hours * 3600 + minutes * 60)
    }
    func set(_ iso: String) { now = TestClock.date(iso) }
    static func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
}

final class TimeTrackerTests: XCTestCase {
    private var clock: TestClock!
    private var store: InMemoryStore!
    private var tracker: TimeTracker!

    /// Weeks run Monday–Sunday in UTC so results don't depend on the machine running the tests.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    override func setUpWithError() throws {
        clock = TestClock("2026-09-28T09:00:00Z") // a Monday
        store = InMemoryStore()
        tracker = try makeTracker()
    }

    private func makeTracker() throws -> TimeTracker {
        let clock = self.clock!
        return try TimeTracker(store: store, calendar: calendar, now: { clock.now })
    }

    func testStartAndStopRecordsDuration() throws {
        try tracker.start(projectNamed: "Website")
        clock.advance(hours: 1, minutes: 30)
        let entry = try XCTUnwrap(tracker.stop())

        XCTAssertEqual(entry.duration(asOf: clock.now), 90 * 60)
        XCTAssertNil(tracker.runningEntry)
        let project = try XCTUnwrap(tracker.findProject(named: "Website"))
        XCTAssertEqual(tracker.totalTime(for: project.id), 90 * 60)
    }

    func testRunningTimerCountsUpToNow() throws {
        try tracker.start(projectNamed: "Website")
        clock.advance(minutes: 20)
        let project = try XCTUnwrap(tracker.runningProject)
        XCTAssertEqual(tracker.totalTime(for: project.id), 20 * 60)
    }

    func testEmptyNameIsRejected() {
        XCTAssertThrowsError(try tracker.start(projectNamed: "   ")) { error in
            XCTAssertEqual(error as? TimeTrackerError, .emptyProjectName)
        }
        XCTAssertTrue(tracker.projects.isEmpty)
    }

    func testSameNameReusesProjectIgnoringCaseAndSpaces() throws {
        try tracker.start(projectNamed: "Website")
        try tracker.stop()
        try tracker.start(projectNamed: "  website ")
        try tracker.stop()

        XCTAssertEqual(tracker.projects.count, 1)
        XCTAssertEqual(tracker.projects.first?.name, "Website")
        XCTAssertEqual(tracker.data.entries.count, 2)
    }

    func testStartingAnotherProjectStopsTheFirst() throws {
        try tracker.start(projectNamed: "A")
        clock.advance(hours: 1)
        try tracker.start(projectNamed: "B")
        clock.advance(hours: 2)

        let a = try XCTUnwrap(tracker.findProject(named: "A"))
        let b = try XCTUnwrap(tracker.findProject(named: "B"))
        XCTAssertEqual(tracker.totalTime(for: a.id), 3600)
        XCTAssertEqual(tracker.totalTime(for: b.id), 2 * 3600)
        XCTAssertEqual(tracker.runningProject?.id, b.id)
        XCTAssertEqual(tracker.data.entries.filter(\.isRunning).count, 1)
    }

    func testStopWithNothingRunningDoesNothing() throws {
        XCTAssertNil(try tracker.stop())
        XCTAssertEqual(store.saveCount, 0)
    }

    func testWeekTotalOnlyCountsThatWeek() throws {
        // Last week (Tuesday): 2 hours.
        clock.set("2026-09-22T10:00:00Z")
        try tracker.start(projectNamed: "Website")
        clock.advance(hours: 2)
        try tracker.stop()

        // This week (Wednesday): 3 hours.
        clock.set("2026-09-30T10:00:00Z")
        try tracker.start(projectNamed: "Website")
        clock.advance(hours: 3)
        try tracker.stop()

        let project = try XCTUnwrap(tracker.findProject(named: "Website"))
        XCTAssertEqual(tracker.weekTime(for: project.id, weekContaining: clock.now), 3 * 3600)
        XCTAssertEqual(tracker.weekTime(for: project.id, weekContaining: TestClock.date("2026-09-22T00:00:00Z")), 2 * 3600)
        XCTAssertEqual(tracker.totalTime(for: project.id), 5 * 3600)
    }

    func testEntryCrossingWeekBoundaryIsSplit() throws {
        // Sunday 11pm to Monday 2am: 1 hour last week, 2 hours this week.
        clock.set("2026-09-27T23:00:00Z")
        try tracker.start(projectNamed: "Late night")
        clock.advance(hours: 3)
        try tracker.stop()

        let project = try XCTUnwrap(tracker.findProject(named: "Late night"))
        XCTAssertEqual(tracker.weekTime(for: project.id, weekContaining: TestClock.date("2026-09-27T12:00:00Z")), 3600)
        XCTAssertEqual(tracker.weekTime(for: project.id, weekContaining: TestClock.date("2026-09-28T12:00:00Z")), 2 * 3600)
        XCTAssertEqual(tracker.totalTime(for: project.id), 3 * 3600)
    }

    func testDayTotalOnlyCountsThatDay() throws {
        // Monday: 2 hours. Tuesday: 30 minutes.
        try tracker.start(projectNamed: "Website")
        clock.advance(hours: 2)
        try tracker.stop()
        clock.set("2026-09-29T09:00:00Z")
        try tracker.start(projectNamed: "Website")
        clock.advance(minutes: 30)
        try tracker.stop()

        let project = try XCTUnwrap(tracker.findProject(named: "Website"))
        XCTAssertEqual(tracker.dayTime(for: project.id, dayContaining: TestClock.date("2026-09-28T12:00:00Z")), 2 * 3600)
        XCTAssertEqual(tracker.dayTime(for: project.id, dayContaining: clock.now), 30 * 60)
        XCTAssertEqual(tracker.weekTime(for: project.id, weekContaining: clock.now), 2.5 * 3600)
    }

    func testEntryPastMidnightIsSplitBetweenDays() throws {
        // Monday 11pm to Tuesday 1am.
        clock.set("2026-09-28T23:00:00Z")
        try tracker.start(projectNamed: "Late night")
        clock.advance(hours: 2)
        try tracker.stop()

        let project = try XCTUnwrap(tracker.findProject(named: "Late night"))
        XCTAssertEqual(tracker.dayTime(for: project.id, dayContaining: TestClock.date("2026-09-28T12:00:00Z")), 3600)
        XCTAssertEqual(tracker.dayTime(for: project.id, dayContaining: TestClock.date("2026-09-29T12:00:00Z")), 3600)
    }

    func testDailyBreakdownCoversTheWholeWeek() throws {
        clock.set("2026-09-30T10:00:00Z") // Wednesday
        try tracker.start(projectNamed: "Website")
        clock.advance(hours: 3)
        try tracker.stop()

        let project = try XCTUnwrap(tracker.findProject(named: "Website"))
        let days = tracker.dailyBreakdown(for: project.id, weekContaining: clock.now)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first?.day, TestClock.date("2026-09-28T00:00:00Z")) // Monday
        XCTAssertEqual(days.map(\.total), [0, 0, 3 * 3600, 0, 0, 0, 0])
    }

    func testRecentProjectsMostRecentFirst() throws {
        try tracker.start(projectNamed: "Old")
        clock.advance(hours: 1)
        try tracker.start(projectNamed: "Newer")
        clock.advance(hours: 1)
        try tracker.start(projectNamed: "Old")
        try tracker.stop()

        XCTAssertEqual(tracker.recentProjects().map(\.name), ["Old", "Newer"])
        XCTAssertEqual(tracker.recentProjects(limit: 1).map(\.name), ["Old"])
    }

    func testSummariesSortedByThisWeek() throws {
        try tracker.start(projectNamed: "Small")
        clock.advance(hours: 1)
        try tracker.start(projectNamed: "Big")
        clock.advance(hours: 4)

        let summaries = tracker.summaries(on: clock.now)
        XCTAssertEqual(summaries.map(\.project.name), ["Big", "Small"])
        XCTAssertEqual(summaries.first?.weekTotal, 4 * 3600)
        XCTAssertEqual(summaries.first?.dayTotal, 4 * 3600)
        XCTAssertEqual(summaries.first?.isRunning, true)
        XCTAssertEqual(summaries.last?.isRunning, false)
    }

    func testRunningTimerSurvivesRestart() throws {
        try tracker.start(projectNamed: "Website")
        clock.advance(hours: 1)

        // Simulate quitting and reopening the app.
        let reopened = try makeTracker()
        clock.advance(hours: 1)
        let project = try XCTUnwrap(reopened.runningProject)
        XCTAssertEqual(project.name, "Website")
        XCTAssertEqual(reopened.totalTime(for: project.id), 2 * 3600)
    }

    func testJSONFileStoreRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("data.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let fileStore = JSONFileStore(fileURL: url)
        XCTAssertEqual(try fileStore.load(), TrackerData())

        let project = Project(name: "Website", createdAt: TestClock.date("2026-09-28T09:00:00Z"))
        let entry = TimeEntry(
            projectID: project.id,
            start: TestClock.date("2026-09-28T09:00:00Z"),
            end: TestClock.date("2026-09-28T10:00:00Z")
        )
        let data = TrackerData(projects: [project], entries: [entry])
        try fileStore.save(data)
        XCTAssertEqual(try fileStore.load(), data)
    }

    func testDurationFormatting() {
        XCTAssertEqual(DurationFormat.clock(3909), "1:05:09")
        XCTAssertEqual(DurationFormat.hoursMinutes(12 * 3600 + 5 * 60 + 59), "12h 05m")
        XCTAssertEqual(DurationFormat.decimalHours(5400), "1.5")
        XCTAssertEqual(DurationFormat.clock(-5), "0:00:00")
    }
}
