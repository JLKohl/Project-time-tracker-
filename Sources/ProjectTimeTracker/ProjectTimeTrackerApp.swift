import AppKit
import SwiftUI
import TimeTrackerCore

@main
struct ProjectTimeTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = TrackerViewModel()

    var body: some Scene {
        MenuBarExtra {
            TrackerPanel(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one copy may run, or two copies could overwrite each other's saved time.
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0 != NSRunningApplication.current }
            if !others.isEmpty {
                NSApp.terminate(nil)
                return
            }
        }
        // Live in the menu bar only: no Dock icon.
        NSApp.setActivationPolicy(.accessory)
    }
}

/// The icon in the menu bar. Shows the running time next to it while tracking.
struct MenuBarLabel: View {
    @ObservedObject var model: TrackerViewModel

    var body: some View {
        if let elapsed = model.runningElapsed {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                Text(DurationFormat.clock(elapsed)).monospacedDigit()
            }
        } else {
            Image(systemName: "timer")
        }
    }
}
