import SwiftUI
import AppKit
import WattsonCore

/// The popover that opens from the menu bar: everything about the machine's power,
/// in one screen, with the mascot doing the talking.
@MainActor
struct DashboardView: View {

    @ObservedObject var monitor: PowerMonitor
    @ObservedObject var preferencesStore: PreferencesStore
    @ObservedObject var store: StoreManager
    @ObservedObject var overlay: RunnerOverlayController
    let actions: AppActions

    @State private var historyWindow: HistoryWindow = .hour
    @State private var showsDiagnostics = false
    /// Snapshotted when the inspector is opened: reading the registry on every
    /// body evaluation would be a needless IOKit call per frame.
    @State private var diagnostics: [String: String] = [:]

    private var snapshot: PowerSnapshot { monitor.snapshot }
    private var preferences: Preferences { preferencesStore.preferences }
    private var isPro: Bool { store.isPro }

    enum HistoryWindow: String, CaseIterable, Identifiable {
        case hour = "1h"
        case day = "24h"
        case week = "7d"
        case month = "30d"

        var id: String { rawValue }
        var interval: TimeInterval {
            switch self {
            case .hour: return 3600
            case .day: return 24 * 3600
            case .week: return 7 * 24 * 3600
            case .month: return 30 * 24 * 3600
            }
        }
        var requiresPro: Bool { self != .hour }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Design.sectionSpacing) {
                header
                gauges
                statRow
                historyCard
                healthCard
                if snapshot.chargeState.isPluggedIn { adapterCard }
                techCard
                if !isPro { upsellCard }
                footer
            }
            .padding(14)
        }
        .frame(width: Design.panelWidth)
        .frame(maxHeight: 640)
        .background(backgroundGradient)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            MascotView(
                mood: monitor.mood,
                skin: preferences.mascotSkin,
                level: snapshot.fraction,
                intensity: PowerMath.intensity(forWatts: snapshot.systemDrawWatts)
            )
            .frame(width: 76, height: 92)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Wattson")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(monitor.mood.badgeTitle)
                        .font(.system(size: 9, weight: .bold))
                        .textCase(.uppercase)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(monitor.mood.tint.opacity(0.18), in: Capsule())
                        .foregroundStyle(monitor.mood.tint)
                    if isPro { ProBadge() }
                }

                Text(Fmt.headline(for: snapshot))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SpeechBubble(
                    text: MascotMoodResolver.line(
                        for: monitor.mood,
                        seed: MascotMoodResolver.dialogueSeed()
                    ),
                    tint: monitor.mood.tint
                )
            }
        }
    }

    // MARK: - Gauges

    private var gauges: some View {
        Card(tint: monitor.mood.tint) {
            HStack(spacing: 16) {
                RingGauge(
                    fraction: snapshot.fraction,
                    tint: monitor.mood.tint,
                    centreTop: Fmt.percent(snapshot.percentage),
                    centreBottom: Fmt.stateTitle(snapshot.chargeState)
                )
                .frame(width: 96, height: 96)

                FlowMeter(
                    watts: snapshot.systemDrawWatts,
                    confidence: snapshot.drawConfidence,
                    tint: monitor.mood.tint,
                    explanation: monitor.drawExplanation,
                    ceiling: ceiling
                )
            }
        }
    }

    /// Scale the wattage bar to the adapter when plugged in, and to a sensible
    /// laptop ceiling when on battery, so the bar means something in both cases.
    private var ceiling: Double {
        if let adapterWatts = snapshot.adapter?.negotiatedWatts, snapshot.chargeState.isPluggedIn {
            return max(adapterWatts, 20)
        }
        return 60
    }

    // MARK: - Stats

    private var statRow: some View {
        Card {
            HStack(alignment: .top, spacing: 10) {
                StatTile(
                    title: snapshot.chargeState == .charging ? "Until full" : "Remaining",
                    value: Fmt.duration(snapshot.chargeState == .charging ? snapshot.timeToFull : monitor.projectedRuntime),
                    systemImage: "clock",
                    tint: monitor.mood.tint,
                    help: "macOS's own estimate where available, otherwise projected from measured draw and remaining energy."
                )
                Divider().frame(height: 30)
                StatTile(
                    title: "Battery flow",
                    value: Fmt.flow(snapshot.batteryFlowWatts),
                    systemImage: "arrow.up.arrow.down",
                    tint: monitor.mood.tint,
                    help: "Positive is energy going into the cell, negative is energy coming out. Always measured."
                )
                Divider().frame(height: 30)
                StatTile(
                    title: "Energy left",
                    value: Fmt.wattHours(snapshot.remainingWattHours),
                    systemImage: "bolt.badge.clock",
                    tint: monitor.mood.tint,
                    help: "Charge remaining in the cell, in watt-hours."
                )
            }
        }
    }

    // MARK: - History

    private var historyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Power history", systemImage: "chart.xyaxis.line")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Picker("", selection: $historyWindow) {
                        ForEach(HistoryWindow.allCases) { window in
                            Text(window.rawValue).tag(window)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 170)
                    .onChange(of: historyWindow) { newValue in
                        // Longer windows are a Pro feature; bounce back with the
                        // paywall rather than silently showing an empty chart.
                        if newValue.requiresPro, !isPro {
                            historyWindow = .hour
                            actions.openPaywall()
                        }
                    }
                }

                PowerSparkline(
                    samples: monitor.sparkline(window: historyWindow.interval, buckets: 90),
                    tint: monitor.mood.tint
                )
                .frame(height: 62)

                let stats = monitor.stats(window: historyWindow.interval)
                HStack(spacing: 10) {
                    StatTile(title: "Average", value: Fmt.watts(stats.averageDrawWatts))
                    StatTile(title: "Peak", value: Fmt.watts(stats.peakDrawWatts))
                    StatTile(title: "Energy used", value: Fmt.wattHours(stats.energyWattHours))
                    StatTile(
                        title: "Drain",
                        value: stats.dischargeRatePerHour.map { String(format: "%.1f%%/h", $0) } ?? Fmt.placeholder
                    )
                }
            }
        }
    }

    // MARK: - Health

    private var healthCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("Battery health", systemImage: "heart.text.square")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text(snapshot.health.grade.label)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(healthTint.opacity(0.16), in: Capsule())
                        .foregroundStyle(healthTint)
                }

                DetailRow(
                    label: "Maximum capacity",
                    value: Fmt.percent(snapshot.health.maximumCapacityPercent, decimals: 1)
                )
                DetailRow(
                    label: "Cycle count",
                    value: snapshot.health.cycleCount.map(String.init) ?? Fmt.placeholder
                )
                DetailRow(
                    label: "Temperature",
                    value: Fmt.temperature(snapshot.health.temperatureCelsius, unit: preferences.temperatureUnit)
                )
                DetailRow(
                    label: "Full charge capacity",
                    value: Fmt.milliampHours(snapshot.health.fullChargeCapacityMilliampHours)
                )
            }
        }
    }

    private var healthTint: Color {
        switch snapshot.health.grade {
        case .excellent, .good: return Color(red: 0.24, green: 0.72, blue: 0.45)
        case .fair: return Color(red: 0.95, green: 0.65, blue: 0.18)
        case .serviceNeeded: return Color(red: 0.93, green: 0.30, blue: 0.32)
        case .unknown: return .secondary
        }
    }

    // MARK: - Adapter

    private var adapterCard: some View {
        Card(tint: Color(red: 0.25, green: 0.72, blue: 0.95)) {
            VStack(alignment: .leading, spacing: 7) {
                Label("Power adapter", systemImage: "powerplug")
                    .font(.system(size: 11, weight: .semibold))

                DetailRow(label: "Adapter", value: snapshot.adapter?.displayName ?? Fmt.placeholder)
                DetailRow(
                    label: "Negotiated",
                    value: snapshot.adapter?.negotiatedWatts.map { Fmt.watts($0, decimals: 0) } ?? Fmt.placeholder
                )
                DetailRow(
                    label: "Voltage / current",
                    value: "\(Fmt.volts(snapshot.adapter?.volts)) · \(Fmt.amps(snapshot.adapter?.amps))"
                )
                if snapshot.chargeState == .chargingPaused {
                    Text("macOS is holding the charge level to protect the battery. Charging resumes on its own.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Tech

    private var techCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("This machine", systemImage: "cpu")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    if snapshot.isLowPowerMode {
                        Text("Low Power Mode")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.16), in: Capsule())
                            .foregroundStyle(.purple)
                    }
                }

                Text(monitor.device.summaryLine)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                DetailRow(label: "Cell voltage", value: Fmt.volts(snapshot.volts))
                DetailRow(label: "Cell current", value: Fmt.amps(snapshot.amps))

                Button {
                    guard isPro else {
                        actions.openPaywall()
                        return
                    }
                    showsDiagnostics.toggle()
                    if showsDiagnostics { diagnostics = monitor.rawDiagnostics() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: showsDiagnostics ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                        Text("Raw IOKit inspector")
                            .font(.system(size: 10, weight: .medium))
                        if !isPro { ProBadge() }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                if showsDiagnostics, isPro {
                    DiagnosticsTable(properties: diagnostics)
                }
            }
        }
    }

    // MARK: - Upsell & footer

    private var upsellCard: some View {
        Card(tint: Color(red: 0.98, green: 0.72, blue: 0.20)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color(red: 0.96, green: 0.60, blue: 0.20))
                    Text("Wattson Pro")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                Text("Skins, 30-day history, custom alerts, deep diagnostics and export. Wattson stays fully usable without it.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("See what's included") { actions.openPaywall() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                overlay.toggle(autoHideAfter: preferences.runnerAutoHideSeconds)
            } label: {
                Label(overlay.isVisible ? "Stop runner" : "Send for a run", systemImage: "figure.run")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            Button { actions.openSettings() } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")

            Menu {
                Button("About Wattson") { actions.openAbout() }
                Button("Clear history") { monitor.clearHistory() }
                Divider()
                Button("Quit Wattson") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .help("More")
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [monitor.mood.tint.opacity(0.10), .clear],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
    }
}

/// The Pro diagnostics table: every property the battery node publishes, searchable.
@MainActor
struct DiagnosticsTable: View {

    let properties: [String: String]
    @State private var query = ""

    private var rows: [(key: String, value: String)] {
        properties
            .filter { query.isEmpty || $0.key.localizedCaseInsensitiveContains(query) }
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, value: $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Filter properties", text: $query)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10))

            if rows.isEmpty {
                Text(properties.isEmpty
                     ? "This Mac does not publish an AppleSmartBattery node."
                     : "No property matches that filter.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(rows, id: \.key) { row in
                            HStack(alignment: .top) {
                                Text(row.key)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 6)
                                Text(row.value)
                                    .font(.system(size: 9, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                .frame(height: 130)
            }
        }
        .padding(.top, 4)
    }
}
