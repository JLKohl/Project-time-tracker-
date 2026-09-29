import AppKit
import SwiftUI
import TimeTrackerCore

/// The panel that drops down from the menu bar icon.
struct TrackerPanel: View {
    @ObservedObject var model: TrackerViewModel

    @State private var editingTargets = false
    @State private var dailyTargetText = ""
    @State private var weeklyTargetText = ""

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
            // The name box handles Return itself; only let Return press this button when no box is showing,
            // so one key press can never both start and stop the timer.
            .keyboardShortcut(model.isRunning && !editingTargets ? KeyboardShortcut.defaultAction : nil)

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
                .onSubmit(model.start)

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
                if !editingTargets {
                    Button(hasTargets(summary.project) ? "Edit targets" : "Set targets") {
                        beginEditingTargets(summary.project)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
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
        }
        // Don't keep editing one project's targets after switching to another.
        .onChange(of: summary.project.id) { _ in editingTargets = false }
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
