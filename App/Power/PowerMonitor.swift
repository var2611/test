import Foundation
import Combine
import AppKit
import IOKit.ps
import WattsonCore

/// The heart of the app: turns hardware readings into everything the UI observes.
///
/// One instance exists for the lifetime of the process. It owns the polling
/// cadence, the smoothing, the history recording and the alert evaluation, so that
/// no view has to know how any of that works.
@MainActor
final class PowerMonitor: ObservableObject {

    // MARK: Published state

    @Published private(set) var snapshot: PowerSnapshot = .placeholder
    @Published private(set) var mood: MascotMood = .chill
    @Published private(set) var motion: RunnerMotion = .idle
    @Published private(set) var drawExplanation: String = ""
    @Published private(set) var hasReceivedFirstReading = false

    let device: DeviceInfo

    // MARK: Collaborators

    private let reader: PowerReading
    private let preferencesStore: PreferencesStore
    private let historyStore: HistoryStore
    private let notifier: NotificationService
    private let entitlements: EntitlementProviding

    // MARK: Machinery

    private var smoother = SnapshotSmoother()
    private var alertEngine = AlertEngine()
    private var timer: Timer?
    private var runLoopSource: CFRunLoopSource?
    private var cancellables = Set<AnyCancellable>()
    private var isSleeping = false
    /// Raised while the dashboard or the overlay is on screen: the numbers are
    /// being *watched*, so they are refreshed faster.
    private var boostCount = 0

    init(
        reader: PowerReading,
        preferencesStore: PreferencesStore,
        historyStore: HistoryStore,
        notifier: NotificationService,
        entitlements: EntitlementProviding,
        device: DeviceInfo = .current
    ) {
        self.reader = reader
        self.preferencesStore = preferencesStore
        self.historyStore = historyStore
        self.notifier = notifier
        self.entitlements = entitlements
        self.device = device

        observeSystemEvents()
        observePreferences()
    }

    // MARK: - Lifecycle

    func start() {
        registerForPowerSourceChanges()
        refresh()
        scheduleTimer()
    }

    /// Tears everything down. Called at termination; the monitor otherwise lives for
    /// the whole process lifetime.
    func stop() {
        timer?.invalidate()
        timer = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        historyStore.flush()
    }

    /// Raises the refresh rate while something is actually being looked at, and
    /// returns a token the caller releases when the view goes away.
    func beginBoost() {
        boostCount += 1
        if boostCount == 1 { scheduleTimer() }
    }

    func endBoost() {
        boostCount = max(boostCount - 1, 0)
        if boostCount == 0 { scheduleTimer() }
    }

    // MARK: - Reading

    func refresh() {
        guard !isSleeping else { return }

        let raw = reader.read()
        let smoothed = smoother.smooth(raw)

        let previousState = snapshot.chargeState
        snapshot = smoothed
        hasReceivedFirstReading = true

        let preferences = preferencesStore.preferences
        mood = MascotMoodResolver.mood(for: smoothed, thresholds: preferences.moodThresholds)
        motion = RunnerMotion.motion(
            for: smoothed,
            mood: mood,
            speedMultiplier: entitlements.isPro ? preferences.runnerSpeedMultiplier : 1.0
        )
        drawExplanation = PowerMath.systemDraw(
            chargeState: smoothed.chargeState,
            batteryFlowWatts: smoothed.batteryFlowWatts,
            adapter: smoothed.adapter
        ).explanation

        historyStore.record(smoothed, retention: retentionInterval(for: preferences))

        let alerts = alertEngine.evaluate(
            snapshot: smoothed,
            preferences: preferences,
            isPro: entitlements.isPro
        )
        for alert in alerts {
            notifier.post(alert)
        }

        if previousState != smoothed.chargeState {
            // The cadence depends on whether we are on the adapter, so a state
            // change is also a scheduling change.
            scheduleTimer()
            historyStore.flush()
            Log.power.info("Charge state → \(smoothed.chargeState.rawValue, privacy: .public)")
        }
    }

    private func retentionInterval(for preferences: Preferences) -> TimeInterval {
        // History depth is a Pro feature; free users keep a rolling day.
        entitlements.isPro ? preferences.historyRetentionInterval : 24 * 3600
    }

    // MARK: - Scheduling

    private var currentInterval: TimeInterval {
        let preferences = preferencesStore.preferences
        if boostCount > 0 { return 1 }
        return snapshot.chargeState.isPluggedIn
            ? preferences.refreshIntervalOnAdapter
            : preferences.refreshIntervalOnBattery
    }

    private func scheduleTimer() {
        timer?.invalidate()
        guard !isSleeping else { return }

        let interval = currentInterval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // A menu bar app must keep updating while a menu is tracking, hence
        // .common; the tolerance lets the system coalesce our wake-ups with others,
        // which is what keeps this app off the "apps using significant energy" list.
        timer.tolerance = max(interval * 0.2, 0.25)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - System events

    private func registerForPowerSourceChanges() {
        // Instant reaction to plugging the cable in, instead of waiting for the tick.
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { rawContext in
            guard let rawContext else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(rawContext).takeUnretainedValue()
            Task { @MainActor in monitor.refresh() }
        }

        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else {
            Log.power.error("Could not observe power source changes; falling back to polling only.")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
    }

    private func observeSystemEvents() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        workspaceCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.handleSleep() }
            }
            .store(in: &cancellables)

        workspaceCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.handleWake() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }
            .store(in: &cancellables)

        // Low Power Mode toggling changes the mood and the expected draw.
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            .store(in: &cancellables)
    }

    private func handleSleep() {
        isSleeping = true
        timer?.invalidate()
        timer = nil
        historyStore.flush()
    }

    private func handleWake() {
        isSleeping = false
        // The world may have changed completely during sleep; do not glide from the
        // pre-sleep average down to the post-wake reality.
        smoother.reset()
        refresh()
        scheduleTimer()
    }

    private func observePreferences() {
        preferencesStore.$preferences
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleTimer()
                    self?.refresh()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Derived values for the UI

    var history: PowerHistory { historyStore.history }

    func stats(window: TimeInterval) -> HistoryStats {
        historyStore.history.stats(within: window)
    }

    func sparkline(window: TimeInterval, buckets: Int) -> [PowerSample] {
        historyStore.history.downsampled(within: window, buckets: buckets)
    }

    /// Runtime projection from *our* measured draw rather than macOS's estimate,
    /// used as a fallback when macOS is still calculating.
    var projectedRuntime: TimeInterval? {
        snapshot.timeToEmpty ?? PowerMath.projectedRuntime(
            remainingWattHours: snapshot.remainingWattHours,
            drawWatts: snapshot.systemDrawWatts
        )
    }

    func clearHistory() {
        historyStore.clear()
    }

    func rawDiagnostics() -> [String: String] {
        (reader as? IOKitPowerReader)?.readRawProperties() ?? [:]
    }
}
