import AppKit
import SwiftUI

/// A small window manager for an agent app.
///
/// A menu bar app has no main window and no Dock icon, so windows have to be
/// created, focused and reused by hand. Each window is kept alive here so that
/// reopening Settings returns to the tab you were on instead of a fresh instance.
@MainActor
final class HostingWindowController<Content: View> {

    private var window: NSWindow?
    private let title: String
    private let makeContent: () -> Content
    private let isResizable: Bool

    init(title: String, isResizable: Bool = false, content: @escaping () -> Content) {
        self.title = title
        self.makeContent = content
        self.isResizable = isResizable
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window

        // An accessory app has to activate explicitly, otherwise the window opens
        // behind whatever the user is doing.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.center()
    }

    func close() {
        window?.performClose(nil)
    }

    private func makeWindow() -> NSWindow {
        var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if isResizable { styleMask.insert(.resizable) }

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 480, height: 440),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: makeContent())
        window.setContentSize(window.contentViewController?.view.fittingSize ?? window.frame.size)
        return window
    }
}
