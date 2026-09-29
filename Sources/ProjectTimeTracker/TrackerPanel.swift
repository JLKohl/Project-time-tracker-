import AppKit
import SwiftUI
import TimeTrackerCore

/// The panel that drops down from the menu bar icon.
struct TrackerPanel: View {
    @ObservedObject var model: TrackerViewModel

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
            .keyboardShortcut(.defaultAction)

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
        VStack(alignment: .leading, spacing: 6) {
            Text(summary.project.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 0) {
                total("Today", summary.dayTotal)
                total("This week", summary.weekTotal)
                total("All time", summary.allTimeTotal)
            }
        }
    }

    private func total(_ title: String, _ value: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(DurationFormat.hoursMinutes(value))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
