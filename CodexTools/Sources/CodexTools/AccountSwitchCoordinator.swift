import AppKit
import CodexToolsCore
import Foundation

protocol AccountSwitchRuntime: Sendable {
    func inspectProcessesNow() async throws -> CodexProcessInfo
    func terminateCodexProcessesNow() async throws -> Int
    func switchAccountNow(_ accountID: String) async throws
}

extension ServiceRuntime: AccountSwitchRuntime {}

enum AccountSwitchOutcome: Equatable {
    case cancelled
    case switched(AccountSwitchResult)
}

struct AccountSwitchResult: Equatable {
    let terminatedProcesses: Bool
    let reopenedCodexApp: Bool
}

@MainActor
protocol AccountSwitchConfirming {
    func confirmSwitchClosingCodex(processCount: Int) -> Bool
}

@MainActor
protocol CodexAppLifecycleControlling {
    func isCodexAppRunning() -> Bool
    func relaunchCodexApp(after delay: TimeInterval)
}

@MainActor
final class AccountSwitchCoordinator {
    private let runtime: any AccountSwitchRuntime
    private let confirmer: any AccountSwitchConfirming
    private let codexAppController: any CodexAppLifecycleControlling
    private let relaunchDelaySeconds: TimeInterval

    init(
        runtime: any AccountSwitchRuntime,
        confirmer: any AccountSwitchConfirming = SwitchConfirmationPrompter(),
        codexAppController: any CodexAppLifecycleControlling = DefaultCodexAppController(),
        relaunchDelaySeconds: TimeInterval = 1.5
    ) {
        self.runtime = runtime
        self.confirmer = confirmer
        self.codexAppController = codexAppController
        self.relaunchDelaySeconds = relaunchDelaySeconds
    }

    func switchAccount(
        _ accountID: String,
        onSwitchWillProceed: @escaping @MainActor () -> Void = {}
    ) async throws -> AccountSwitchOutcome {
        let processInfo = try await runtime.inspectProcessesNow()
        let willTerminateProcesses = processInfo.count > 0
        let shouldReopenCodexApp = willTerminateProcesses && codexAppController.isCodexAppRunning()

        if willTerminateProcesses && !confirmer.confirmSwitchClosingCodex(processCount: processInfo.count) {
            return .cancelled
        }

        onSwitchWillProceed()

        if willTerminateProcesses {
            _ = try await runtime.terminateCodexProcessesNow()
        }

        try await runtime.switchAccountNow(accountID)

        if shouldReopenCodexApp {
            codexAppController.relaunchCodexApp(after: relaunchDelaySeconds)
        }

        return .switched(
            AccountSwitchResult(
                terminatedProcesses: willTerminateProcesses,
                reopenedCodexApp: shouldReopenCodexApp
            )
        )
    }
}

@MainActor
struct SwitchConfirmationPrompter: AccountSwitchConfirming {
    func confirmSwitchClosingCodex(processCount: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Switching accounts will close Codex. Are you sure?"
        if processCount == 1 {
            alert.informativeText = "This will close the running Codex session before switching accounts."
        } else {
            alert.informativeText = "This will close \(processCount) running Codex processes before switching accounts."
        }
        alert.addButton(withTitle: "Switch Account")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

@MainActor
final class DefaultCodexAppController: CodexAppLifecycleControlling {
    private let workspace: NSWorkspace
    private let bundleIdentifier = "com.openai.codex"

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func isCodexAppRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    func relaunchCodexApp(after delay: TimeInterval) {
        let delayNanoseconds = UInt64(max(0, delay) * 1_000_000_000)
        Task { @MainActor [workspace, bundleIdentifier] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)

            guard let applicationURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                return
            }

            let configuration = NSWorkspace.OpenConfiguration()
            _ = try? await workspace.openApplication(at: applicationURL, configuration: configuration)
        }
    }
}
