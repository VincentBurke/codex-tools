import AppKit
import CodexToolsCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let controller = AppController()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var monitor: Any?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var manageWindowController: ManageWindowController?
    private var isPopoverVisible = false
    private var isManageWindowVisible = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupPopover()

        controller.requestOpenManageWindow = { [weak self] in
            self?.showManageWindow()
        }
        controller.requestClosePopover = { [weak self] in
            self?.closePopover()
        }

        monitor = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePopover()
            }
        }

        updateRuntimeMonitoringMode()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor {
            NotificationCenter.default.removeObserver(monitor)
        }
        removePopoverClickMonitors()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = ""
        item.button?.imagePosition = .imageOnly
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.setAccessibilityLabel("Codex Tools")
        statusItem = item
        applyStatusItemIcon()
    }

    private func setupPopover() {
        let content = StatusPopoverView(controller: controller)
        let host = NSHostingController(rootView: content)
        popover.contentViewController = host
        popover.delegate = self
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: UITheme.Popover.width, height: 370)
    }

    @objc
    private func togglePopover() {
        if popover.isShown {
            closePopover()
            return
        }

        guard let button = statusItem?.button else {
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        isPopoverVisible = true
        updateRuntimeMonitoringMode()
        installPopoverClickMonitors()
    }

    private func applyStatusItemIcon() {
        guard let button = statusItem?.button else {
            return
        }

        button.image = makeStatusItemImage()
        button.toolTip = "Codex Tools"
    }

    private func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
        removePopoverClickMonitors()
        if isPopoverVisible {
            isPopoverVisible = false
            updateRuntimeMonitoringMode()
        }
    }

    private func showManageWindow() {
        if manageWindowController == nil {
            manageWindowController = ManageWindowController(
                controller: controller,
                onVisibilityChanged: { [weak self] visible in
                    guard let self else {
                        return
                    }
                    self.isManageWindowVisible = visible
                    self.updateRuntimeMonitoringMode()
                }
            )
        }
        manageWindowController?.showOrFocus()
    }

    func popoverDidClose(_ notification: Notification) {
        removePopoverClickMonitors()
        if isPopoverVisible {
            isPopoverVisible = false
            updateRuntimeMonitoringMode()
        }
    }

    private func installPopoverClickMonitors() {
        removePopoverClickMonitors()

        let eventMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            self?.handlePopoverClick(event)
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handlePopoverClick(event)
            }
        }
    }

    private func removePopoverClickMonitors() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }

        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    private func handlePopoverClick(_ event: NSEvent) {
        guard popover.isShown else {
            return
        }

        guard !isClickInsidePopover(event) else {
            return
        }

        guard !isClickOnStatusItem(event) else {
            // Let the status-item toggle keep its existing open/close semantics.
            return
        }

        closePopover()
    }

    private func isClickInsidePopover(_ event: NSEvent) -> Bool {
        guard let popoverWindow = popover.contentViewController?.view.window else {
            return false
        }
        return popoverWindow.frame.contains(screenPoint(for: event))
    }

    private func isClickOnStatusItem(_ event: NSEvent) -> Bool {
        guard let statusButtonFrame = statusItemButtonFrameInScreen() else {
            return false
        }
        return statusButtonFrame.contains(screenPoint(for: event))
    }

    private func statusItemButtonFrameInScreen() -> NSRect? {
        guard let button = statusItem?.button, let window = button.window else {
            return nil
        }
        let rectInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(rectInWindow)
    }

    private func screenPoint(for event: NSEvent) -> NSPoint {
        if let window = event.window {
            return window.convertPoint(toScreen: event.locationInWindow)
        }
        return event.locationInWindow
    }

    private func updateRuntimeMonitoringMode() {
        let mode: RuntimeMonitoringMode = (isPopoverVisible || isManageWindowVisible) ? .interactive : .idle
        controller.setMonitoringMode(mode)
    }
}
