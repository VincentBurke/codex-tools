import AppKit
import SwiftUI

final class ManageWindowController: NSWindowController, NSWindowDelegate {
    private let onVisibilityChanged: (Bool) -> Void

    init(controller: AppController, onVisibilityChanged: @escaping (Bool) -> Void) {
        self.onVisibilityChanged = onVisibilityChanged
        let rootView = ManageAccountsView(controller: controller)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Manage Accounts"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 680, height: 520))
        window.minSize = NSSize(width: 560, height: 420)
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showOrFocus() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        onVisibilityChanged(true)
    }

    func windowWillClose(_ notification: Notification) {
        onVisibilityChanged(false)
    }
}
