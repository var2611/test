import SwiftUI
import AppKit
import WattsonCore

/// Settings, in four tabs. Locked controls are visible but disabled with a Pro
/// badge — hiding paid features makes them undiscoverable, and disabling them
/// explains the offer better than a wall of marketing.
@MainActor
struct SettingsView: View {

    @ObservedObject var preferencesStore: PreferencesStore
    @ObservedObject var store: StoreManager
    @ObservedObject var monitor: PowerMonitor
    @ObservedObject var overlay: RunnerOverlayController
    let notifier: NotificationService
    let actions: AppActions

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var notificationsDenied = false
    @State private var exportFormat: Exporter.Format = .csv

    private var isPro: Bool { store.isPro }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            appearanceTab
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            alertsTab
                .tabItem { Label("Alerts", systemImage: "bell") }
            proTab
                .tabItem { Label("Pro", systemImage: "sparkles") }
        }
        .frame(width: 460, height: 430)
        .task {
            notificationsDenied = await notifier.isDenied()
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch Wattson at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        launchAtLogin = LaunchAtLogin.set(newValue)
                        preferencesStore.update { $0.launchAtLogin = launchAtLogin }
                    }
                ))
                if LaunchAtLogin.requiresApproval {
                    Text("macOS is waiting for you to allow Wattson in System Settings → General → Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Menu bar") {
                Toggle("Show percentage", isOn: binding(\.menuBarDisplay.showPercentage))
                Toggle("Show live watts", isOn: binding(\.menuBarDisplay.showWatts))
                lockedToggle(
                    "Show time remaining",
                    isOn: binding(\.menuBarDisplay.showTimeRemaining),
                    feature: .menuBarCustomisation
                )
                Toggle("Clicking the mascot sends it for a run", isOn: binding(\.showRunnerOnIconClick))
            }

            Section("Refresh") {
                LabeledContent("On adapter") {
                    Stepper(
                        "\(Int(preferencesStore.preferences.refreshIntervalOnAdapter)) s",
                        value: binding(\.refreshIntervalOnAdapter),
                        in: 1...60,
                        step: 1
                    )
                }
                LabeledContent("On battery") {
                    Stepper(
                        "\(Int(preferencesStore.preferences.refreshIntervalOnBattery)) s",
                        value: binding(\.refreshIntervalOnBattery),
                        in: 2...120,
                        step: 1
                    )
                }
                Text("Longer intervals use less energy. Wattson refreshes instantly whenever the power source changes, whatever this is set to.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Units") {
                Picker("Temperature", selection: binding(\.temperatureUnit)) {
                    Text("Celsius").tag(TemperatureUnit.celsius)
                    Text("Fahrenheit").tag(TemperatureUnit.fahrenheit)
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Appearance

    private var appearanceTab: some View {
        Form {
            Section("Mascot skin") {
                Picker("Skin", selection: skinBinding) {
                    ForEach(MascotSkin.allCases, id: \.self) { skin in
                        Text(skin.title + (skin.requiresPro && !isPro ? "  (Pro)" : "")).tag(skin)
                    }
                }
                skinPreviewStrip
            }

            Section("Corner runner") {
                Picker("Character", selection: runnerBinding) {
                    ForEach(RunnerCharacter.allCases, id: \.self) { character in
                        Text(character.title + (character.requiresPro && !isPro ? "  (Pro)" : "")).tag(character)
                    }
                }
                Picker("Corner", selection: binding(\.runnerCorner)) {
                    ForEach(ScreenCorner.allCases, id: \.self) { corner in
                        Text(corner.title).tag(corner)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Auto-hide") {
                    Stepper(
                        preferencesStore.preferences.runnerAutoHideSeconds == 0
                            ? "Never"
                            : "\(Int(preferencesStore.preferences.runnerAutoHideSeconds)) s",
                        value: binding(\.runnerAutoHideSeconds),
                        in: 0...120,
                        step: 5
                    )
                }

                lockedSlider("Size", value: binding(\.runnerScale), range: 0.6...2.0, feature: .runnerPlayground)
                lockedSlider("Speed", value: binding(\.runnerSpeedMultiplier), range: 0.5...2.5, feature: .runnerPlayground)
                Toggle("Confetti when fully charged", isOn: binding(\.confettiEnabled))

                Button("Preview the runner") {
                    overlay.show(autoHideAfter: max(preferencesStore.preferences.runnerAutoHideSeconds, 8))
                }
            }
        }
        .formStyle(.grouped)
    }

    private var skinPreviewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(MascotSkin.allCases, id: \.self) { skin in
                    VStack(spacing: 4) {
                        MascotView(
                            mood: monitor.mood,
                            skin: skin,
                            level: monitor.snapshot.fraction,
                            intensity: 0.5,
                            staticPhase: 1.4
                        )
                        .frame(width: 46, height: 56)
                        .opacity(skin.requiresPro && !isPro ? 0.45 : 1)

                        Text(skin.title)
                            .font(.system(size: 9))
                            .foregroundStyle(preferencesStore.preferences.mascotSkin == skin ? .primary : .secondary)
                    }
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(preferencesStore.preferences.mascotSkin == skin
                                  ? Color.accentColor.opacity(0.15)
                                  : Color.clear)
                    )
                    .onTapGesture { select(skin: skin) }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Alerts

    private var alertsTab: some View {
        Form {
            if notificationsDenied {
                Section {
                    Text("Notifications are turned off for Wattson in System Settings → Notifications. These switches will have no effect until they are turned back on.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Toggle("Enable alerts", isOn: binding(\.alertsEnabled))
                    .onChange(of: preferencesStore.preferences.alertsEnabled) { enabled in
                        guard enabled else { return }
                        Task { await notifier.requestAuthorizationIfNeeded() }
                    }
            }

            Section("Battery level") {
                LabeledContent("Low battery") {
                    Stepper(
                        "\(Int(preferencesStore.preferences.lowBatteryPercent))%",
                        value: binding(\.lowBatteryPercent),
                        in: 5...50,
                        step: 5
                    )
                    .disabled(!isPro)
                }
                LabeledContent("Critical battery") {
                    Stepper(
                        "\(Int(preferencesStore.preferences.criticalBatteryPercent))%",
                        value: binding(\.criticalBatteryPercent),
                        in: 2...30,
                        step: 1
                    )
                    .disabled(!isPro)
                }
                if !isPro {
                    HStack {
                        ProBadge()
                        Text("Custom thresholds are part of Pro. The free defaults (20% and 8%) stay active.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Events") {
                Toggle("Fully charged", isOn: binding(\.notifyOnFullyCharged))
                Toggle("Plugged in / unplugged", isOn: binding(\.notifyOnPowerSourceChange))
                lockedToggle("Heavy power draw", isOn: binding(\.notifyOnHighDraw), feature: .customAlerts)
                if preferencesStore.preferences.notifyOnHighDraw {
                    LabeledContent("Draw threshold") {
                        Stepper(
                            "\(Int(preferencesStore.preferences.highDrawWatts)) W",
                            value: binding(\.highDrawWatts),
                            in: 10...150,
                            step: 5
                        )
                    }
                }
                lockedToggle("Battery running warm", isOn: binding(\.notifyOnHighTemperature), feature: .customAlerts)
            }

            Section("Quiet hours") {
                lockedToggle("Silence non-critical alerts", isOn: binding(\.quietHoursEnabled), feature: .quietHours)
                if preferencesStore.preferences.quietHoursEnabled {
                    LabeledContent("From") {
                        Stepper("\(preferencesStore.preferences.quietHoursStartHour):00", value: binding(\.quietHoursStartHour), in: 0...23)
                    }
                    LabeledContent("Until") {
                        Stepper("\(preferencesStore.preferences.quietHoursEndHour):00", value: binding(\.quietHoursEndHour), in: 0...23)
                    }
                    Text("Critical battery alerts are always delivered.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Pro

    private var proTab: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    MascotView(mood: .fullAndSmug, skin: preferencesStore.preferences.mascotSkin, level: 1, staticPhase: 0.8)
                        .frame(width: 44, height: 54)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isPro ? "Wattson Pro is active" : "Wattson Pro")
                            .font(.headline)
                        Text(isPro
                             ? subscriptionSummary
                             : "Skins, 30-day history, custom alerts, diagnostics and export.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            Section {
                if isPro {
                    Button("Manage subscription") { store.showManageSubscriptions() }
                } else {
                    Button("See plans") { actions.openPaywall() }
                        .buttonStyle(.borderedProminent)
                }
                Button("Restore purchases") {
                    Task { await store.restore() }
                }
            }

            Section("History") {
                LabeledContent("Keep history for") {
                    Stepper(
                        "\(preferencesStore.preferences.historyRetentionDays) days",
                        value: binding(\.historyRetentionDays),
                        in: 1...90,
                        step: 1
                    )
                    .disabled(!isPro)
                }
                HStack {
                    Picker("Export as", selection: $exportFormat) {
                        ForEach(Exporter.Format.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .frame(width: 160)
                    Button("Export…") {
                        guard isPro else {
                            actions.openPaywall()
                            return
                        }
                        Exporter.export(
                            history: monitor.history,
                            window: preferencesStore.preferences.historyRetentionInterval,
                            format: exportFormat
                        )
                    }
                    if !isPro { ProBadge() }
                }
                Button("Clear history", role: .destructive) { monitor.clearHistory() }
            }

            Section {
                Text("Wattson has no account and no server. Your entitlement comes from the App Store, and nothing about your machine ever leaves it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var subscriptionSummary: String {
        if store.isInGracePeriod {
            return "Renewal is being retried by the App Store. Pro stays on in the meantime."
        }
        if let expiry = store.expirationDate {
            return "Renews \(expiry.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Thank you — you own Wattson Pro outright."
    }

    // MARK: - Helpers

    private func binding<T>(_ keyPath: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(
            get: { preferencesStore.preferences[keyPath: keyPath] },
            set: { newValue in preferencesStore.update { $0[keyPath: keyPath] = newValue } }
        )
    }

    private var skinBinding: Binding<MascotSkin> {
        Binding(
            get: { preferencesStore.preferences.mascotSkin },
            set: { select(skin: $0) }
        )
    }

    private var runnerBinding: Binding<RunnerCharacter> {
        Binding(
            get: { preferencesStore.preferences.runnerCharacter },
            set: { character in
                guard !character.requiresPro || isPro else {
                    actions.openPaywall()
                    return
                }
                preferencesStore.update { $0.runnerCharacter = character }
            }
        )
    }

    private func select(skin: MascotSkin) {
        guard !skin.requiresPro || isPro else {
            actions.openPaywall()
            return
        }
        preferencesStore.update { $0.mascotSkin = skin }
    }

    @ViewBuilder
    private func lockedToggle(_ title: String, isOn: Binding<Bool>, feature: ProFeature) -> some View {
        HStack {
            Toggle(title, isOn: Binding(
                get: { isOn.wrappedValue && isPro },
                set: { newValue in
                    guard isPro else {
                        actions.openPaywall()
                        return
                    }
                    isOn.wrappedValue = newValue
                }
            ))
            if !isPro {
                ProBadge()
                    .onTapGesture { actions.openPaywall() }
            }
        }
    }

    @ViewBuilder
    private func lockedSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        feature: ProFeature
    ) -> some View {
        HStack {
            Slider(value: value, in: range) {
                Text(title)
            }
            .disabled(!isPro)
            if !isPro {
                ProBadge()
                    .onTapGesture { actions.openPaywall() }
            }
        }
    }
}
