import CodexToolsCore
import Foundation
import XCTest

final class StorageTests: XCTestCase {
    func testLoadMissingFileReturnsDefaultStore() throws {
        let temp = try makeTempDirectory()
        try withEnv("CODEX_TOOLS_HOME", temp.path) {
            let repository = FileStoreRepository()
            let store = try repository.loadStore()

            XCTAssertEqual(store.version, accountsStoreVersion)
            XCTAssertTrue(store.accounts.isEmpty)
            XCTAssertNil(store.activeAccountID)
            XCTAssertTrue(store.usageCache.isEmpty)
        }
    }

    func testDuplicateAccountNameRejected() throws {
        let temp = try makeTempDirectory()
        try withEnv("CODEX_TOOLS_HOME", temp.path) {
            let repository = FileStoreRepository()
            let domain = StoreDomain(accountsRepository: repository, uiRepository: repository)

            _ = try domain.addAccount(.newAPIKey(name: "Work", apiKey: "sk-1"))
            XCTAssertThrowsError(try domain.addAccount(.newAPIKey(name: "Work", apiKey: "sk-2")))
        }
    }

    func testDeletingActiveAccountReassignsToFirstRemaining() throws {
        let temp = try makeTempDirectory()
        try withEnv("CODEX_TOOLS_HOME", temp.path) {
            let repository = FileStoreRepository()
            let domain = StoreDomain(accountsRepository: repository, uiRepository: repository)

            let first = try domain.addAccount(.newAPIKey(name: "Primary", apiKey: "sk-1"))
            let second = try domain.addAccount(.newAPIKey(name: "Secondary", apiKey: "sk-2"))

            try domain.setActiveAccount(second.id)
            try domain.upsertUsageCacheEntries([
                CachedUsageEntry(
                    usage: UsageInfo(
                        accountID: second.id,
                        planType: "pro",
                        primaryUsedPercent: 1,
                        primaryWindowMinutes: 300,
                        primaryResetsAt: 1_700_000_000,
                        secondaryUsedPercent: 2,
                        secondaryWindowMinutes: 10_080,
                        secondaryResetsAt: 1_700_600_000,
                        hasCredits: true,
                        unlimitedCredits: false,
                        creditsBalance: nil,
                        error: nil
                    ),
                    cachedAtUnix: 1_700_000_000
                )
            ])

            try domain.removeAccount(second.id)

            let store = try repository.loadStore()
            XCTAssertEqual(store.accounts.count, 1)
            XCTAssertEqual(store.accounts[0].id, first.id)
            XCTAssertEqual(store.activeAccountID, first.id)
            XCTAssertNil(store.usageCache[second.id])
        }
    }

    func testRejectsLegacyV1Store() throws {
        let temp = try makeTempDirectory()
        try withEnv("CODEX_TOOLS_HOME", temp.path) {
            let repository = FileStoreRepository()
            let account = StoredAccount.newAPIKey(name: "Legacy", apiKey: "sk-legacy")
            let encodedAccount = try String(data: CodexJSON.makeEncoder().encode(account), encoding: .utf8).unwrap()
            let raw = "{\"version\":1,\"accounts\":[\(encodedAccount)],\"active_account_id\":\"\(account.id)\"}"
            try raw.data(using: .utf8).unwrap().write(to: temp.appendingPathComponent("accounts.json"))

            XCTAssertThrowsError(try repository.loadStore())
        }
    }

    func testUsageCachePersistsAndLoads() throws {
        let temp = try makeTempDirectory()
        try withEnv("CODEX_TOOLS_HOME", temp.path) {
            let repository = FileStoreRepository()
            let domain = StoreDomain(accountsRepository: repository, uiRepository: repository)

            let account = try domain.addAccount(.newAPIKey(name: "Cache", apiKey: "sk-cache"))
            let entry = CachedUsageEntry(
                usage: UsageInfo(
                    accountID: account.id,
                    planType: "pro",
                    primaryUsedPercent: 25,
                    primaryWindowMinutes: 300,
                    primaryResetsAt: 1_700_000_000,
                    secondaryUsedPercent: 50,
                    secondaryWindowMinutes: 10_080,
                    secondaryResetsAt: 1_700_600_000,
                    hasCredits: true,
                    unlimitedCredits: false,
                    creditsBalance: "$9.99",
                    error: nil
                ),
                cachedAtUnix: 1_700_000_123
            )

            try domain.upsertUsageCacheEntries([entry])
            let loaded = try domain.loadUsageCache()
            XCTAssertEqual(loaded[account.id]?.cachedAtUnix, entry.cachedAtUnix)
            XCTAssertEqual(loaded[account.id]?.usage.primaryUsedPercent, entry.usage.primaryUsedPercent)
        }
    }

    func testSidebarModeRoundTrip() throws {
        let temp = try makeTempDirectory()
        try withEnv("CODEX_TOOLS_HOME", temp.path) {
            let repository = FileStoreRepository()

            XCTAssertEqual(try repository.loadSidebarMode(), .compact)
            try repository.saveSidebarMode(.detailed)
            XCTAssertEqual(try repository.loadSidebarMode(), .detailed)
            try repository.saveSidebarMode(.compact)
            XCTAssertEqual(try repository.loadSidebarMode(), .compact)
        }
    }
}

private extension Optional {
    func unwrap(file: StaticString = #filePath, line: UInt = #line) throws -> Wrapped {
        guard let value = self else {
            XCTFail("Unexpected nil", file: file, line: line)
            throw NSError(domain: "Test", code: 1)
        }
        return value
    }
}
