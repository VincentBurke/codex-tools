import AppKit
import CodexToolsCore
import Foundation

@MainActor
final class AppController: ObservableObject {
    @Published var statusSnapshot = StatusMenuSnapshot()
    @Published var manageSnapshot = ManageAccountsWindowSnapshot()
    @Published var selectedManageAccountID: String?
    @Published var isAddAccountSheetPresented = false

    var requestOpenManageWindow: (() -> Void)?
    var requestClosePopover: (() -> Void)?

    private let runtime: ServiceRuntime
    private var loopTimer: Timer?
    private var tickInFlight = false

    init(runtime: ServiceRuntime = ServiceRuntime()) {
        self.runtime = runtime

        Task {
            await runtime.boot()
            await refreshSnapshots()
            startLoop()
        }
    }

    func sendStatusCommand(_ command: StatusMenuCommand) {
        if command == .closeCodex && !confirmCloseCodexProcesses() {
            return
        }

        if command == .manageAccounts {
            requestOpenManageWindow?()
        }

        if shouldClosePopover(for: command) {
            requestClosePopover?()
        }

        Task {
            await runtime.handleStatusCommand(command)
            await refreshSnapshots()
        }
    }

    func sendManageAction(_ action: ManageAccountsAction) {
        Task {
            await runtime.handleManageAction(action)
            await refreshSnapshots()
        }
    }

    func setSelectedManageAccountID(_ value: String?) {
        selectedManageAccountID = value
        Task {
            await runtime.setSelectedManageAccountID(value)
        }
    }

    func presentAddAccountSheet() {
        isAddAccountSheetPresented = true
    }

    func dismissAddAccountSheet() {
        isAddAccountSheetPresented = false
    }

    func submitAddAccount(input: AddAccountInput) {
        isAddAccountSheetPresented = false
        sendManageAction(.addAccount(input))
    }

    func requestDelete(_ account: ManageAccountItem) {
        guard confirmDeleteAccount(name: account.name) else {
            return
        }
        sendManageAction(.delete(account.id))
    }

    func setSidebarMode(_ mode: SidebarMode) {
        sendManageAction(.sidebarModeChanged(mode))
    }

    func switchToAccountFromPopover(_ accountID: String) {
        sendStatusCommand(.switchAccount(accountID))
    }

    func closePopoverFromKeyboard() {
        requestClosePopover?()
    }

    private func startLoop() {
        loopTimer?.invalidate()
        loopTimer = Timer.scheduledTimer(withTimeInterval: 0.20, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.runTick()
            }
        }
    }

    private func runTick() {
        guard !tickInFlight else {
            return
        }
        tickInFlight = true

        Task {
            let output = await runtime.tick()
            let shouldPollRefreshing = statusSnapshot.isRefreshingUsage
                || manageSnapshot.accounts.contains(where: { $0.isUsageRefreshing })

            if output.snapshotsChanged || shouldPollRefreshing {
                await refreshSnapshots()
            }
            if let surfacedError = output.surfacedError {
                showErrorAlert(title: "Operation Failed", message: surfacedError)
            }
            if output.shouldQuit {
                NSApp.terminate(nil)
            }
            tickInFlight = false
        }
    }

    private func refreshSnapshots() async {
        statusSnapshot = await runtime.currentStatusSnapshot()
        manageSnapshot = await runtime.currentManageSnapshot()

        let reconciled = reconcileSelection(
            selectedID: selectedManageAccountID,
            accounts: manageSnapshot.accounts
        )
        selectedManageAccountID = reconciled
        await runtime.setSelectedManageAccountID(reconciled)
    }

    private func reconcileSelection(selectedID: String?, accounts: [ManageAccountItem]) -> String? {
        if let selectedID, accounts.contains(where: { $0.id == selectedID }) {
            return selectedID
        }
        if let active = accounts.first(where: { $0.isActive }) {
            return active.id
        }
        return accounts.first?.id
    }

    private func shouldClosePopover(for command: StatusMenuCommand) -> Bool {
        switch command {
        case .switchAccount, .manageAccounts, .quitApp:
            return true
        case .refreshAll, .closeCodex:
            return false
        }
    }

    private func confirmDeleteAccount(name: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete account \"\(name)\"?"
        alert.informativeText = "This action cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmCloseCodexProcesses() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Are you sure you want to close all running Codex processes?"
        alert.informativeText = "This will terminate active Codex CLI sessions and child processes."
        alert.addButton(withTitle: "Close Codex")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        _ = alert.runModal()
    }
}
