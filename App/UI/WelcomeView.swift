import SwiftUI
import WattsonCore

/// Shown once, on first launch. A menu bar app that appears with no window and no
/// Dock icon is a menu bar app people never find, so this points at the icon,
/// explains the one interaction that is not obvious, and gets out of the way.
@MainActor
struct WelcomeView: View {

    var onFinish: () -> Void
    var onPreviewRunner: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                MascotView(mood: .sipping, skin: .classic, level: 0.68, staticPhase: 0.9)
                    .frame(width: 64, height: 78)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hello, I'm Wattson.")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    Text("I live in your menu bar and watch where your power comes from and where it goes.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                row("bolt.fill", "Watts, not vibes",
                    "Live system draw — measured from the cell on battery, estimated from the adapter when plugged in. Every figure says which it is.")
                row("face.smiling", "Moods you can read at a glance",
                    "Sipping while charging, sunglasses at 100%, sweating at 15%, on fire when the fans spin up.")
                row("figure.run", "Click the mascot to send it for a run",
                    "A character sprints across the corner of your screen at the speed of your power draw.")
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.07)))

            Text("No account, no sign-in, no data leaves this Mac.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            HStack {
                Button("Show me the run") { onPreviewRunner() }
                Spacer()
                Button("Start using Wattson") { onFinish() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The About window. Kept separate from `NSApplication.orderFrontStandardAboutPanel`
/// so it can carry the mascot and the honest description of what the app measures.
@MainActor
struct AboutView: View {

    let device: DeviceInfo

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 12) {
            MascotView(mood: .chill, skin: .classic, level: 0.8, staticPhase: 1.2)
                .frame(width: 70, height: 84)

            Text("Wattson")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text(version)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text(device.summaryLine)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            Text("Wattson reads only public, sandbox-safe power APIs: IOPowerSources and the AppleSmartBattery registry node. It uses no private frameworks, collects nothing, and makes no network requests of its own.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(width: 340)
    }
}
