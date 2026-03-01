@testable import CodexToolsCore
import XCTest

final class UsageTests: XCTestCase {
    func testConvertPayloadMapsRateLimitsAndCredits() {
        let payload = RateLimitStatusPayload(
            planType: "pro",
            rateLimit: RateLimitDetails(
                primaryWindow: RateLimitWindow(usedPercent: 37.5, limitWindowSeconds: 18_000, resetAt: 1_700_000_000),
                secondaryWindow: RateLimitWindow(usedPercent: 82.0, limitWindowSeconds: 604_800, resetAt: 1_700_600_000)
            ),
            credits: CreditStatusDetails(hasCredits: true, unlimited: false, balance: "$12.34")
        )

        let usage = convertPayloadToUsageInfo(accountID: "account-1", payload: payload)
        XCTAssertEqual(usage.accountID, "account-1")
        XCTAssertEqual(usage.planType, "pro")
        XCTAssertEqual(usage.primaryUsedPercent, 37.5)
        XCTAssertEqual(usage.primaryWindowMinutes, 300)
        XCTAssertEqual(usage.primaryResetsAt, 1_700_000_000)
        XCTAssertEqual(usage.secondaryUsedPercent, 82.0)
        XCTAssertEqual(usage.secondaryWindowMinutes, 10_080)
        XCTAssertEqual(usage.secondaryResetsAt, 1_700_600_000)
        XCTAssertEqual(usage.hasCredits, true)
        XCTAssertEqual(usage.unlimitedCredits, false)
        XCTAssertEqual(usage.creditsBalance, "$12.34")
        XCTAssertNil(usage.error)
    }

    func testAPIKeyAccountReturnsUsageUnavailableError() async throws {
        let client = DefaultUsageClient()
        let account = StoredAccount.newAPIKey(name: "API", apiKey: "sk-test")

        let usage = try await client.getUsage(for: account)
        XCTAssertEqual(usage.accountID, account.id)
        XCTAssertEqual(usage.planType, "api_key")
        XCTAssertEqual(usage.error, "Usage info not available for API key accounts")
    }

    func testRemainingPercentIsClampedAndRounded() {
        XCTAssertEqual(remainingPercentFromUsed(10.0), 90)
        XCTAssertEqual(remainingPercentFromUsed(-5.0), 100)
        XCTAssertEqual(remainingPercentFromUsed(140.0), 0)
        XCTAssertEqual(remainingPercentFromUsed(10.51), 89)
        XCTAssertNil(remainingPercentFromUsed(nil))
    }

    func testRefreshAllUsageConcurrentPreservesInputOrderAndRespectsConcurrencyLimit() async {
        let accounts = (0..<6).map { index in
            StoredAccount.newAPIKey(name: "account-\(index)", apiKey: "sk-\(index)")
        }
        let indexByID = Dictionary(uniqueKeysWithValues: accounts.enumerated().map { ($1.id, $0) })
        let tracker = RefreshConcurrencyTracker()

        let usageList = await refreshAllUsageConcurrent(
            accounts: accounts,
            maxConcurrentRequests: 2
        ) { account in
            let index = indexByID[account.id]!
            await tracker.begin()
            try? await Task.sleep(nanoseconds: UInt64((6 - index) * 20_000_000))
            await tracker.end()
            return UsageInfo.error(accountID: account.id, message: "done-\(index)")
        }

        XCTAssertEqual(usageList.map(\.accountID), accounts.map(\.id))
        let peak = await tracker.peak()
        XCTAssertGreaterThanOrEqual(peak, 2)
        XCTAssertLessThanOrEqual(peak, 2)
    }
}

private actor RefreshConcurrencyTracker {
    private var active = 0
    private var maxActive = 0

    func begin() {
        active += 1
        maxActive = max(maxActive, active)
    }

    func end() {
        active -= 1
    }

    func peak() -> Int {
        maxActive
    }
}
