import AppKit
import SwiftUI
import TimeTrackerCore

@main
struct ProjectTimeTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            TrackerPanel(model: appDelegate.model)
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Owned here (not by the SwiftUI scene) so the app can show it from outside the menu bar too.
    lazy var model = TrackerViewModel()

    /// Opening the app while it's already running (from Applications, Spotlight or the Dock)
    /// shows the hours window. That way the tracker can always be reached, even when a crowded
    /// menu bar or the camera notch hides its menu bar icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        HoursWindowController.shared.show(model: model)
        return false
    }

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
/// With "Show time in menu bar" off, only the icon shows: a filled stopwatch while a timer runs.
/// That keeps it narrow, so it's less likely to be hidden on a crowded menu bar or behind the notch.
struct MenuBarLabel: View {
    @ObservedObject var model: TrackerViewModel
    @AppStorage(MenuBarLabel.showTimeKey) private var showTime = true

    static let showTimeKey = "showTimeInMenuBar"

    var body: some View {
        if let elapsed = model.runningElapsed {
            if showTime {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                    Text(DurationFormat.clock(elapsed)).monospacedDigit()
                }
            } else {
                Image(systemName: "stopwatch.fill")
            }
        } else {
            Image(systemName: "timer")
        }
    }
}
