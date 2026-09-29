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

    func testAddProjectDoesNotStartTimer() throws {
        let project = try tracker.addProject(named: " Website ")

        XCTAssertEqual(project.name, "Website")
        XCTAssertNil(tracker.runningEntry)
        XCTAssertTrue(tracker.data.entries.isEmpty)
        XCTAssertEqual(tracker.totalTime(for: project.id), 0)
        XCTAssertEqual(try makeTracker().findProject(named: "website")?.id, project.id)

        // Adding the same name again returns the same project.
        XCTAssertEqual(try tracker.addProject(named: "WEBSITE").id, project.id)
        XCTAssertEqual(tracker.projects.count, 1)

        // Starting it later uses that project.
        try tracker.start(projectNamed: "website")
        XCTAssertEqual(tracker.runningProject?.id, project.id)
    }

    func testAddProjectRejectsEmptyName() {
        XCTAssertThrowsError(try tracker.addProject(named: "  ")) { error in
            XCTAssertEqual(error as? TimeTrackerError, .emptyProjectName)
        }
    }

    func testAddingProjectLeavesRunningTimerAlone() throws {
        try tracker.start(projectNamed: "Website")
        clock.advance(minutes: 10)
        try tracker.addProject(named: "Blog")
        XCTAssertEqual(tracker.runningProject?.name, "Website")
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

    func testSundayStartWeek() throws {
        var sundayCalendar = calendar
        sundayCalendar.firstWeekday = 1
        let clock = self.clock!
        let sundayTracker = try TimeTracker(store: InMemoryStore(), calendar: sundayCalendar, now: { clock.now })

        // Saturday 11pm to Sunday 1am: 1 hour in each week.
        clock.set("2026-09-26T23:00:00Z")
        try sundayTracker.start(projectNamed: "Website")
        clock.advance(hours: 2)
        try sundayTracker.stop()

        let id = try XCTUnwrap(sundayTracker.findProject(named: "Website")).id
        let week = sundayTracker.weekInterval(containing: clock.now)
        XCTAssertEqual(week.start, TestClock.date("2026-09-27T00:00:00Z")) // Sunday
        XCTAssertEqual(sundayTracker.weekTime(for: id, weekContaining: clock.now), 3600)
        XCTAssertEqual(sundayTracker.weekTime(for: id, weekContaining: TestClock.date("2026-09-26T12:00:00Z")), 3600)
        XCTAssertEqual(sundayTracker.dailyBreakdown(for: id, weekContaining: clock.now).first?.day, week.start)
    }

    func testWeekReport() throws {
        // Monday: A 1h, B 2h. Wednesday: A 30m. Last week: C 1h.
        clock.set("2026-09-22T10:00:00Z")
        try tracker.start(projectNamed: "C")
        clock.advance(hours: 1)
        try tracker.stop()

        clock.set("2026-09-28T09:00:00Z")
        try tracker.start(projectNamed: "A")
        clock.advance(hours: 1)
        try tracker.start(projectNamed: "B")
        clock.advance(hours: 2)
        try tracker.stop()
        clock.set("2026-09-30T09:00:00Z")
        try tracker.start(projectNamed: "A")
        clock.advance(minutes: 30)
        try tracker.stop()

        let report = tracker.weekReport(containing: clock.now)
        XCTAssertEqual(report.days.count, 7)
        XCTAssertEqual(report.days.first, TestClock.date("2026-09-28T00:00:00Z"))
        XCTAssertEqual(report.rows.map(\.summary.project.name), ["B", "A"]) // C had no time this week
        XCTAssertEqual(report.rows[1].days, [3600, 0, 1800, 0, 0, 0, 0])

        let withEmpty = tracker.weekReport(containing: clock.now, includeEmpty: true)
        XCTAssertEqual(withEmpty.rows.map(\.summary.project.name), ["B", "A", "C"])

        let lastWeek = tracker.weekReport(containing: tracker.date(clock.now, movedByWeeks: -1))
        XCTAssertEqual(lastWeek.rows.map(\.summary.project.name), ["C"])
        XCTAssertEqual(lastWeek.days.first, TestClock.date("2026-09-21T00:00:00Z"))
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

    func testTargetsShowTimeRemaining() throws {
        try tracker.start(projectNamed: "Website")
        let id = try XCTUnwrap(tracker.runningProject).id
        try tracker.setTargets(for: id, daily: 2 * 3600, weekly: 10 * 3600)
        let project = try XCTUnwrap(tracker.project(withID: id))
        clock.advance(hours: 1, minutes: 30)

        let summary = tracker.summary(for: project, on: clock.now)
        XCTAssertEqual(summary.dayRemaining, 30 * 60)
        XCTAssertEqual(summary.weekRemaining, 8.5 * 3600)
        XCTAssertEqual(summary.dayProgress, 0.75)

        clock.advance(hours: 1)
        let over = tracker.summary(for: project, on: clock.now)
        XCTAssertEqual(over.dayRemaining, 0)
        XCTAssertEqual(over.dayProgress, 1)
    }

    func testClearingTargets() throws {
        try tracker.start(projectNamed: "Website")
        let id = try XCTUnwrap(tracker.runningProject).id
        try tracker.setTargets(for: id, daily: 3600, weekly: 5 * 3600)
        try tracker.setTargets(for: id, daily: nil, weekly: 0)

        let project = try XCTUnwrap(tracker.project(withID: id))
        XCTAssertNil(project.dailyTarget)
        XCTAssertNil(project.weeklyTarget)
        XCTAssertNil(tracker.summary(for: project, on: clock.now).dayRemaining)
    }

    func testTargetsAreSaved() throws {
        try tracker.start(projectNamed: "Website")
        let id = try XCTUnwrap(tracker.runningProject).id
        try tracker.setTargets(for: id, daily: nil, weekly: 10 * 3600)

        let reopened = try makeTracker()
        XCTAssertEqual(reopened.project(withID: id)?.weeklyTarget, 10 * 3600)
    }

    func testOldSaveFilesWithoutTargetsStillLoad() throws {
        let json = """
        {"projects":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Website",
        "createdAt":"2026-09-28T09:00:00Z"}],"entries":[]}
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("data.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)

        let data = try JSONFileStore(fileURL: url).load()
        XCTAssertEqual(data.projects.first?.name, "Website")
        XCTAssertNil(data.projects.first?.dailyTarget)
    }

    func testRenameProjectKeepsItsTime() throws {
        try tracker.start(projectNamed: "Webiste")
        clock.advance(hours: 1)
        let id = try XCTUnwrap(tracker.runningProject).id
        try tracker.setTargets(for: id, daily: 3600, weekly: nil)

        try tracker.renameProject(withID: id, to: "  Website ")

        XCTAssertEqual(tracker.project(withID: id)?.name, "Website")
        XCTAssertEqual(tracker.findProject(named: "website")?.id, id)
        XCTAssertNil(tracker.findProject(named: "Webiste"))
        XCTAssertEqual(tracker.totalTime(for: id), 3600)
        XCTAssertEqual(tracker.project(withID: id)?.dailyTarget, 3600)
        XCTAssertEqual(tracker.runningProject?.id, id)
        XCTAssertEqual(try makeTracker().project(withID: id)?.name, "Website")

        // Changing only the capitals is fine.
        try tracker.renameProject(withID: id, to: "WEBSITE")
        XCTAssertEqual(tracker.project(withID: id)?.name, "WEBSITE")
    }

    func testRenameRejectsEmptyAndDuplicateNames() throws {
        try tracker.start(projectNamed: "Website")
        try tracker.start(projectNamed: "Blog")
        let blog = try XCTUnwrap(tracker.runningProject)

        XCTAssertThrowsError(try tracker.renameProject(withID: blog.id, to: "  ")) { error in
            XCTAssertEqual(error as? TimeTrackerError, .emptyProjectName)
        }
        XCTAssertThrowsError(try tracker.renameProject(withID: blog.id, to: "website")) { error in
            XCTAssertEqual(error as? TimeTrackerError, .duplicateProjectName("Website"))
        }
        XCTAssertEqual(tracker.project(withID: blog.id)?.name, "Blog")
    }

    func testDeleteProjectRemovesItsTime() throws {
        try tracker.start(projectNamed: "Keep")
        clock.advance(hours: 1)
        try tracker.start(projectNamed: "Delete me")
        clock.advance(hours: 1)
        let doomed = try XCTUnwrap(tracker.runningProject)

        try tracker.deleteProject(withID: doomed.id)

        XCTAssertEqual(tracker.projects.map(\.name), ["Keep"])
        XCTAssertNil(tracker.runningEntry) // its running timer went with it
        XCTAssertTrue(tracker.data.entries.allSatisfy { $0.projectID != doomed.id })
        let keep = try XCTUnwrap(tracker.findProject(named: "Keep"))
        XCTAssertEqual(tracker.totalTime(for: keep.id), 3600)

        // Saved, and the name can be used again for a fresh project.
        XCTAssertNil(try makeTracker().findProject(named: "Delete me"))
        try tracker.start(projectNamed: "Delete me")
        XCTAssertNotEqual(tracker.runningProject?.id, doomed.id)
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
        XCTAssertEqual(DurationFormat.compact(0), "0m 00s")
        XCTAssertEqual(DurationFormat.compact(252), "4m 12s")
        XCTAssertEqual(DurationFormat.compact(3 * 3600 + 5 * 60), "3h 05m")
    }

    func testParsingTargetHours() {
        XCTAssertEqual(DurationFormat.parseHours("2"), 2 * 3600)
        XCTAssertEqual(DurationFormat.parseHours(" 1.5 "), 1.5 * 3600)
        XCTAssertEqual(DurationFormat.parseHours("1:30"), 1.5 * 3600)
        XCTAssertEqual(DurationFormat.parseHours("2h"), 2 * 3600)
        XCTAssertEqual(DurationFormat.parseHours("45m"), 45 * 60)
        XCTAssertEqual(DurationFormat.parseHours("1h 30m"), 1.5 * 3600)
        XCTAssertEqual(DurationFormat.parseHours("1H30M"), 1.5 * 3600)
        XCTAssertNil(DurationFormat.parseHours(""))
        XCTAssertNil(DurationFormat.parseHours("abc"))
        XCTAssertNil(DurationFormat.parseHours("1:75"))
        XCTAssertNil(DurationFormat.parseHours("-2"))
        XCTAssertNil(DurationFormat.parseHours("2h 5"))

        for text in ["2", "1.5", "1:20", "0:45"] {
            let parsed = DurationFormat.parseHours(text)!
            XCTAssertEqual(DurationFormat.targetText(parsed), text)
        }
    }
}
