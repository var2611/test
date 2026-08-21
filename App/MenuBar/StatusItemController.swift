import AppKit
import SwiftUI
import Combine
import WattsonCore

/// An `NSHostingView` that refuses to intercept clicks, so the status item button
/// underneath still receives them. Without this the mascot would eat every click and
/// the menu bar item would appear dead.
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Owns the menu bar item: the animated mascot, the click behaviour, the dashboard
/// popover and the right-click menu.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {

    private let statusItem: NSStatusItem
    private let monitor: PowerMonitor
    private let preferencesStore: PreferencesStore
    private let store: StoreManager
    private let overlay: RunnerOverlayController
    private let actions: AppActions

    private var popover: NSPopover?
    private var hostingView: NSView?
    private var cancellables = Set<AnyCancellable>()

    init(
        monitor: PowerMonitor,
        preferencesStore: PreferencesStore,
        store: StoreManager,
        overlay: RunnerOverlayController,
        actions: AppActions
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.monitor = monitor
        self.preferencesStore = preferencesStore
        self.store = store
        self.overlay = overlay
        self.actions = actions
        super.init()

        installView()
        observeForWidthChanges()
    }

    // MARK: - Setup

    private func installView() {
        guard let button = statusItem.button else {
            Log.menuBar.error("The status item has no button; the menu bar is unavailable.")
            return
        }

        let root = MenuBarMascotView(monitor: monitor, preferencesStore: preferencesStore)
        let hosting = PassthroughHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hosting)

        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: button.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])

        hostingView = hosting
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("Wattson power status")

        updateLength()
    }

    /// The item is variable-length, so its width has to be recomputed whenever the
    /// text inside it changes shape.
    private func observeForWidthChanges() {
        monitor.$snapshot
            .map { snapshot in
                "\(Int(snapshot.percentage))|\(Int((snapshot.systemDrawWatts ?? 0) * 10))|\(snapshot.chargeState.rawValue)"
            }
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.updateLength() }
            }
            .store(in: &cancellables)

        preferencesStore.$preferences
            .map(\.menuBarDisplay)
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.updateLength() }
            }
            .store(in: &cancellables)
    }

    private func updateLength() {
        guard let hostingView else { return }
        hostingView.invalidateIntrinsicContentSize()
        let width = hostingView.fittingSize.width
        // Clamped so a pathological reading can never claim half the menu bar.
        statusItem.length = min(max(width, 30), 140)
    }

    // MARK: - Interaction

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true

        if isRightClick {
            showMenu()
        } else {
            togglePopover()
            // The headline interaction: tapping the mascot sends it for a lap in the
            // corner of the screen.
            if preferencesStore.preferences.showRunnerOnIconClick {
                overlay.show(autoHideAfter: preferencesStore.preferences.runnerAutoHideSeconds)
            }
        }
    }

    func togglePopover() {
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        // Balanced with `endBoost` in `popoverDidClose`, so re-showing an
        // already-open popover must not take a second boost.
        guard popover?.isShown != true else { return }

        let popover = self.popover ?? makePopover()
        self.popover = popover

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        // Bring the popover forward without stealing focus from the user's work
        // any longer than the popover itself is on screen.
        popover.contentViewController?.view.window?.makeKey()
        monitor.beginBoost()
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(
                monitor: monitor,
                preferencesStore: preferencesStore,
                store: store,
                overlay: overlay,
                actions: actions
            )
            .frame(width: Design.panelWidth)
        )
        return popover
    }

    func popoverDidClose(_ notification: Notification) {
        monitor.endBoost()
    }

    // MARK: - Right-click menu

    private func showMenu() {
        let menu = NSMenu()

        let status = NSMenuItem(title: Fmt.headline(for: monitor.snapshot), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let draw = NSMenuItem(
            title: "System draw: \(Fmt.watts(monitor.snapshot.systemDrawWatts)) (\(monitor.snapshot.drawConfidence.badge))",
            action: nil,
            keyEquivalent: ""
        )
        draw.isEnabled = false
        menu.addItem(draw)
        menu.addItem(.separator())

        menu.addItem(withTitleAndAction("Open Dashboard", #selector(menuOpenDashboard)))
        menu.addItem(
            withTitleAndAction(
                overlay.isVisible ? "Stop the Runner" : "Send Wattson for a Run",
                #selector(menuToggleRunner)
            )
        )
        menu.addItem(.separator())
        menu.addItem(withTitleAndAction("Settings…", #selector(menuOpenSettings), key: ","))

        if !store.isPro {
            menu.addItem(withTitleAndAction("Unlock Wattson Pro…", #selector(menuOpenPaywall)))
        }

        menu.addItem(.separator())
        menu.addItem(withTitleAndAction("About Wattson", #selector(menuAbout)))
        menu.addItem(withTitleAndAction("Quit Wattson", #selector(menuQuit), key: "q"))

        // Attaching the menu and immediately clicking is the supported way to show a
        // menu from a status item that also handles plain clicks.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func withTitleAndAction(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func menuOpenDashboard() { showPopover() }
    @objc private func menuToggleRunner() {
        overlay.toggle(autoHideAfter: preferencesStore.preferences.runnerAutoHideSeconds)
    }
    @objc private func menuOpenSettings() { actions.openSettings() }
    @objc private func menuOpenPaywall() { actions.openPaywall() }
    @objc private func menuAbout() { actions.openAbout() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
}

/// App-level commands the menu bar and the dashboard both need. Passing this
/// around keeps views from reaching for `NSApp.delegate` and casting.
@MainActor
final class AppActions {
    var openSettings: () -> Void = {}
    var openPaywall: () -> Void = {}
    var openAbout: () -> Void = {}
}
