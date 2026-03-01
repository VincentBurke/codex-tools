@testable import CodexTools
import CodexToolsCore
import XCTest

final class UITestPlaceholder: XCTestCase {
    func testRowSelectionNavigationDoesNotTriggerSwitch() {
        let accounts = makeAccounts(activeID: "a")

        let movedDown = resolveManageKeyboardCommand(
            .moveDown,
            visibleAccounts: accounts,
            selectedAccountID: "a",
            canSwitch: true
        )

        XCTAssertEqual(movedDown, .select("b"))
    }

    func testReturnTriggersSwitchForInactiveSelection() {
        let accounts = makeAccounts(activeID: "a")

        let result = resolveManageKeyboardCommand(
            .switchSelected,
            visibleAccounts: accounts,
            selectedAccountID: "b",
            canSwitch: true
        )

        XCTAssertEqual(result, .switchAccount("b"))
    }

    func testSpaceTogglesExpandedRowForSelection() {
        let accounts = makeAccounts(activeID: "a")

        let result = resolveManageKeyboardCommand(
            .toggleExpanded,
            visibleAccounts: accounts,
            selectedAccountID: "c",
            canSwitch: true
        )

        XCTAssertEqual(result, .toggleExpanded("c"))
    }

    func testDeleteTriggersDeleteRequestForSelectedAccount() {
        let accounts = makeAccounts(activeID: "a")

        let result = resolveManageKeyboardCommand(
            .deleteSelected,
            visibleAccounts: accounts,
            selectedAccountID: "b",
            canSwitch: true
        )

        XCTAssertEqual(result, .requestDelete("b"))
    }

    func testNextBestRecommendationPrefersWeeklyThenFiveHour() {
        let recommendation = makeNextBestRecommendation(from: [
            status(id: "active", weekly: 95, fiveHour: 95, isActive: true),
            status(id: "a", weekly: 80, fiveHour: 20, isActive: false),
            status(id: "b", weekly: 80, fiveHour: 70, isActive: false)
        ])

        XCTAssertEqual(recommendation?.accountID, "b")
    }

    private func makeAccounts(activeID: String) -> [ManageAccountItem] {
        ["a", "b", "c"].map { id in
            ManageAccountItem(
                id: id,
                name: "account-\(id)",
                isActive: id == activeID,
                isStale: false,
                email: nil,
                authModeLabel: "ChatGPT",
                plan: nil,
                lastUsed: nil,
                fiveHourRemaining: 80,
                weeklyRemaining: 70,
                weeklyResetCountdown: "2d",
                usageError: nil
            )
        }
    }

    private func status(id: String, weekly: UInt8?, fiveHour: UInt8?, isActive: Bool) -> StatusAccountEntry {
        StatusAccountEntry(
            id: id,
            name: "status-\(id)",
            isActive: isActive,
            isStale: false,
            fiveHourRemaining: fiveHour,
            weeklyRemaining: weekly,
            usageError: nil
        )
    }
}
