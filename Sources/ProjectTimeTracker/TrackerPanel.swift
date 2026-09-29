import AppKit
import SwiftUI
import TimeTrackerCore

/// The panel that drops down from the menu bar icon.
struct TrackerPanel: View {
    @ObservedObject var model: TrackerViewModel
    @StateObject private var loginItem = LoginItem()
    @AppStorage(MenuBarLabel.showTimeKey) private var showTimeInMenuBar = true

    @State private var editingTargets = false
    @State private var dailyTargetText = ""
    @State private var weeklyTargetText = ""
    @State private var confirmingDelete = false
    @State private var renaming = false
    @State private var renameText = ""

    /// True while one of the inline editors (targets, rename, delete) is open.
    private var isEditing: Bool { editingTargets || confirmingDelete || renaming }

    private var startStopShortcut: KeyboardShortcut? {
        guard !isEditing else { return nil }
        return model.isRunning ? .defaultAction : KeyboardShortcut(.return, modifiers: .command)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let warning = model.storageWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let project = model.runningProject {
                runningHeader(project)
            } else {
                projectPicker
            }

            Button(action: model.toggle) {
                Label(model.isRunning ? "Stop" : "Start",
                      systemImage: model.isRunning ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.isRunning ? .red : .green)
            .controlSize(.large)
            // Return in the name box only adds the project. While running (no name box), Return stops;
            // otherwise ⌘Return starts.
            .keyboardShortcut(startStopShortcut)
            .help(model.isRunning ? "Stop (Return)" : "Start (⌘Return)")

            if let info = model.infoMessage {
                Text(info)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let summary = model.focusedSummary {
                Divider()
                totals(summary)
            }

            Divider()

            Toggle("Show time in menu bar", isOn: $showTimeInMenuBar)
                .toggleStyle(.checkbox)
                .font(.caption)
                .help("Turn off to keep the menu bar icon small, so it isn't hidden by the notch")

            if loginItem.isAvailable {
                Toggle("Open at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)
                .onAppear { loginItem.refresh() }

                if let message = loginItem.message {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Button {
                    HoursWindowController.shared.show(model: model)
                } label: {
                    Label("All hours…", systemImage: "calendar")
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(16)
        .frame(width: 290)
    }

    private func runningHeader(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Tracking")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(project.name)
                .font(.headline)
                .lineLimit(1)
            Text(DurationFormat.clock(model.runningElapsed ?? 0))
                .font(.system(size: 34, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
    }

    private var projectPicker: some View {
        HStack(spacing: 6) {
            TextField("Project name", text: $model.projectName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(model.addProject)

            if !model.recentProjects.isEmpty {
                Menu {
                    ForEach(model.recentProjects) { project in
                        Button(project.name) { model.projectName = project.name }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Recent projects")
            }
        }
    }

    private func totals(_ summary: ProjectSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(summary.project.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if !isEditing {
                    Button(hasTargets(summary.project) ? "Edit targets" : "Set targets") {
                        beginEditingTargets(summary.project)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)

                    Button {
                        renameText = summary.project.name
                        renaming = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("Rename this project")

                    Button { confirmingDelete = true } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("Delete this project")
                }
            }

            HStack(alignment: .top, spacing: 8) {
                total("Today", summary.dayTotal,
                      target: summary.project.dailyTarget,
                      progress: summary.dayProgress,
                      remaining: summary.dayRemaining)
                total("This week", summary.weekTotal,
                      target: summary.project.weeklyTarget,
                      progress: summary.weekProgress,
                      remaining: summary.weekRemaining)
                total("All time", summary.allTimeTotal)
            }

            if editingTargets {
                targetEditor(summary.project)
            }

            if renaming {
                renameEditor(summary.project)
            }

            if confirmingDelete {
                deleteConfirmation(summary)
            }
        }
        // Don't keep editing (or deleting) one project after switching to another.
        .onChange(of: summary.project.id) { _ in
            editingTargets = false
            confirmingDelete = false
            renaming = false
        }
    }

    private func total(
        _ title: String,
        _ value: TimeInterval,
        target: TimeInterval? = nil,
        progress: Double? = nil,
        remaining: TimeInterval? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(DurationFormat.compact(value))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
            if let target, let progress, let remaining {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(remaining == 0 ? Color.green : Color.accentColor)
                Text(remaining == 0
                     ? "Target met ✓"
                     : "\(DurationFormat.compact(remaining)) left")
                    .font(.caption2)
                    .foregroundStyle(remaining == 0 ? Color.green : Color.secondary)
                    .monospacedDigit()
                    .help("Target: \(DurationFormat.hoursMinutes(target))")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func targetEditor(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("Hours per day").font(.caption)
                    TextField("none", text: $dailyTargetText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveTargets(project) }
                }
                GridRow {
                    Text("Hours per week").font(.caption)
                    TextField("none", text: $weeklyTargetText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveTargets(project) }
                }
            }
            Text("e.g. 2, 1.5, 1:30 or 1h 30m. Leave empty for no target.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { editingTargets = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { saveTargets(project) }
            }
            .controlSize(.small)
        }
    }

    private func renameEditor(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("New name", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { saveRename(project) }
            HStack {
                Spacer()
                Button("Cancel") { renaming = false }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") { saveRename(project) }
            }
            .controlSize(.small)
        }
    }

    private func saveRename(_ project: Project) {
        if model.renameProject(project, to: renameText) {
            renaming = false
        }
    }

    /// Asks before deleting, right in the panel.
    private func deleteConfirmation(_ summary: ProjectSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Delete “\(summary.project.name)” and all \(DurationFormat.compact(summary.allTimeTotal)) "
                 + "of its time? This can't be undone.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { confirmingDelete = false }
                    .keyboardShortcut(.cancelAction)
                Button("Delete") {
                    confirmingDelete = false
                    model.deleteProject(summary.project)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
    }

    private func hasTargets(_ project: Project) -> Bool {
        project.dailyTarget != nil || project.weeklyTarget != nil
    }

    private func beginEditingTargets(_ project: Project) {
        dailyTargetText = project.dailyTarget.map(DurationFormat.targetText) ?? ""
        weeklyTargetText = project.weeklyTarget.map(DurationFormat.targetText) ?? ""
        editingTargets = true
    }

    private func saveTargets(_ project: Project) {
        if model.setTargets(for: project, daily: dailyTargetText, weekly: weeklyTargetText) {
            editingTargets = false
        }
    }
}
