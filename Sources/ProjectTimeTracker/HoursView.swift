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
    /// The project waiting for the user to confirm deletion.
    @State private var projectToDelete: Project?
    /// The project being renamed, and the name typed so far.
    @State private var projectToRename: Project?
    /// The project whose sessions are being edited.
    @State private var sessionsProject: Project?
    @State private var renameText = ""

    private var isCurrentWeek: Bool {
        model.calendar.isDate(shownDate, equalTo: model.now, toGranularity: .weekOfYear)
    }

    var body: some View {
        let report = model.weekReport(containing: shownDate, includeEmpty: !hideEmpty)

        VStack(alignment: .leading, spacing: 16) {
            if let project = model.runningProject {
                runningBanner(project)
            }

            header(report)
                .alert(
                    "Rename “\(projectToRename?.name ?? "")”",
                    isPresented: Binding(get: { projectToRename != nil }, set: { if !$0 { projectToRename = nil } })
                ) {
                    TextField("New name", text: $renameText)
                    Button("Rename") {
                        if let project = projectToRename { model.renameProject(project, to: renameText) }
                    }
                    Button("Cancel", role: .cancel) {}
                }

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
                if let error = model.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Use a project's Edit button to fix its times, rename it or delete it. Projects with no time this week are hidden unless you untick the box above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 820, minHeight: 320, alignment: .topLeading)
        .sheet(item: $sessionsProject) { project in
            SessionsEditor(model: model, project: project, weekContaining: shownDate) {
                sessionsProject = nil
            }
        }
        .alert(
            "Delete “\(projectToDelete?.name ?? "")”?",
            isPresented: Binding(get: { projectToDelete != nil }, set: { if !$0 { projectToDelete = nil } }),
            presenting: projectToDelete
        ) { project in
            Button("Delete", role: .destructive) { model.deleteProject(project) }
            Button("Cancel", role: .cancel) {}
        } message: { project in
            Text("This permanently removes the project and all \(DurationFormat.compact(model.totalTime(for: project))) "
                 + "of time tracked on it. This can't be undone.")
        }
    }

    // MARK: - Running timer

    /// Shows the running timer with a Stop button, so it can be stopped from here too.
    private func runningBanner(_ project: Project) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
            Text("Tracking \(project.name)")
                .fontWeight(.semibold)
                .lineLimit(1)
            Text(DurationFormat.clock(model.runningElapsed ?? 0))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer()
            Button("Edit Times…") {
                model.clearError()
                sessionsProject = project
            }
            Button {
                model.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.1)))
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

            Text(weekTitle(report))
                .font(.title3.weight(.semibold))

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
                Text("")
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
                    editMenu(row.summary.project)
                }
                .monospacedDigit()
                .contentShape(Rectangle())
                .contextMenu { editMenuItems(row.summary.project) }
            }
        }
    }

    /// A visible Edit button on each row, with the same choices as right-clicking.
    private func editMenu(_ project: Project) -> some View {
        Menu("Edit") { editMenuItems(project) }
            .fixedSize()
            .help("Edit times, rename or delete this project")
    }

    @ViewBuilder
    private func editMenuItems(_ project: Project) -> some View {
        Button("Edit Times…") {
            model.clearError()
            sessionsProject = project
        }
        Button("Rename Project…") {
            renameText = project.name
            projectToRename = project
        }
        Button("Delete Project…", role: .destructive) {
            projectToDelete = project
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
