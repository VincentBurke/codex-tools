import CodexToolsCore
import Foundation
import XCTest

final class RuntimeTests: XCTestCase {
    func testBootPublishesAccountsWithoutWaitingForProcessCheck() async throws {
        let temp = try makeTempDirectory()
        try await withEnv("CODEX_TOOLS_HOME", temp.path) {
            let repository = FileStoreRepository()
            let domain = StoreDomain(accountsRepository: repository, uiRepository: repository)

            let account = try domain.addAccount(.newAPIKey(name: "active", apiKey: "sk-active"))
            try domain.setActiveAccount(account.id)

            let slowProcessService = SlowProcessService(delaySeconds: 1.5, processCount: 0)
            let runtime = ServiceRuntime(
                storeDomain: domain,
                authSwitcher: FileAuthSwitcher(),
                usageClient: StubUsageClient(),
                oauthClient: StubOAuthClient(),
                processInspector: slowProcessService,
                processTerminator: slowProcessService
            )

            let start = Date()
            await runtime.boot()
            let elapsed = Date().timeIntervalSince(start)

            let statusSnapshot = await runtime.currentStatusSnapshot()
            let manageSnapshot = await runtime.currentManageSnapshot()

            XCTAssertLessThan(elapsed, 0.5)
            XCTAssertEqual(statusSnapshot.accounts.count, 1)
            XCTAssertEqual(manageSnapshot.accounts.count, 1)
        }
    }

    func testBootPublishesAccountsWithoutWaitingForActiveUsageRefresh() async throws {
        let temp = try makeTempDirectory()
        try await withEnv("CODEX_TOOLS_HOME", temp.path) {
            let repository = FileStoreRepository()
            let domain = StoreDomain(accountsRepository: repository, uiRepository: repository)

            let account = try domain.addAccount(.newAPIKey(name: "active", apiKey: "sk-active"))
            try domain.setActiveAccount(account.id)

            let runtime = ServiceRuntime(
                storeDomain: domain,
                authSwitcher: FileAuthSwitcher(),
                usageClient: SlowErrorUsageClient(delayNanoseconds: 2_000_000_000),
                oauthClient: StubOAuthClient(),
                processInspector: StubProcessService(processCount: 0),
                processTerminator: StubProcessService(processCount: 0)
            )

            let start = Date()
            await runtime.boot()
            let elapsed = Date().timeIntervalSince(start)

            let statusSnapshot = await runtime.currentStatusSnapshot()
            let manageSnapshot = await runtime.currentManageSnapshot()

            XCTAssertLessThan(elapsed, 1.0)
            XCTAssertEqual(statusSnapshot.accounts.count, 1)
            XCTAssertEqual(manageSnapshot.accounts.count, 1)
        }
    }

    func testSnapshotsKeepActiveAccountFirstThenSortByWeeklyRemaining() async throws {
        let temp = try makeTempDirectory()
        try await withEnv("CODEX_TOOLS_HOME", temp.path) {
            let repository = FileStoreRepository()
            let domain = StoreDomain(accountsRepository: repository, uiRepository: repository)

            let a = try domain.addAccount(.newAPIKey(name: "low", apiKey: "sk-a"))
            let b = try domain.addAccount(.newAPIKey(name: "highest", apiKey: "sk-b"))
            let c = try domain.addAccount(.newAPIKey(name: "middle", apiKey: "sk-c"))

            try domain.upsertUsageCacheEntries([
                CachedUsageEntry(
                    usage: UsageInfo(
                        accountID: a.id,
                        planType: nil,
                        primaryUsedPercent: nil,
                        primaryWindowMinutes: nil,
                        primaryResetsAt: nil,
                        secondaryUsedPercent: 85,
                        secondaryWindowMinutes: nil,
                        secondaryResetsAt: nil,
                        hasCredits: nil,
                        unlimitedCredits: nil,
                        creditsBalance: nil,
                        error: nil
                    ),
                    cachedAtUnix: Int64(Date().timeIntervalSince1970)
                ),
                CachedUsageEntry(
                    usage: UsageInfo(
                        accountID: b.id,
                        planType: nil,
                        primaryUsedPercent: nil,
                        primaryWindowMinutes: nil,
                        primaryResetsAt: nil,
                        secondaryUsedPercent: 1,
                        secondaryWindowMinutes: nil,
                        secondaryResetsAt: nil,
                        hasCredits: nil,
                        unlimitedCredits: nil,
                        creditsBalance: nil,
                        error: nil
                    ),
                    cachedAtUnix: Int64(Date().timeIntervalSince1970)
                ),
                CachedUsageEntry(
                    usage: UsageInfo(
                        accountID: c.id,
                        planType: nil,
                        primaryUsedPercent: nil,
                        primaryWindowMinutes: nil,
                        primaryResetsAt: nil,
                        secondaryUsedPercent: 40,
                        secondaryWindowMinutes: nil,
                        secondaryResetsAt: nil,
                        hasCredits: nil,
                        unlimitedCredits: nil,
                        creditsBalance: nil,
                        error: nil
                    ),
                    cachedAtUnix: Int64(Date().timeIntervalSince1970)
                )
            ])

            let runtime = ServiceRuntime(
                storeDomain: domain,
                authSwitcher: FileAuthSwitcher(),
                usageClient: StubUsageClient(),
                oauthClient: StubOAuthClient(),
                processInspector: StubProcessService(processCount: 0),
                processTerminator: StubProcessService(processCount: 0)
            )
            await runtime.boot()
            let manageSnapshot = await runtime.currentManageSnapshot()
            XCTAssertEqual(manageSnapshot.accounts.map(\.name), ["low", "highest", "middle"])

            let statusSnapshot = await runtime.currentStatusSnapshot()
            XCTAssertEqual(statusSnapshot.accounts.map(\.name), ["low", "highest", "middle"])
        }
    }

    func testLowWeeklyAccountsSortBySoonestResetAcrossManageAndStatusSnapshots() async throws {
        let temp = try makeTempDirectory()
        try await withEnv("CODEX_TOOLS_HOME", temp.path) {
            let repository = FileStoreRepository()
            let domain = StoreDomain(accountsRepository: repository, uiRepository: repository)

            let high = try domain.addAccount(.newAPIKey(name: "high", apiKey: "sk-high"))
            let lowLate = try domain.addAccount(.newAPIKey(name: "low-late", apiKey: "sk-late"))
            let lowSoon = try domain.addAccount(.newAPIKey(name: "low-soon", apiKey: "sk-soon"))
            let lowUnknown = try domain.addAccount(.newAPIKey(name: "low-unknown", apiKey: "sk-unknown"))

            let nowTS = Int64(Date().timeIntervalSince1970)
            try domain.upsertUsageCacheEntries([
                CachedUsageEntry(
                    usage: usageInfo(
                        accountID: high.id,
                        weeklyUsedPercent: 20.0,
                        weeklyResetAt: nowTS + 86_400
                    ),
                    cachedAtUnix: nowTS
                ),
                CachedUsageEntry(
                    usage: usageInfo(
                        accountID: lowLate.id,
                        weeklyUsedPercent: 97.0,
                        weeklyResetAt: nowTS + 10_800
                    ),
                    cachedAtUnix: nowTS
                ),
                CachedUsageEntry(
                    usage: usageInfo(
                        accountID: lowSoon.id,
                        weeklyUsedPercent: 99.0,
                        weeklyResetAt: nowTS + 3_600
                    ),
                    cachedAtUnix: nowTS
                ),
                CachedUsageEntry(
                    usage: usageInfo(
                        accountID: lowUnknown.id,
                        weeklyUsedPercent: 98.0,
                        weeklyResetAt: nil
                    ),
                    cachedAtUnix: nowTS
                )
            ])

            let runtime = ServiceRuntime(
                storeDomain: domain,
                authSwitcher: FileAuthSwitcher(),
                usageClient: StubUsageClient(),
                oauthClient: StubOAuthClient(),
                processInspector: StubProcessService(processCount: 0),
                processTerminator: StubProcessService(processCount: 0)
            )
            await runtime.boot()

            let expectedOrder = [high.id, lowSoon.id, lowLate.id, lowUnknown.id]
            let manageOrder = await runtime.currentManageSnapshot().accounts.map(\.id)
            XCTAssertEqual(manageOrder, expectedOrder)

            let statusOrder = await runtime.currentStatusSnapshot().accounts.map(\.id)
            XCTAssertEqual(statusOrder, expectedOrder)
        }
    }

    func testSwitchBlockedWhenProcessesRunning() async throws {
        let tempHome = try makeTempDirectory()
        let tempCodex = try makeTempDirectory()

        try await withEnv("CODEX_TOOLS_HOME", tempHome.path) {
            try await withEnv("CODEX_HOME", tempCodex.path) {
                let repository = FileStoreRepository()
                let domain = StoreDomain(accountsRepository: repository, uiRepository: repository)

                let first = try domain.addAccount(.newAPIKey(name: "active", apiKey: "sk-1"))
                let second = try domain.addAccount(.newAPIKey(name: "target", apiKey: "sk-2"))
                try domain.setActiveAccount(first.id)

                let runtime = ServiceRuntime(
                    storeDomain: domain,
                    authSwitcher: FileAuthSwitcher(),
                    usageClient: StubUsageClient(),
                    oauthClient: StubOAuthClient(),
                    processInspector: StubProcessService(processCount: 1),
                    processTerminator: StubProcessService(processCount: 1)
                )

                await runtime.boot()
                await runtime.handleStatusCommand(.switchAccount(second.id))

                let store = try domain.loadStore()
                XCTAssertEqual(store.activeAccountID, first.id)
            }
        }
    }

    func testTickDoesNotPublishSnapshotsWhenProcessStateUnchanged() async throws {
        let tempHome = try makeTempDirectory()

        await withEnv("CODEX_TOOLS_HOME", tempHome.path) {
            let repository = FileStoreRepository()
            let domain = StoreDomain(accountsRepository: repository, uiRepository: repository)
            let stable = CodexProcessInfo(count: 0, canSwitch: true, pids: [])
            let processService = SequenceProcessService(results: [.success(stable), .success(stable)])

            let runtime = ServiceRuntime(
                storeDomain: domain,
                authSwitcher: FileAuthSwitcher(),
                usageClient: StubUsageClient(),
                oauthClient: StubOAuthClient(),
                processInspector: processService,
                processTerminator: processService
            )

            await runtime.boot()
            let output = await runtime.tick(now: Date().addingTimeInterval(4))
            XCTAssertFalse(output.snapshotsChanged)
            XCTAssertNil(output.surfacedError)
        }
    }

    func testTickPublishesSnapshotsWhenProcessStateChanges() async throws {
        let tempHome = try makeTempDirectory()

        await withEnv("CODEX_TOOLS_HOME", tempHome.path) {
            let repository = FileStoreRepository()
            let domain = StoreDomain(accountsRepository: repository, uiRepository: repository)
            let initial = CodexProcessInfo(count: 0, canSwitch: true, pids: [])
            let changed = CodexProcessInfo(count: 1, canSwitch: false, pids: [4242])
            let processService = SequenceProcessService(results: [.success(initial), .success(changed)])

            let runtime = ServiceRuntime(
                storeDomain: domain,
                authSwitcher: FileAuthSwitcher(),
                usageClient: StubUsageClient(),
                oauthClient: StubOAuthClient(),
                processInspector: processService,
                processTerminator: processService
            )

            await runtime.boot()
            let output = await runtime.tick(now: Date().addingTimeInterval(4))
            XCTAssertTrue(output.snapshotsChanged)
            XCTAssertNil(output.surfacedError)
        }
    }

    func testTickSurfacesProcessInspectorFailure() async throws {
        let tempHome = try makeTempDirectory()

        await withEnv("CODEX_TOOLS_HOME", tempHome.path) {
            let repository = FileStoreRepository()
            let domain = StoreDomain(accountsRepository: repository, uiRepository: repository)
            let initial = CodexProcessInfo(count: 0, canSwitch: true, pids: [])
            let processService = SequenceProcessService(results: [
                .success(initial),
                .failure(NSError(domain: "RuntimeTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "process check failed"]))
            ])

            let runtime = ServiceRuntime(
                storeDomain: domain,
                authSwitcher: FileAuthSwitcher(),
                usageClient: StubUsageClient(),
                oauthClient: StubOAuthClient(),
                processInspector: processService,
                processTerminator: processService
            )

            await runtime.boot()
            let output = await runtime.tick(now: Date().addingTimeInterval(4))
            XCTAssertTrue(output.snapshotsChanged)
            XCTAssertEqual(output.surfacedError, "process check failed")
        }
    }

    func testRefreshAllSkipsWeeklyExhaustedAccountsBeforeReset() async throws {
        let temp = try makeTempDirectory()
        try await withEnv("CODEX_TOOLS_HOME", temp.path) {
            let repository = FileStoreRepository()
            let domain = StoreDomain(accountsRepository: repository, uiRepository: repository)

            let skip = try domain.addAccount(.newAPIKey(name: "skip", apiKey: "sk-skip"))
            let include = try domain.addAccount(.newAPIKey(name: "include", apiKey: "sk-include"))
            let includeAtThreshold = try domain.addAccount(.newAPIKey(name: "include-threshold", apiKey: "sk-threshold"))

            let nowTS = Int64(Date().timeIntervalSince1970)
            try domain.upsertUsageCacheEntries([
                CachedUsageEntry(
                    usage: usageInfo(
                        accountID: skip.id,
                        weeklyUsedPercent: 98.5,
                        weeklyResetAt: nowTS + 3_600
                    ),
                    cachedAtUnix: nowTS
                ),
                CachedUsageEntry(
                    usage: usageInfo(
                        accountID: include.id,
                        weeklyUsedPercent: 99.5,
                        weeklyResetAt: nowTS - 60
                    ),
                    cachedAtUnix: nowTS
                ),
                CachedUsageEntry(
                    usage: usageInfo(
                        accountID: includeAtThreshold.id,
                        weeklyUsedPercent: 97.0,
                        weeklyResetAt: nowTS + 3_600
                    ),
                    cachedAtUnix: nowTS
                )
            ])

            let usageClient = RecordingUsageClient()
            let runtime = ServiceRuntime(
                storeDomain: domain,
                authSwitcher: FileAuthSwitcher(),
                usageClient: usageClient,
                oauthClient: StubOAuthClient(),
                processInspector: StubProcessService(processCount: 0),
                processTerminator: StubProcessService(processCount: 0)
            )

            await runtime.boot()
            await runtime.handleStatusCommand(.refreshAll)
            await waitForRefreshAllToFinish(runtime)

            let refreshedIDs = await usageClient.latestRefreshAllAccountIDs()
            XCTAssertEqual(Set(refreshedIDs), Set([include.id, includeAtThreshold.id]))
            XCTAssertFalse(refreshedIDs.contains(skip.id))
        }
    }

    func testRefreshAllIncludesAccountWithoutWeeklyResetTimestamp() async throws {
        let temp = try makeTempDirectory()
        try await withEnv("CODEX_TOOLS_HOME", temp.path) {
            let repository = FileStoreRepository()
            let domain = StoreDomain(accountsRepository: repository, uiRepository: repository)

            let account = try domain.addAccount(.newAPIKey(name: "unknown-reset", apiKey: "sk-unknown"))
            let nowTS = Int64(Date().timeIntervalSince1970)
            try domain.upsertUsageCacheEntries([
                CachedUsageEntry(
                    usage: usageInfo(
                        accountID: account.id,
                        weeklyUsedPercent: 99.9,
                        weeklyResetAt: nil
                    ),
                    cachedAtUnix: nowTS
                )
            ])

            let usageClient = RecordingUsageClient()
            let runtime = ServiceRuntime(
                storeDomain: domain,
                authSwitcher: FileAuthSwitcher(),
                usageClient: usageClient,
                oauthClient: StubOAuthClient(),
                processInspector: StubProcessService(processCount: 0),
                processTerminator: StubProcessService(processCount: 0)
            )

            await runtime.boot()
            await runtime.handleStatusCommand(.refreshAll)
            await waitForRefreshAllToFinish(runtime)

            let refreshedIDs = await usageClient.latestRefreshAllAccountIDs()
            XCTAssertEqual(refreshedIDs, [account.id])
        }
    }

    func testManageActionRefreshUsageTargetsSingleAccountAndSetsLastRefreshed() async throws {
        let temp = try makeTempDirectory()
        try await withEnv("CODEX_TOOLS_HOME", temp.path) {
            let repository = FileStoreRepository()
            let domain = StoreDomain(accountsRepository: repository, uiRepository: repository)

            _ = try domain.addAccount(.newAPIKey(name: "first", apiKey: "sk-first"))
            let second = try domain.addAccount(.newAPIKey(name: "second", apiKey: "sk-second"))

            let usageClient = RecordingSingleRefreshUsageClient()
            let runtime = ServiceRuntime(
                storeDomain: domain,
                authSwitcher: FileAuthSwitcher(),
                usageClient: usageClient,
                oauthClient: StubOAuthClient(),
                processInspector: StubProcessService(processCount: 0),
                processTerminator: StubProcessService(processCount: 0)
            )

            await runtime.boot()
            await runtime.handleManageAction(.refreshUsage(second.id))

            for _ in 0..<200 {
                let requestedIDs = await usageClient.latestGetUsageAccountIDs()
                let snapshot = await runtime.currentManageSnapshot()
                let row = snapshot.accounts.first(where: { $0.id == second.id })
                if requestedIDs.contains(second.id), row?.isUsageRefreshing == false, row?.usageLastRefreshed != nil {
                    break
                }
                await Task.yield()
            }

            let refreshedIDs = await usageClient.latestGetUsageAccountIDs()
            XCTAssertTrue(refreshedIDs.contains(second.id))

            let snapshot = await runtime.currentManageSnapshot()
            let secondRow = try XCTUnwrap(snapshot.accounts.first(where: { $0.id == second.id }))
            XCTAssertNotNil(secondRow.usageLastRefreshed)
        }
    }
}

private struct StubUsageClient: UsageClient {
    func getUsage(for account: StoredAccount) async throws -> UsageInfo {
        UsageInfo.error(accountID: account.id, message: "stub")
    }

    func refreshAllUsage(accounts: [StoredAccount]) async -> [UsageInfo] {
        accounts.map { UsageInfo.error(accountID: $0.id, message: "stub") }
    }
}

private struct SlowErrorUsageClient: UsageClient {
    let delayNanoseconds: UInt64

    func getUsage(for account: StoredAccount) async throws -> UsageInfo {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return UsageInfo.error(accountID: account.id, message: "stub delayed")
    }

    func refreshAllUsage(accounts: [StoredAccount]) async -> [UsageInfo] {
        []
    }
}

private actor StubOAuthClient: OAuthClient {
    func startLogin(action: OAuthLoginAction) async throws -> OAuthLoginInfo {
        OAuthLoginInfo(authURL: "https://example.com", callbackPort: 1455)
    }

    func pollLogin() async -> OAuthPollResult {
        .pending
    }

    func cancelLogin() async {}
}

private struct StubProcessService: ProcessInspector, ProcessTerminator {
    var processCount: Int

    func checkCodexProcesses() throws -> CodexProcessInfo {
        CodexProcessInfo(count: processCount, canSwitch: processCount == 0, pids: processCount == 0 ? [] : [9999])
    }

    func terminateCodexProcesses() throws -> Int {
        processCount
    }
}

private final class SlowProcessService: ProcessInspector, ProcessTerminator, @unchecked Sendable {
    private let delaySeconds: TimeInterval
    private let processCount: Int

    init(delaySeconds: TimeInterval, processCount: Int) {
        self.delaySeconds = delaySeconds
        self.processCount = processCount
    }

    func checkCodexProcesses() throws -> CodexProcessInfo {
        Thread.sleep(forTimeInterval: delaySeconds)
        return CodexProcessInfo(count: processCount, canSwitch: processCount == 0, pids: processCount == 0 ? [] : [9999])
    }

    func terminateCodexProcesses() throws -> Int {
        processCount
    }
}

private final class SequenceProcessService: ProcessInspector, ProcessTerminator, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<CodexProcessInfo, Error>]

    init(results: [Result<CodexProcessInfo, Error>]) {
        self.results = results
    }

    func checkCodexProcesses() throws -> CodexProcessInfo {
        lock.lock()
        defer { lock.unlock() }

        guard !results.isEmpty else {
            return CodexProcessInfo(count: 0, canSwitch: true, pids: [])
        }

        let result: Result<CodexProcessInfo, Error>
        if results.count == 1 {
            result = results[0]
        } else {
            result = results.removeFirst()
        }
        return try result.get()
    }

    func terminateCodexProcesses() throws -> Int {
        0
    }
}

private actor RecordingUsageClient: UsageClient {
    private var refreshAllAccountIDs: [[String]] = []

    func getUsage(for account: StoredAccount) async throws -> UsageInfo {
        UsageInfo.error(accountID: account.id, message: "stub")
    }

    func refreshAllUsage(accounts: [StoredAccount]) async -> [UsageInfo] {
        refreshAllAccountIDs.append(accounts.map(\.id))
        return accounts.map { UsageInfo.error(accountID: $0.id, message: "stub") }
    }

    func latestRefreshAllAccountIDs() -> [String] {
        refreshAllAccountIDs.last ?? []
    }
}

private actor RecordingSingleRefreshUsageClient: UsageClient {
    private var getUsageAccountIDs: [String] = []

    func getUsage(for account: StoredAccount) async throws -> UsageInfo {
        getUsageAccountIDs.append(account.id)
        let nowTS = Int64(Date().timeIntervalSince1970)
        return usageInfo(accountID: account.id, weeklyUsedPercent: 45, weeklyResetAt: nowTS + 3_600)
    }

    func refreshAllUsage(accounts: [StoredAccount]) async -> [UsageInfo] {
        []
    }

    func latestGetUsageAccountIDs() -> [String] {
        getUsageAccountIDs
    }
}

private func usageInfo(accountID: String, weeklyUsedPercent: Double, weeklyResetAt: Int64?) -> UsageInfo {
    UsageInfo(
        accountID: accountID,
        planType: nil,
        primaryUsedPercent: nil,
        primaryWindowMinutes: nil,
        primaryResetsAt: nil,
        secondaryUsedPercent: weeklyUsedPercent,
        secondaryWindowMinutes: nil,
        secondaryResetsAt: weeklyResetAt,
        hasCredits: nil,
        unlimitedCredits: nil,
        creditsBalance: nil,
        error: nil
    )
}

private func waitForRefreshAllToFinish(_ runtime: ServiceRuntime) async {
    for _ in 0..<200 {
        if !(await runtime.currentStatusSnapshot().isRefreshingUsage) {
            return
        }
        await Task.yield()
    }
}
