@testable import CodexTools
import CodexToolsCore
import XCTest

final class UIFormattingTests: XCTestCase {
    func testUsageSeverityPrioritizesUnavailableWhenUsageMissing() {
        let severity = usageSeverity(
            fiveHourRemaining: nil,
            weeklyRemaining: 90,
            isStale: false,
            usageError: nil
        )

        XCTAssertEqual(severity, .unavailable)
    }

    func testUsageSeverityDetectsLowAndDepletedBands() {
        XCTAssertEqual(
            usageSeverity(
                fiveHourRemaining: 80,
                weeklyRemaining: 9,
                isStale: false,
                usageError: nil
            ),
            .low
        )

        XCTAssertEqual(
            usageSeverity(
                fiveHourRemaining: 80,
                weeklyRemaining: 0,
                isStale: false,
                usageError: nil
            ),
            .depleted
        )
    }

    func testUsageErrorNormalizationTreatsBlankStringAsNoError() {
        XCTAssertFalse(hasUsageError(""))
        XCTAssertFalse(hasUsageError("   "))
        XCTAssertNil(normalizedUsageError("   "))

        XCTAssertEqual(
            usageSeverity(
                fiveHourRemaining: 80,
                weeklyRemaining: 90,
                isStale: false,
                usageError: "   "
            ),
            .healthy
        )

        XCTAssertEqual(
            makeManageRowSubtitle(
                plan: nil,
                isStale: false,
                weeklyRemaining: 50,
                fiveHourRemaining: 60,
                usageError: "   "
            ),
            "--"
        )
    }

    func testUsageErrorNormalizationTreatsTrimmedTextAsError() {
        XCTAssertTrue(hasUsageError(" timeout "))
        XCTAssertEqual(normalizedUsageError(" timeout "), "timeout")

        XCTAssertEqual(
            usageSeverity(
                fiveHourRemaining: 80,
                weeklyRemaining: 90,
                isStale: false,
                usageError: " timeout "
            ),
            .unavailable
        )
    }

    func testManageMetricPresentationAlwaysProvidesWeeklyAndFiveHourText() {
        let metric = makeManageRowMetricPresentation(
            weeklyRemaining: nil,
            fiveHourRemaining: 55
        )

        XCTAssertEqual(metric.weeklyText, "--")
        XCTAssertEqual(metric.fiveHourText, "55%")
    }

    func testManageHealthPresentationUsesSeverityLabelsAndSymbols() {
        let stale = makeManageRowHealthPresentation(
            baseSeverity: .stale,
            weeklyRemaining: 50,
            fiveHourRemaining: 40
        )
        XCTAssertEqual(stale.label, "Good")
        XCTAssertEqual(stale.symbolName, "checkmark.circle.fill")
        XCTAssertEqual(stale.effectiveSeverity, .healthy)

        let criticalFiveHour = makeManageRowHealthPresentation(
            baseSeverity: .healthy,
            weeklyRemaining: 90,
            fiveHourRemaining: 2
        )
        XCTAssertEqual(criticalFiveHour.label, "Bad")
        XCTAssertEqual(criticalFiveHour.symbolName, "xmark.circle.fill")
        XCTAssertEqual(criticalFiveHour.effectiveSeverity, .depleted)

        let staleLowWeekly = makeManageRowHealthPresentation(
            baseSeverity: .stale,
            weeklyRemaining: 8,
            fiveHourRemaining: 50
        )
        XCTAssertEqual(staleLowWeekly.label, "Low")
        XCTAssertEqual(staleLowWeekly.symbolName, "exclamationmark.circle.fill")
        XCTAssertEqual(staleLowWeekly.effectiveSeverity, .low)
    }

    func testManageRowSubtitleUsesPlanAndStatusWithoutAuthMethod() {
        XCTAssertEqual(
            makeManageRowSubtitle(
                plan: "team",
                isStale: false,
                weeklyRemaining: 95,
                fiveHourRemaining: 90,
                usageError: nil
            ),
            "team"
        )

        XCTAssertEqual(
            makeManageRowSubtitle(
                plan: "team",
                isStale: true,
                weeklyRemaining: 60,
                fiveHourRemaining: 70,
                usageError: nil
            ),
            "team • stale usage"
        )

        XCTAssertEqual(
            makeManageRowSubtitle(
                plan: nil,
                isStale: false,
                weeklyRemaining: nil,
                fiveHourRemaining: nil,
                usageError: nil
            ),
            "usage unavailable"
        )

        XCTAssertEqual(
            makeManageRowSubtitle(
                plan: nil,
                isStale: false,
                weeklyRemaining: 50,
                fiveHourRemaining: 60,
                usageError: nil
            ),
            "--"
        )
    }

    func testNextBestRecommendationExcludesActiveAndRanksByWeeklyThenFiveHour() {
        let entries = [
            makeStatus(id: "active", weekly: 90, fiveHour: 90, isActive: true),
            makeStatus(id: "a", weekly: 35, fiveHour: 10),
            makeStatus(id: "b", weekly: 35, fiveHour: 30),
            makeStatus(id: "c", weekly: 20, fiveHour: 90)
        ]

        let recommendation = makeNextBestRecommendation(from: entries)
        XCTAssertEqual(recommendation?.accountID, "b")
    }

    func testNextBestRecommendationFallsBackToFiveHourWhenNoPositiveWeekly() {
        let entries = [
            makeStatus(id: "active", weekly: 0, fiveHour: 40, isActive: true),
            makeStatus(id: "a", weekly: 0, fiveHour: 70),
            makeStatus(id: "b", weekly: nil, fiveHour: 80),
            makeStatus(id: "c", weekly: 0, fiveHour: 60)
        ]

        let recommendation = makeNextBestRecommendation(from: entries)
        XCTAssertEqual(recommendation?.accountID, "b")
    }

    func testResolveManageKeyboardToggleExpandedTargetsSelection() {
        let accounts = [
            makeManageAccount(id: "a", active: false),
            makeManageAccount(id: "b", active: false)
        ]

        let result = resolveManageKeyboardCommand(
            .toggleExpanded,
            visibleAccounts: accounts,
            selectedAccountID: "b",
            canSwitch: true
        )

        XCTAssertEqual(result, .toggleExpanded("b"))
    }

    func testResolveManageKeyboardMoveDownSelectsNextRow() {
        let accounts = [
            makeManageAccount(id: "a", active: true),
            makeManageAccount(id: "b", active: false),
            makeManageAccount(id: "c", active: false)
        ]

        let result = resolveManageKeyboardCommand(
            .moveDown,
            visibleAccounts: accounts,
            selectedAccountID: "a",
            canSwitch: true
        )

        XCTAssertEqual(result, .select("b"))
    }

    func testResolveManageKeyboardSwitchSelectedReturnsSwitchWhenInactive() {
        let accounts = [
            makeManageAccount(id: "a", active: true),
            makeManageAccount(id: "b", active: false)
        ]

        let result = resolveManageKeyboardCommand(
            .switchSelected,
            visibleAccounts: accounts,
            selectedAccountID: "b",
            canSwitch: true
        )

        XCTAssertEqual(result, .switchAccount("b"))
    }

    func testResolveManageKeyboardDeleteSelectedReturnsDeleteRequest() {
        let accounts = [
            makeManageAccount(id: "a", active: true),
            makeManageAccount(id: "b", active: false)
        ]

        let result = resolveManageKeyboardCommand(
            .deleteSelected,
            visibleAccounts: accounts,
            selectedAccountID: "b",
            canSwitch: true
        )

        XCTAssertEqual(result, .requestDelete("b"))
    }

    func testNextBestRecommendationPrefersFreshEntryWhenWeeklyAndFiveHourTie() {
        let entries = [
            StatusAccountEntry(
                id: "stale",
                name: "stale",
                isActive: false,
                isStale: true,
                fiveHourRemaining: 60,
                weeklyRemaining: 60,
                usageError: nil
            ),
            StatusAccountEntry(
                id: "fresh",
                name: "fresh",
                isActive: false,
                isStale: false,
                fiveHourRemaining: 60,
                weeklyRemaining: 60,
                usageError: nil
            )
        ]

        let recommendation = makeNextBestRecommendation(from: entries)
        XCTAssertEqual(recommendation?.accountID, "fresh")
    }

    func testReconcileSelectionIDKeepsCurrentWhenStillPresent() {
        let accounts = [
            makeManageAccount(id: "a", active: true),
            makeManageAccount(id: "b", active: false)
        ]

        let resolved = reconcileSelectionID(
            currentID: "b",
            accounts: accounts,
            id: \.id,
            isActive: \.isActive
        )

        XCTAssertEqual(resolved, "b")
    }

    func testReconcileSelectionIDFallsBackToActiveThenFirst() {
        let withActive = [
            makeManageAccount(id: "a", active: false),
            makeManageAccount(id: "b", active: true),
            makeManageAccount(id: "c", active: false)
        ]
        XCTAssertEqual(
            reconcileSelectionID(
                currentID: "missing",
                accounts: withActive,
                id: \.id,
                isActive: \.isActive
            ),
            "b"
        )

        let withoutActive = [
            makeManageAccount(id: "x", active: false),
            makeManageAccount(id: "y", active: false)
        ]
        XCTAssertEqual(
            reconcileSelectionID(
                currentID: nil,
                accounts: withoutActive,
                id: \.id,
                isActive: \.isActive
            ),
            "x"
        )
    }

    func testManageAndStatusRowDisplayModelsMatchForEquivalentValues() {
        let manage = ManageAccountItem(
            id: "acct-1",
            name: "primary",
            isActive: true,
            isStale: true,
            email: nil,
            authModeLabel: "ChatGPT",
            plan: "team",
            lastUsed: nil,
            fiveHourRemaining: 55,
            weeklyRemaining: 40,
            weeklyResetCountdown: "2d",
            usageError: nil
        )
        let status = StatusAccountEntry(
            id: "acct-1",
            name: "primary",
            isActive: true,
            isStale: true,
            fiveHourRemaining: 55,
            weeklyRemaining: 40,
            usageError: nil
        )

        let manageModel = makeManageRowDisplayModel(manage)
        let statusModel = makeStatusRowDisplayModel(status)
        XCTAssertEqual(manageModel, statusModel)
    }

    private func makeManageAccount(id: String, active: Bool) -> ManageAccountItem {
        ManageAccountItem(
            id: id,
            name: "name-\(id)",
            isActive: active,
            isStale: false,
            email: nil,
            authModeLabel: "ChatGPT",
            plan: nil,
            lastUsed: nil,
            fiveHourRemaining: 50,
            weeklyRemaining: 50,
            weeklyResetCountdown: "2d",
            usageError: nil
        )
    }

    private func makeStatus(
        id: String,
        weekly: UInt8?,
        fiveHour: UInt8?,
        isActive: Bool = false
    ) -> StatusAccountEntry {
        StatusAccountEntry(
            id: id,
            name: "account-\(id)",
            isActive: isActive,
            isStale: false,
            fiveHourRemaining: fiveHour,
            weeklyRemaining: weekly,
            usageError: nil
        )
    }
}
