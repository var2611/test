import SwiftUI
import WattsonCore

/// What actually rides in the menu bar: the mascot, plus whichever figures the user
/// asked for. Deliberately narrow — a menu bar item that grows without bound is a
/// menu bar item people delete.
@MainActor
struct MenuBarMascotView: View {

    @ObservedObject var monitor: PowerMonitor
    @ObservedObject var preferencesStore: PreferencesStore

    private var preferences: Preferences { preferencesStore.preferences }
    private var snapshot: PowerSnapshot { monitor.snapshot }

    var body: some View {
        HStack(spacing: 3) {
            MascotView(
                mood: monitor.mood,
                skin: preferences.mascotSkin,
                level: snapshot.fraction,
                intensity: PowerMath.intensity(forWatts: snapshot.systemDrawWatts),
                isCompact: true
            )
            .frame(width: 17, height: 20)

            if !readouts.isEmpty {
                Text(readouts)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// e.g. "72% · 11.4W". Rebuilt as a single string so the item's width changes in
    /// one step instead of shuffling as each label appears.
    private var readouts: String {
        var parts: [String] = []
        if preferences.menuBarDisplay.showPercentage {
            parts.append(Fmt.percent(snapshot.percentage))
        }
        if preferences.menuBarDisplay.showWatts, let watts = snapshot.systemDrawWatts {
            parts.append(Fmt.compactWatts(watts))
        }
        if preferences.menuBarDisplay.showTimeRemaining {
            let remaining = snapshot.chargeState == .charging ? snapshot.timeToFull : monitor.projectedRuntime
            if let remaining {
                parts.append(Fmt.duration(remaining))
            }
        }
        return parts.joined(separator: " · ")
    }

    private var accessibilityLabel: String {
        "\(Fmt.stateTitle(snapshot.chargeState)), \(Fmt.percent(snapshot.percentage)), "
            + "\(Fmt.watts(snapshot.systemDrawWatts)). \(monitor.mood.accessibilityDescription)."
    }
}
