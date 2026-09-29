import AppKit
import SwiftUI
import TimeTrackerCore

/// Shows the times editor in its own window, for opening it from the menu bar panel.
@MainActor
final class SessionsWindowController {
    static let shared = SessionsWindowController()

    private var window: NSWindow?

    func show(project: Project, model: TrackerViewModel) {
        window?.close()
        model.clearError()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Edit Times"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: SessionsEditor(model: model, project: project, weekContaining: Date()) { [weak window] in
                window?.close()
            }
        )
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// Lists one project's sessions for a week and lets the user change their times,
/// delete them, or add a session that wasn't tracked.
struct SessionsEditor: View {
    @ObservedObject var model: TrackerViewModel
    let project: Project
    /// Called when the user clicks Done.
    let onDone: () -> Void

    /// Any date inside the week being shown.
    @State private var shownDate: Date

    init(model: TrackerViewModel, project: Project, weekContaining date: Date, onDone: @escaping () -> Void) {
        self.model = model
        self.project = project
        self.onDone = onDone
        _shownDate = State(initialValue: date)
    }

    private var week: DateInterval { model.weekInterval(containing: shownDate) }

    private var isCurrentWeek: Bool {
        model.calendar.isDate(shownDate, equalTo: model.now, toGranularity: .weekOfYear)
    }

    private enum Editing: Equatable {
        case existing(UUID)
        case new
    }

    @State private var editing: Editing?
    @State private var draftStart = Date()
    @State private var draftEnd = Date()
    @State private var draftRunning = false
    @State private var deletingID: UUID?

    var body: some View {
        let sessions = model.sessions(for: project, in: week)

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Times for \(project.name)")
                        .font(.headline)
                    Text(weekText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { move(weeks: -1) } label: { Image(systemName: "chevron.left") }
                    .help("Previous week")
                    .disabled(editing != nil)
                Button { move(weeks: 1) } label: { Image(systemName: "chevron.right") }
                    .help("Next week")
                    .disabled(editing != nil || isCurrentWeek)
            }

            Text("Each row is one stretch of time from Start to Stop. Click Edit to change its times.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if sessions.isEmpty && editing != Editing.new {
                Text("No time tracked this week. Use the arrows to see other weeks, or click Add Time.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(sessions) { session in
                            if editing == Editing.existing(session.id) {
                                editor(for: session)
                            } else {
                                row(session)
                            }
                            Divider()
                        }
                        if editing == Editing.new {
                            editor(for: nil)
                        }
                    }
                    .padding(.trailing, 4)
                }
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button(action: beginAdding) {
                    Label("Add Time", systemImage: "plus")
                }
                .disabled(editing != nil)
                .help("Add time you worked without running the timer")

                Spacer()

                Button("Done") {
                    model.clearError()
                    onDone()
                }
                .keyboardShortcut(editing == nil ? KeyboardShortcut.defaultAction : nil)
                .disabled(editing != nil)
            }
        }
        .padding(20)
        .frame(width: 580, height: 440)
    }

    // MARK: - Rows

    private func row(_ session: TimeEntry) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(timeRange(session))
                    .monospacedDigit()
            }

            Spacer()

            Text(DurationFormat.compact(session.duration(asOf: model.now)))
                .fontWeight(.semibold)
                .monospacedDigit()

            if deletingID == session.id {
                Text("Delete?")
                    .font(.caption)
                Button("Cancel") { deletingID = nil }
                Button("Delete") {
                    deletingID = nil
                    model.deleteSession(session)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button("Edit") { beginEditing(session) }
                    .disabled(editing != nil)
                Button { deletingID = session.id } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(editing != nil)
                .help("Delete this time")
            }
        }
    }

    private func timeRange(_ session: TimeEntry) -> String {
        let start = session.start.formatted(date: .omitted, time: .shortened)
        guard let end = session.end else { return "\(start) – running" }
        let endText = model.calendar.isDate(end, inSameDayAs: session.start)
            ? end.formatted(date: .omitted, time: .shortened)
            : end.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        return "\(start) – \(endText)"
    }

    // MARK: - Editing

    /// `session` is nil when adding a new one.
    private func editor(for session: TimeEntry?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session == nil ? "Add time" : "Change times")
                .font(.caption.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Start")
                    DatePicker("Start", selection: $draftStart, in: ...model.now,
                               displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
                GridRow {
                    Text("End")
                    if draftRunning {
                        HStack {
                            Text("Still running")
                                .foregroundStyle(.secondary)
                            Button("Set End Time") {
                                draftEnd = minuteRounded(model.now)
                                draftRunning = false
                            }
                            .help("Stop this session at a time you choose")
                        }
                    } else {
                        DatePicker("End", selection: $draftEnd, in: ...model.now,
                                   displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                    }
                }
            }

            Text("Length: \(DurationFormat.compact(max(0, (draftRunning ? model.now : draftEnd).timeIntervalSince(draftStart))))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            HStack {
                Spacer()
                Button("Cancel") {
                    editing = nil
                    model.clearError()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") { save(session) }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08)))
    }

    private func beginEditing(_ session: TimeEntry) {
        model.clearError()
        deletingID = nil
        draftStart = session.start
        draftEnd = session.end ?? minuteRounded(model.now)
        draftRunning = session.isRunning
        editing = .existing(session.id)
    }

    private func beginAdding() {
        model.clearError()
        deletingID = nil
        // This week: the hour just past. An earlier week: 9 to 10am on its first day.
        if week.contains(model.now) {
            draftEnd = minuteRounded(model.now)
            draftStart = draftEnd.addingTimeInterval(-3600)
        } else {
            draftStart = week.start.addingTimeInterval(9 * 3600)
            draftEnd = draftStart.addingTimeInterval(3600)
        }
        draftRunning = false
        editing = .new
    }

    private func save(_ session: TimeEntry?) {
        let saved: Bool
        if let session {
            saved = model.updateSession(session, start: draftStart, end: draftRunning ? nil : draftEnd)
        } else {
            saved = model.addSession(for: project, start: draftStart, end: draftEnd)
        }
        if saved { editing = nil }
    }

    private func move(weeks: Int) {
        deletingID = nil
        shownDate = model.date(shownDate, movedByWeeks: weeks)
    }

    private func minuteRounded(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }

    private var weekText: String {
        let formatter = DateIntervalFormatter()
        formatter.calendar = model.calendar
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let lastDay = week.end.addingTimeInterval(-1)
        let range = formatter.string(from: week.start, to: lastDay)
        return isCurrentWeek ? "This week · \(range)" : range
    }
}
