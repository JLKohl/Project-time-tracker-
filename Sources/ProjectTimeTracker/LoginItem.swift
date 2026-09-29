import Foundation
import ServiceManagement

/// Turns "Open at login" on and off using macOS's Login Items.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var message: String?

    /// Login Items only work for the installed app, not when run from Terminal with `swift run`.
    var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    init() { refresh() }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            message = nil
        } catch {
            message = "Couldn't change Open at Login: \(error.localizedDescription)"
        }
        refresh()
        if SMAppService.mainApp.status == .requiresApproval {
            message = "Allow it in System Settings → General → Login Items."
        }
    }
}
