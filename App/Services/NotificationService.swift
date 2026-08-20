import Foundation
import UserNotifications
import WattsonCore

/// Posts the alerts that `AlertEngine` decides on.
///
/// The service deliberately contains no policy: it does not decide *whether* to
/// notify, only how to hand a decision to the system. Authorisation is requested
/// lazily, the first time an alert actually needs to go out, so a user who never
/// hits a threshold is never prompted.
@MainActor
final class NotificationService {

    private enum Authorization {
        case unknown, granted, denied
    }

    private var authorization: Authorization = .unknown
    private var isRequesting = false
    private let center: UNUserNotificationCenter?

    init() {
        // `UNUserNotificationCenter.current()` traps in a process without a bundle
        // identifier (unit test runners, some preview hosts), so it is guarded.
        center = Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    /// Asks for permission up front, from a place in the UI where the user has just
    /// switched alerts on and the prompt makes sense.
    func requestAuthorizationIfNeeded() async {
        guard let center, authorization == .unknown, !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorization = .granted
            return
        case .denied:
            authorization = .denied
            return
        case .notDetermined:
            break
        @unknown default:
            break
        }

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            authorization = granted ? .granted : .denied
        } catch {
            Log.notifications.error("Authorisation request failed: \(error.localizedDescription, privacy: .public)")
            authorization = .denied
        }
    }

    func post(_ alert: AlertRequest) {
        guard let center else { return }

        Task { @MainActor in
            await requestAuthorizationIfNeeded()
            guard authorization == .granted else { return }

            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = alert.isTimeSensitive ? .defaultCritical : .default
            if alert.isTimeSensitive {
                content.interruptionLevel = .timeSensitive
            }
            content.threadIdentifier = alert.kind.rawValue

            let request = UNNotificationRequest(
                identifier: "\(alert.kind.rawValue).\(UUID().uuidString)",
                content: content,
                trigger: nil
            )

            do {
                try await center.add(request)
            } catch {
                Log.notifications.error("Could not post \(alert.kind.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// True when the user has actively turned notifications off in System Settings,
    /// so the settings screen can explain why the toggles are doing nothing.
    func isDenied() async -> Bool {
        guard let center else { return false }
        return await center.notificationSettings().authorizationStatus == .denied
    }
}
