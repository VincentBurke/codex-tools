@testable import CodexTools
import CodexToolsCore
import Foundation
import XCTest

@MainActor
final class AccountSwitchCoordinatorTests: XCTestCase {
    func testSwitchWithoutRunningProcessesSkipsConfirmationAndRelaunch() async throws {
        let runtime = RecordingAccountSwitchRuntime(processInfo: CodexProcessInfo(count: 0, canSwitch: true, pids: []))
        let confirmer = RecordingAccountSwitchConfirmer(result: true)
        let appController = RecordingCodexAppController(isRunning: false)
        let coordinator = AccountSwitchCoordinator(
            runtime: runtime,
            confirmer: confirmer,
            codexAppController: appController
        )

        var proceedCalls = 0
        let outcome = try await coordinator.switchAccount("target") {
            proceedCalls += 1
        }

        XCTAssertEqual(
            outcome,
            .switched(AccountSwitchResult(terminatedProcesses: false, reopenedCodexApp: false))
        )
        XCTAssertEqual(runtime.inspectCalls, 1)
        XCTAssertEqual(runtime.terminateCalls, 0)
        XCTAssertEqual(runtime.switchCalls, ["target"])
        XCTAssertTrue(confirmer.processCounts.isEmpty)
        XCTAssertTrue(appController.relaunchDelays.isEmpty)
        XCTAssertEqual(proceedCalls, 1)
    }

    func testSwitchCancellationStopsBeforeTermination() async throws {
        let runtime = RecordingAccountSwitchRuntime(processInfo: CodexProcessInfo(count: 2, canSwitch: false, pids: [1, 2]))
        let confirmer = RecordingAccountSwitchConfirmer(result: false)
        let appController = RecordingCodexAppController(isRunning: true)
        let coordinator = AccountSwitchCoordinator(
            runtime: runtime,
            confirmer: confirmer,
            codexAppController: appController
        )

        var proceedCalls = 0
        let outcome = try await coordinator.switchAccount("target") {
            proceedCalls += 1
        }

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(runtime.inspectCalls, 1)
        XCTAssertEqual(runtime.terminateCalls, 0)
        XCTAssertTrue(runtime.switchCalls.isEmpty)
        XCTAssertEqual(confirmer.processCounts, [2])
        XCTAssertTrue(appController.relaunchDelays.isEmpty)
        XCTAssertEqual(proceedCalls, 0)
    }

    func testSwitchWithRunningProcessesRelaunchesCodexAppWhenItWasOpen() async throws {
        let runtime = RecordingAccountSwitchRuntime(processInfo: CodexProcessInfo(count: 1, canSwitch: false, pids: [99]))
        let confirmer = RecordingAccountSwitchConfirmer(result: true)
        let appController = RecordingCodexAppController(isRunning: true)
        let coordinator = AccountSwitchCoordinator(
            runtime: runtime,
            confirmer: confirmer,
            codexAppController: appController
        )

        var proceedCalls = 0
        let outcome = try await coordinator.switchAccount("target") {
            proceedCalls += 1
        }

        XCTAssertEqual(
            outcome,
            .switched(AccountSwitchResult(terminatedProcesses: true, reopenedCodexApp: true))
        )
        XCTAssertEqual(runtime.terminateCalls, 1)
        XCTAssertEqual(runtime.switchCalls, ["target"])
        XCTAssertEqual(confirmer.processCounts, [1])
        XCTAssertEqual(appController.relaunchDelays, [1.5])
        XCTAssertEqual(proceedCalls, 1)
    }

    func testSwitchDoesNotRelaunchWhenCodexAppWasNotOpen() async throws {
        let runtime = RecordingAccountSwitchRuntime(processInfo: CodexProcessInfo(count: 1, canSwitch: false, pids: [42]))
        let confirmer = RecordingAccountSwitchConfirmer(result: true)
        let appController = RecordingCodexAppController(isRunning: false)
        let coordinator = AccountSwitchCoordinator(
            runtime: runtime,
            confirmer: confirmer,
            codexAppController: appController
        )

        let outcome = try await coordinator.switchAccount("target")

        XCTAssertEqual(
            outcome,
            .switched(AccountSwitchResult(terminatedProcesses: true, reopenedCodexApp: false))
        )
        XCTAssertEqual(runtime.terminateCalls, 1)
        XCTAssertEqual(runtime.switchCalls, ["target"])
        XCTAssertTrue(appController.relaunchDelays.isEmpty)
    }

    func testSwitchPropagatesTerminationFailureWithoutSwitching() async {
        let runtime = RecordingAccountSwitchRuntime(
            processInfo: CodexProcessInfo(count: 1, canSwitch: false, pids: [42]),
            terminateError: NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "terminate failed"])
        )
        let confirmer = RecordingAccountSwitchConfirmer(result: true)
        let appController = RecordingCodexAppController(isRunning: true)
        let coordinator = AccountSwitchCoordinator(
            runtime: runtime,
            confirmer: confirmer,
            codexAppController: appController
        )

        do {
            _ = try await coordinator.switchAccount("target")
            XCTFail("Expected terminate failure")
        } catch {
            XCTAssertEqual(error.localizedDescription, "terminate failed")
        }

        XCTAssertTrue(runtime.switchCalls.isEmpty)
        XCTAssertTrue(appController.relaunchDelays.isEmpty)
    }

    func testSwitchDoesNotRelaunchWhenSwitchingFails() async {
        let runtime = RecordingAccountSwitchRuntime(
            processInfo: CodexProcessInfo(count: 1, canSwitch: false, pids: [42]),
            switchError: NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "switch failed"])
        )
        let confirmer = RecordingAccountSwitchConfirmer(result: true)
        let appController = RecordingCodexAppController(isRunning: true)
        let coordinator = AccountSwitchCoordinator(
            runtime: runtime,
            confirmer: confirmer,
            codexAppController: appController
        )

        do {
            _ = try await coordinator.switchAccount("target")
            XCTFail("Expected switch failure")
        } catch {
            XCTAssertEqual(error.localizedDescription, "switch failed")
        }

        XCTAssertEqual(runtime.terminateCalls, 1)
        XCTAssertEqual(runtime.switchCalls, ["target"])
        XCTAssertTrue(appController.relaunchDelays.isEmpty)
    }
}

@MainActor
private final class RecordingAccountSwitchRuntime: AccountSwitchRuntime, @unchecked Sendable {
    private let processInfo: CodexProcessInfo
    private let terminateError: Error?
    private let switchError: Error?

    private(set) var inspectCalls = 0
    private(set) var terminateCalls = 0
    private(set) var switchCalls: [String] = []

    init(processInfo: CodexProcessInfo, terminateError: Error? = nil, switchError: Error? = nil) {
        self.processInfo = processInfo
        self.terminateError = terminateError
        self.switchError = switchError
    }

    func inspectProcessesNow() async throws -> CodexProcessInfo {
        inspectCalls += 1
        return processInfo
    }

    func terminateCodexProcessesNow() async throws -> Int {
        terminateCalls += 1
        if let terminateError {
            throw terminateError
        }
        return processInfo.count
    }

    func switchAccountNow(_ accountID: String) async throws {
        switchCalls.append(accountID)
        if let switchError {
            throw switchError
        }
    }
}

@MainActor
private final class RecordingAccountSwitchConfirmer: AccountSwitchConfirming {
    let result: Bool
    private(set) var processCounts: [Int] = []

    init(result: Bool) {
        self.result = result
    }

    func confirmSwitchClosingCodex(processCount: Int) -> Bool {
        processCounts.append(processCount)
        return result
    }
}

@MainActor
private final class RecordingCodexAppController: CodexAppLifecycleControlling {
    let isRunning: Bool
    private(set) var relaunchDelays: [TimeInterval] = []

    init(isRunning: Bool) {
        self.isRunning = isRunning
    }

    func isCodexAppRunning() -> Bool {
        isRunning
    }

    func relaunchCodexApp(after delay: TimeInterval) {
        relaunchDelays.append(delay)
    }
}
