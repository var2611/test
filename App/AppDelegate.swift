import AppKit
import SwiftUI
import Combine
import WattsonCore

/// Wires the app together and owns everything with a lifetime.
///
/// The composition is done by hand rather than with a dependency framework: there
/// are nine objects, they are created once, and being able to read the whole graph
/// in one screen is worth more here than indirection.
///
/// The app starts from AppKit rather than a SwiftUI `App` scene: it is an agent
/// (`LSUIElement`) with no main window, and window management has to be explicit.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let preferencesStore = PreferencesStore()
    private let historyStore = HistoryStore()
    private let notifier = NotificationService()
    private let store = StoreManager()
    private let actions = AppActions()

    private var monitor: PowerMonitor!
    private var overlay: RunnerOverlayController!
    private var statusItem: StatusItemController!

    private var settingsWindow: HostingWindowController<SettingsView>?
    private var paywallWindow: HostingWindowController<PaywallView>?
    private var aboutWindow: HostingWindowController<AboutView>?
    private var welcomeWindow: HostingWindowController<WelcomeView>?

    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A menu bar app has no Dock icon and no main window.
        NSApp.setActivationPolicy(.accessory)

        let reader: PowerReading = AppDelegate.isSimulating ? SimulatedPowerReader() : IOKitPowerReader()

        monitor = PowerMonitor(
            reader: reader,
            preferencesStore: preferencesStore,
            historyStore: historyStore,
            notifier: notifier,
            entitlements: store
        )
        overlay = RunnerOverlayController(monitor: monitor, preferencesStore: preferencesStore)
        statusItem = StatusItemController(
            monitor: monitor,
            preferencesStore: preferencesStore,
            store: store,
            overlay: overlay,
            actions: actions
        )

        wireActions()
        observeEntitlement()

        monitor.start()

        Task { await store.bootstrap() }

        if !preferencesStore.hasCompletedWelcome {
            showWelcome()
        }

        Log.power.info("Wattson launched on \(self.monitor.device.chipName, privacy: .public)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        historyStore.flush()
    }

    /// Clicking the app in Finder while it is already running should show something,
    /// otherwise it looks like nothing happened.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem?.togglePopover()
        return true
    }

    // MARK: - Composition

    private static var isSimulating: Bool {
        CommandLine.arguments.contains("--simulate")
            || ProcessInfo.processInfo.environment["WATTSON_SIMULATE"] == "1"
    }

    private func wireActions() {
        actions.openSettings = { [weak self] in self?.showSettings() }
        actions.openPaywall = { [weak self] in self?.showPaywall() }
        actions.openAbout = { [weak self] in self?.showAbout() }
    }

    /// Pro settings must not survive a lapsed subscription, and buying Pro should
    /// take effect without a relaunch. Both directions are handled here.
    private func observeEntitlement() {
        store.$hasVerifiedEntitlement
            .removeDuplicates()
            .sink { [weak self] isPro in
                Task { @MainActor in
                    guard let self else { return }
                    if !isPro { self.preferencesStore.enforceFreeTier() }
                    self.monitor?.refresh()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Windows

    private func showSettings() {
        let controller = settingsWindow ?? HostingWindowController(title: "Wattson Settings", isResizable: false) { [self] in
            SettingsView(
                preferencesStore: preferencesStore,
                store: store,
                monitor: monitor,
                overlay: overlay,
                notifier: notifier,
                actions: actions
            )
        }
        settingsWindow = controller
        controller.show()
    }

    private func showPaywall() {
        let controller = paywallWindow ?? HostingWindowController(title: "Wattson Pro") { [self] in
            PaywallView(store: store) { [weak self] in
                self?.paywallWindow?.close()
            }
        }
        paywallWindow = controller
        controller.show()
    }

    private func showAbout() {
        let controller = aboutWindow ?? HostingWindowController(title: "About Wattson") { [self] in
            AboutView(device: monitor.device)
        }
        aboutWindow = controller
        controller.show()
    }

    private func showWelcome() {
        let controller = welcomeWindow ?? HostingWindowController(title: "Welcome to Wattson") { [self] in
            WelcomeView(
                onFinish: { [weak self] in
                    self?.preferencesStore.hasCompletedWelcome = true
                    self?.welcomeWindow?.close()
                    self?.statusItem?.togglePopover()
                },
                onPreviewRunner: { [weak self] in
                    self?.overlay.show(autoHideAfter: 12)
                }
            )
        }
        welcomeWindow = controller
        controller.show()
    }
}
