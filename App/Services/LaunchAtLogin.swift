import Foundation
import ServiceManagement

/// Wraps `SMAppService`, which is the only login-item mechanism allowed for a
/// sandboxed, App Store-distributed app on macOS 13 and later.
enum LaunchAtLogin {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns the state that actually took effect, so the UI can correct its toggle
    /// when macOS refuses (for example when the user has denied the login item in
    /// System Settings → General → Login Items).
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            Log.settings.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
        }
        return isEnabled
    }

    /// `requiresApproval` means macOS has the login item registered but the user has
    /// switched it off; the app should say so rather than silently disagree.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }
}
