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
                availability: .fresh
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
            availability: .stale,
            weeklyRemaining: 50,
            fiveHourRemaining: 40
        )
        XCTAssertEqual(stale.label, "Good")
        XCTAssertEqual(stale.symbolName, "checkmark.circle.fill")
        XCTAssertEqual(stale.effectiveSeverity, .healthy)

        let criticalFiveHour = makeManageRowHealthPresentation(
            availability: .fresh,
            weeklyRemaining: 90,
            fiveHourRemaining: 2
        )
        XCTAssertEqual(criticalFiveHour.label, "Bad")
        XCTAssertEqual(criticalFiveHour.symbolName, "xmark.circle.fill")
        XCTAssertEqual(criticalFiveHour.effectiveSeverity, .depleted)

        let staleLowWeekly = makeManageRowHealthPresentation(
            availability: .stale,
            weeklyRemaining: 8,
            fiveHourRemaining: 50
        )
        XCTAssertEqual(staleLowWeekly.label, "Low")
        XCTAssertEqual(staleLowWeekly.symbolName, "exclamationmark.circle.fill")
        XCTAssertEqual(staleLowWeekly.effectiveSeverity, .low)

        let disabled = makeManageRowHealthPresentation(
            availability: .disabled,
            weeklyRemaining: nil,
            fiveHourRemaining: nil
        )
        XCTAssertEqual(disabled.label, "Disabled")
        XCTAssertEqual(disabled.effectiveSeverity, .disabled)
    }

    func testManageRowSubtitleUsesPlanAndStatusWithoutAuthMethod() {
        XCTAssertEqual(
            makeManageRowSubtitle(
                plan: "team",
                availability: .fresh
            ),
            "team"
        )

        XCTAssertEqual(
            makeManageRowSubtitle(
                plan: "team",
                availability: .stale
            ),
            "team • stale usage"
        )

        XCTAssertEqual(
            makeManageRowSubtitle(
                plan: nil,
                availability: .unavailable
            ),
            "usage unavailable"
        )

        XCTAssertEqual(
            makeManageRowSubtitle(
                plan: nil,
                availability: .fresh
            ),
            "--"
        )

        XCTAssertEqual(
            makeManageRowSubtitle(
                plan: "team",
                availability: .paymentRequired
            ),
            "team • payment required"
        )

        XCTAssertEqual(
            makeManageRowSubtitle(
                plan: "team",
                availability: .expired
            ),
            "team • expired"
        )

        XCTAssertEqual(
            makeManageRowSubtitle(
                plan: "team",
                availability: .disabled
            ),
            "team • disabled"
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

    func testResolveManageKeyboardSwitchSelectedIgnoresTerminalUnavailableRow() {
        let accounts = [
            makeManageAccount(id: "a", active: true),
            makeManageAccount(id: "b", active: false, availability: .disabled)
        ]

        let result = resolveManageKeyboardCommand(
            .switchSelected,
            visibleAccounts: accounts,
            selectedAccountID: "b",
            canSwitch: true
        )

        XCTAssertEqual(result, .none)
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
            usageError: nil,
            availability: .stale
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

    func testManageRowActionPresentationUsesRemoveForTerminalUnavailableRows() {
        let presentation = makeManageRowActionPresentation(
            account: makeManageAccount(id: "bad", active: false, availability: .paymentRequired),
            canSwitch: true
        )

        XCTAssertEqual(presentation.kind, .remove)
        XCTAssertEqual(presentation.label, "Remove")
        XCTAssertTrue(presentation.isDestructive)
    }

    func testTerminalUnavailableAccountsReturnsOnlyTerminalRows() {
        let accounts = [
            makeManageAccount(id: "fresh", active: false),
            makeManageAccount(id: "stale", active: false, availability: .stale),
            makeManageAccount(id: "disabled", active: false, availability: .disabled),
            makeManageAccount(id: "expired", active: false, availability: .expired),
            makeManageAccount(id: "unknown", active: false, availability: .unavailable)
        ]

        XCTAssertEqual(
            terminalUnavailableAccounts(in: accounts).map(\.id),
            ["disabled", "expired"]
        )
    }

    private func makeManageAccount(
        id: String,
        active: Bool,
        availability: ManageAccountAvailabilityState = .fresh
    ) -> ManageAccountItem {
        ManageAccountItem(
            id: id,
            name: "name-\(id)",
            isActive: active,
            isStale: availability == .stale,
            email: nil,
            authModeLabel: "ChatGPT",
            plan: nil,
            lastUsed: nil,
            fiveHourRemaining: availability.isTerminalUnavailable ? nil : 50,
            weeklyRemaining: availability.isTerminalUnavailable ? nil : 50,
            weeklyResetCountdown: availability.isTerminalUnavailable ? nil : "2d",
            usageError: availability.isTerminalUnavailable ? String(describing: availability.rawValue).replacingOccurrences(of: "_", with: " ") : nil,
            availability: availability
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
