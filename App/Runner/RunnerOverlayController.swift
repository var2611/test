import AppKit
import SwiftUI
import Combine
import WattsonCore

/// A borderless, click-through panel pinned to a bottom corner of the screen.
///
/// Details that matter for a good citizen on macOS:
/// * `.nonactivatingPanel` — showing the runner never steals focus from your work;
/// * `ignoresMouseEvents` — the overlay is decoration, so it must never eat a click;
/// * `canJoinAllSpaces` + `.stationary` — it stays put when you switch Spaces;
/// * the window is *closed*, not hidden, when dismissed, so nothing renders and the
///   animation timer stops entirely when the runner is not on screen.
@MainActor
final class RunnerOverlayController: ObservableObject {

    @Published private(set) var isVisible = false

    private var panel: NSPanel?
    private var autoHideTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private let monitor: PowerMonitor
    private let preferencesStore: PreferencesStore

    private static let designSize = CGSize(width: 440, height: 170)
    private static let screenMargin: CGFloat = 18

    init(monitor: PowerMonitor, preferencesStore: PreferencesStore) {
        self.monitor = monitor
        self.preferencesStore = preferencesStore

        // Corner and size are live settings: moving the slider repositions the
        // runner while you watch it.
        preferencesStore.$preferences
            .map { ($0.runnerCorner, $0.runnerScale) }
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] _ in
                Task { @MainActor in self?.reposition() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.reposition() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Visibility

    func toggle(autoHideAfter seconds: Double) {
        isVisible ? hide() : show(autoHideAfter: seconds)
    }

    func show(autoHideAfter seconds: Double) {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        reposition()
        panel.orderFrontRegardless()
        // The refresh boost is a balanced pair, so it is only taken on the
        // hidden → visible transition: clicking the mascot twice must not leave
        // the monitor permanently boosted.
        if !isVisible {
            isVisible = true
            monitor.beginBoost()
        }
        scheduleAutoHide(after: seconds)
        Log.overlay.info("Runner shown")
    }

    func hide() {
        autoHideTask?.cancel()
        autoHideTask = nil
        guard isVisible else { return }

        panel?.orderOut(nil)
        isVisible = false
        monitor.endBoost()
        Log.overlay.info("Runner hidden")
    }

    private func scheduleAutoHide(after seconds: Double) {
        autoHideTask?.cancel()
        autoHideTask = nil
        guard seconds > 0 else { return }

        autoHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    // MARK: - Panel

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: RunnerOverlayController.designSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        panel.isReleasedWhenClosed = false

        let hosting = NSHostingView(
            rootView: RunnerView(monitor: monitor, preferencesStore: preferencesStore)
        )
        hosting.frame = CGRect(origin: .zero, size: RunnerOverlayController.designSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        return panel
    }

    private func reposition() {
        guard let panel else { return }

        // The screen with the menu bar the user just clicked is the right home for
        // the runner; fall back to the main screen if that cannot be determined.
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen else { return }

        let preferences = preferencesStore.preferences
        let scale = preferences.runnerScale
        let size = CGSize(
            width: RunnerOverlayController.designSize.width * scale,
            height: RunnerOverlayController.designSize.height * scale
        )

        let visible = screen.visibleFrame
        let margin = RunnerOverlayController.screenMargin
        let x = preferences.runnerCorner == .bottomLeft
            ? visible.minX + margin
            : visible.maxX - size.width - margin

        panel.setFrame(
            CGRect(x: x, y: visible.minY + margin, width: size.width, height: size.height),
            display: true
        )
    }
}
