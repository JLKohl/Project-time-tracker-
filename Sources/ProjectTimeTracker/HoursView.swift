import AppKit
import SwiftUI
import TimeTrackerCore

/// Opens the hours window, or brings it to the front if it's already open.
@MainActor
final class HoursWindowController {
    static let shared = HoursWindowController()

    private var window: NSWindow?

    func show(model: TrackerViewModel) {
        if window?.isVisible != true {
            // Build a fresh window each time so a closed one isn't kept updating in the background.
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 420),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Project Hours"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: HoursView(model: model))
            _ = window.setFrameAutosaveName("HoursWindow")
            if !window.setFrameUsingName("HoursWindow") { window.center() }
            self.window = window
        }
        // The app has no Dock icon, so it must bring itself forward for the window to show on top.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Every project's hours for one week, day by day, with week and all-time totals.
struct HoursView: View {
    @ObservedObject var model: TrackerViewModel

    /// Any date inside the week being shown.
    @State private var shownDate = Date()
    @AppStorage("hideEmptyProjects") private var hideEmpty = true

    private var isCurrentWeek: Bool {
        model.calendar.isDate(shownDate, equalTo: model.now, toGranularity: .weekOfYear)
    }

    var body: some View {
        let report = model.weekReport(containing: shownDate, includeEmpty: !hideEmpty)

        VStack(alignment: .leading, spacing: 16) {
            header(report)

            if report.rows.isEmpty {
                Spacer()
                Text(hideEmpty ? "No time tracked this week." : "No projects yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView([.vertical, .horizontal]) {
                    table(report)
                        .padding(.bottom, 8)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 820, minHeight: 320, alignment: .topLeading)
    }

    // MARK: - Header

    private func header(_ report: WeekReport) -> some View {
        HStack(spacing: 10) {
            Button { shownDate = model.date(shownDate, movedByWeeks: -1) } label: {
                Image(systemName: "chevron.left")
            }
            .help("Previous week")

            Button { shownDate = model.date(shownDate, movedByWeeks: 1) } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(isCurrentWeek)
            .help("Next week")

            VStack(alignment: .leading, spacing: 2) {
                Text(weekTitle(report))
                    .font(.title3.weight(.semibold))
                Text("Total: \(DurationFormat.compact(report.weekTotal))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Toggle("Hide projects with no time", isOn: $hideEmpty)
                .toggleStyle(.checkbox)

            Button("This week") { shownDate = Date() }
                .disabled(isCurrentWeek)
        }
    }

    private func weekTitle(_ report: WeekReport) -> String {
        guard let lastDay = report.days.last else { return "" }
        let formatter = DateIntervalFormatter()
        formatter.calendar = model.calendar
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let range = formatter.string(from: report.week.start, to: lastDay)
        return isCurrentWeek ? "This week · \(range)" : range
    }

    // MARK: - Table

    private func table(_ report: WeekReport) -> some View {
        Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 10) {
            GridRow {
                Text("Project").gridColumnAlignment(.leading)
                ForEach(report.days, id: \.self) { day in
                    dayHeader(day)
                }
                Text("Week")
                Text("All time")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            Divider().gridCellUnsizedAxes(.horizontal)

            ForEach(report.rows) { row in
                GridRow {
                    projectName(row.summary)
                    ForEach(Array(row.days.enumerated()), id: \.offset) { _, time in
                        dayCell(time, dailyTarget: row.summary.project.dailyTarget)
                    }
                    weekCell(row.summary)
                    Text(DurationFormat.compact(row.summary.allTimeTotal))
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
            }

            Divider().gridCellUnsizedAxes(.horizontal)

            GridRow {
                Text("Total")
                ForEach(Array(report.dayTotals.enumerated()), id: \.offset) { _, time in
                    Text(time > 0 ? DurationFormat.compact(time) : "–")
                }
                Text(DurationFormat.compact(report.weekTotal))
                Text("")
            }
            .font(.body.weight(.semibold))
            .monospacedDigit()
        }
    }

    private func dayHeader(_ day: Date) -> some View {
        let isToday = model.calendar.isDate(day, inSameDayAs: model.now)
        return VStack(alignment: .trailing, spacing: 1) {
            Text(day.formatted(.dateTime.weekday(.abbreviated)))
            Text(day.formatted(.dateTime.month(.abbreviated).day()))
                .font(.caption2)
        }
        .foregroundStyle(isToday ? Color.accentColor : Color.secondary)
    }

    private func projectName(_ summary: ProjectSummary) -> some View {
        HStack(spacing: 6) {
            if summary.isRunning {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                    .help("Timer running")
            }
            Text(summary.project.name)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(minWidth: 120, maxWidth: 200, alignment: .leading)
    }

    /// A day's time. Turns green once that day's target is met.
    private func dayCell(_ time: TimeInterval, dailyTarget: TimeInterval?) -> some View {
        let metTarget = dailyTarget.map { time >= $0 } ?? false
        return Text(time > 0 ? DurationFormat.compact(time) : "–")
            .foregroundStyle(time == 0 ? Color.secondary : (metTarget ? Color.green : Color.primary))
            .help(dailyTarget.map { "Daily target: \(DurationFormat.hoursMinutes($0))" } ?? "")
    }

    private func weekCell(_ summary: ProjectSummary) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(DurationFormat.compact(summary.weekTotal))
                .fontWeight(.semibold)
            if let target = summary.project.weeklyTarget, let progress = summary.weekProgress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(progress >= 1 ? Color.green : Color.accentColor)
                    .frame(width: 80)
                Text("of \(DurationFormat.hoursMinutes(target))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
