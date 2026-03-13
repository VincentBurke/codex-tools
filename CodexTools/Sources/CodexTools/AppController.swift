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
    private var loopTask: Task<Void, Never>?
    private var snapshotSubscriptionTask: Task<Void, Never>?
    private var monitoringMode: RuntimeMonitoringMode = .idle

    init(runtime: ServiceRuntime = ServiceRuntime()) {
        self.runtime = runtime

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await runtime.boot()
            await refreshSnapshots()
            await runtime.setMonitoringMode(monitoringMode)
            startSnapshotSubscription()
            startLoop()
        }
    }

    deinit {
        loopTask?.cancel()
        snapshotSubscriptionTask?.cancel()
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
        }
    }

    func sendManageAction(_ action: ManageAccountsAction) {
        Task {
            await runtime.handleManageAction(action)
        }
    }

    func setMonitoringMode(_ mode: RuntimeMonitoringMode) {
        guard monitoringMode != mode else {
            return
        }
        monitoringMode = mode
        Task { [weak self] in
            guard let self else {
                return
            }
            await self.runtime.setMonitoringMode(mode)
            await MainActor.run {
                self.startLoop()
            }
        }
    }

    func setSelectedManageAccountID(_ value: String?) {
        selectedManageAccountID = value
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
        guard confirmDeleteAccounts(names: [account.name]) else {
            return
        }
        sendManageAction(.delete(account.id))
    }

    func requestDeleteUnavailable(_ accounts: [ManageAccountItem]) {
        let accountNames = accounts.map(\.name)
        guard confirmDeleteAccounts(names: accountNames) else {
            return
        }
        sendManageAction(.deleteMany(accounts.map(\.id)))
    }

    func switchToAccountFromPopover(_ accountID: String) {
        sendStatusCommand(.switchAccount(accountID))
    }

    func closePopoverFromKeyboard() {
        requestClosePopover?()
    }

    private func startLoop() {
        loopTask?.cancel()
        loopTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            while !Task.isCancelled {
                let tickStartedAt = Date()
                let output = await runtime.tick()
                handleTickOutput(output)
                if output.shouldQuit {
                    return
                }

                do {
                    // Runtime delay is computed from tick-start timestamps. Subtracting the tick
                    // execution time prevents steady drift that otherwise makes active UI feel laggy.
                    let elapsed = Date().timeIntervalSince(tickStartedAt)
                    let remainingDelay = max(0, output.nextTickDelaySeconds - elapsed)
                    try await Task.sleep(nanoseconds: nanoseconds(for: remainingDelay))
                } catch {
                    return
                }
            }
        }
    }

    private func startSnapshotSubscription() {
        snapshotSubscriptionTask?.cancel()
        snapshotSubscriptionTask = Task { [weak self] in
            guard let self else {
                return
            }
            let stream = await self.runtime.subscribeSnapshots()
            for await _ in stream {
                if Task.isCancelled {
                    return
                }
                await self.refreshSnapshots()
            }
        }
    }

    private func handleTickOutput(_ output: RuntimeTickOutput) {
        if let surfacedError = output.surfacedError {
            showErrorAlert(title: "Operation Failed", message: surfacedError)
        }
        if output.shouldQuit {
            NSApp.terminate(nil)
        }
    }

    private func nanoseconds(for seconds: TimeInterval) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }

    private func refreshSnapshots() async {
        statusSnapshot = await runtime.currentStatusSnapshot()
        manageSnapshot = await runtime.currentManageSnapshot()

        let reconciled = reconcileSelectionID(
            currentID: selectedManageAccountID,
            accounts: manageSnapshot.accounts,
            id: \.id,
            isActive: \.isActive
        )
        selectedManageAccountID = reconciled
    }

    private func shouldClosePopover(for command: StatusMenuCommand) -> Bool {
        switch command {
        case .switchAccount, .manageAccounts, .quitApp:
            return true
        case .refreshAll, .closeCodex:
            return false
        }
    }

    private func confirmDeleteAccounts(names: [String]) -> Bool {
        let sortedNames = names.sorted()
        let alert = NSAlert()
        alert.alertStyle = .warning
        if sortedNames.count == 1, let onlyName = sortedNames.first {
            alert.messageText = "Delete account \"\(onlyName)\"?"
            alert.informativeText = "This action cannot be undone."
        } else {
            let preview = sortedNames.prefix(6).joined(separator: "\n")
            let remainingCount = max(0, sortedNames.count - 6)
            let suffix = remainingCount > 0 ? "\n…and \(remainingCount) more." : ""
            alert.messageText = "Delete \(sortedNames.count) unavailable accounts?"
            alert.informativeText = "These accounts will be removed from the list:\n\(preview)\(suffix)"
        }
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
