import CodexToolsCore
import Foundation
import SwiftUI

enum UsageDisplayState: Equatable {
    case healthy(fiveHour: String, weekly: String)
    case stale(fiveHour: String, weekly: String)
    case unavailable
}

enum UsageSeverity: Equatable {
    case healthy
    case low
    case depleted
    case stale
    case unavailable
}

struct AccountRowDisplayModel: Equatable, Identifiable {
    let id: String
    let name: String
    let weeklyResetCountdown: String
    let fiveHourText: String
    let weeklyText: String
    let usageState: UsageDisplayState
    let severity: UsageSeverity
    let isActive: Bool
    let statusChip: String?
    let statusLine: String
}

struct NextBestRecommendation: Equatable {
    let accountID: String
    let name: String
    let weeklyText: String
    let fiveHourText: String
    let statusLine: String
    let severity: UsageSeverity
    let isStale: Bool
}

struct ManageRowMetricPresentation: Equatable {
    let weeklyText: String
    let fiveHourText: String
}

struct ManageRowHealthPresentation: Equatable {
    let label: String
    let symbolName: String
    let effectiveSeverity: UsageSeverity
}

enum ManageKeyboardCommand: Equatable {
    case moveUp
    case moveDown
    case switchSelected
    case deleteSelected
    case addAccount
    case toggleExpanded
}

enum ManageKeyboardResolution: Equatable {
    case none
    case select(String?)
    case switchAccount(String)
    case requestDelete(String)
    case presentAddAccount
    case toggleExpanded(String)
}

private struct RecommendationCandidate {
    let entry: StatusAccountEntry
    let originalIndex: Int
}

func makeManageRowMetricPresentation(
    weeklyRemaining: UInt8?,
    fiveHourRemaining: UInt8?
) -> ManageRowMetricPresentation {
    ManageRowMetricPresentation(
        weeklyText: percentLabel(weeklyRemaining),
        fiveHourText: percentLabel(fiveHourRemaining)
    )
}

func makeManageRowSubtitle(
    plan: String?,
    isStale: Bool,
    weeklyRemaining: UInt8?,
    fiveHourRemaining: UInt8?,
    usageError: String?
) -> String {
    var parts: [String] = []

    if let plan, !plan.isEmpty {
        parts.append(plan)
    }

    let usageUnavailable = hasUsageError(usageError) || (weeklyRemaining == nil && fiveHourRemaining == nil)
    if isStale {
        parts.append("stale usage")
    } else if usageUnavailable {
        parts.append("usage unavailable")
    }

    return parts.isEmpty ? "--" : parts.joined(separator: " • ")
}

func percentLabel(_ value: UInt8?) -> String {
    guard let value else {
        return "--"
    }
    return "\(value)%"
}

func normalizedUsageError(_ usageError: String?) -> String? {
    guard let usageError else {
        return nil
    }

    let trimmed = usageError.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

func hasUsageError(_ usageError: String?) -> Bool {
    normalizedUsageError(usageError) != nil
}

func usageSeverity(
    fiveHourRemaining: UInt8?,
    weeklyRemaining: UInt8?,
    isStale: Bool,
    usageError: String?
) -> UsageSeverity {
    guard !hasUsageError(usageError) else {
        return .unavailable
    }

    guard let weeklyRemaining, let fiveHourRemaining else {
        return .unavailable
    }

    if isStale {
        return .stale
    }

    if weeklyRemaining == 0 || fiveHourRemaining == 0 {
        return .depleted
    }

    if weeklyRemaining < 10 {
        return .low
    }

    return .healthy
}

func usageDisplayState(
    fiveHourRemaining: UInt8?,
    weeklyRemaining: UInt8?,
    isStale: Bool,
    usageError: String?
) -> UsageDisplayState {
    let severity = usageSeverity(
        fiveHourRemaining: fiveHourRemaining,
        weeklyRemaining: weeklyRemaining,
        isStale: isStale,
        usageError: usageError
    )

    switch severity {
    case .unavailable:
        return .unavailable
    case .stale:
        return .stale(
            fiveHour: percentLabel(fiveHourRemaining),
            weekly: percentLabel(weeklyRemaining)
        )
    case .healthy, .low, .depleted:
        return .healthy(
            fiveHour: percentLabel(fiveHourRemaining),
            weekly: percentLabel(weeklyRemaining)
        )
    }
}

func makeManageRowHealthPresentation(
    baseSeverity: UsageSeverity,
    weeklyRemaining: UInt8?,
    fiveHourRemaining: UInt8?
) -> ManageRowHealthPresentation {
    let minimum = [weeklyRemaining, fiveHourRemaining].compactMap { $0 }.min()
    let stalenessAgnosticSeverity: UsageSeverity

    switch baseSeverity {
    case .stale:
        if let weeklyRemaining, let fiveHourRemaining {
            if weeklyRemaining == 0 || fiveHourRemaining == 0 {
                stalenessAgnosticSeverity = .depleted
            } else if weeklyRemaining < 10 {
                stalenessAgnosticSeverity = .low
            } else {
                stalenessAgnosticSeverity = .healthy
            }
        } else {
            stalenessAgnosticSeverity = .unavailable
        }
    default:
        stalenessAgnosticSeverity = baseSeverity
    }

    let effectiveSeverity: UsageSeverity
    if let minimum, minimum < 3 {
        effectiveSeverity = .depleted
    } else {
        effectiveSeverity = stalenessAgnosticSeverity
    }

    switch effectiveSeverity {
    case .healthy:
        return ManageRowHealthPresentation(
            label: "Good",
            symbolName: "checkmark.circle.fill",
            effectiveSeverity: .healthy
        )
    case .low:
        return ManageRowHealthPresentation(
            label: "Low",
            symbolName: "exclamationmark.circle.fill",
            effectiveSeverity: .low
        )
    case .depleted:
        return ManageRowHealthPresentation(
            label: "Bad",
            symbolName: "xmark.circle.fill",
            effectiveSeverity: .depleted
        )
    case .stale:
        return ManageRowHealthPresentation(
            label: "Stale",
            symbolName: "clock.fill",
            effectiveSeverity: .stale
        )
    case .unavailable:
        return ManageRowHealthPresentation(
            label: "Unknown",
            symbolName: "questionmark.circle.fill",
            effectiveSeverity: .unavailable
        )
    }
}

func severityAccentColor(_ severity: UsageSeverity) -> Color {
    switch severity {
    case .healthy:
        return .secondary
    case .low:
        return UITheme.Color.lowUsage
    case .depleted:
        return UITheme.Color.depletedUsage
    case .stale:
        return UITheme.Color.staleUsage
    case .unavailable:
        return UITheme.Color.unavailableUsage
    }
}

func usageStatusChip(_ severity: UsageSeverity) -> String? {
    switch severity {
    case .healthy:
        return nil
    case .low:
        return "Low"
    case .depleted:
        return "Depleted"
    case .stale:
        return "Stale"
    case .unavailable:
        return "Unavailable"
    }
}

func usageStatusLine(
    fiveHourRemaining: UInt8?,
    weeklyRemaining: UInt8?,
    isStale: Bool,
    usageError: String?
) -> String {
    if hasUsageError(usageError) {
        return "5h -- · Weekly --"
    }

    let staleSuffix = isStale ? " (stale)" : ""
    return "5h \(percentLabel(fiveHourRemaining)) · Weekly \(percentLabel(weeklyRemaining))\(staleSuffix)"
}

func makeManageRowDisplayModel(_ account: ManageAccountItem) -> AccountRowDisplayModel {
    let severity = usageSeverity(
        fiveHourRemaining: account.fiveHourRemaining,
        weeklyRemaining: account.weeklyRemaining,
        isStale: account.isStale,
        usageError: account.usageError
    )

    return AccountRowDisplayModel(
        id: account.id,
        name: account.name,
        weeklyResetCountdown: account.weeklyResetCountdown ?? "--",
        fiveHourText: percentLabel(account.fiveHourRemaining),
        weeklyText: percentLabel(account.weeklyRemaining),
        usageState: usageDisplayState(
            fiveHourRemaining: account.fiveHourRemaining,
            weeklyRemaining: account.weeklyRemaining,
            isStale: account.isStale,
            usageError: account.usageError
        ),
        severity: severity,
        isActive: account.isActive,
        statusChip: usageStatusChip(severity),
        statusLine: usageStatusLine(
            fiveHourRemaining: account.fiveHourRemaining,
            weeklyRemaining: account.weeklyRemaining,
            isStale: account.isStale,
            usageError: account.usageError
        )
    )
}

func makeStatusRowDisplayModel(_ account: StatusAccountEntry) -> AccountRowDisplayModel {
    let severity = usageSeverity(
        fiveHourRemaining: account.fiveHourRemaining,
        weeklyRemaining: account.weeklyRemaining,
        isStale: account.isStale,
        usageError: account.usageError
    )

    return AccountRowDisplayModel(
        id: account.id,
        name: account.name,
        weeklyResetCountdown: "--",
        fiveHourText: percentLabel(account.fiveHourRemaining),
        weeklyText: percentLabel(account.weeklyRemaining),
        usageState: usageDisplayState(
            fiveHourRemaining: account.fiveHourRemaining,
            weeklyRemaining: account.weeklyRemaining,
            isStale: account.isStale,
            usageError: account.usageError
        ),
        severity: severity,
        isActive: account.isActive,
        statusChip: usageStatusChip(severity),
        statusLine: usageStatusLine(
            fiveHourRemaining: account.fiveHourRemaining,
            weeklyRemaining: account.weeklyRemaining,
            isStale: account.isStale,
            usageError: account.usageError
        )
    )
}

func nextSelectionID(currentID: String?, accountIDs: [String], direction: ManageKeyboardCommand) -> String? {
    guard !accountIDs.isEmpty else {
        return nil
    }

    guard let currentID,
          let currentIndex = accountIDs.firstIndex(of: currentID)
    else {
        return accountIDs[0]
    }

    switch direction {
    case .moveUp:
        return accountIDs[max(0, currentIndex - 1)]
    case .moveDown:
        return accountIDs[min(accountIDs.count - 1, currentIndex + 1)]
    case .switchSelected, .deleteSelected, .addAccount, .toggleExpanded:
        return currentID
    }
}

func resolveManageKeyboardCommand(
    _ command: ManageKeyboardCommand,
    visibleAccounts: [ManageAccountItem],
    selectedAccountID: String?,
    canSwitch: Bool
) -> ManageKeyboardResolution {
    let accountIDs = visibleAccounts.map(\.id)

    switch command {
    case .moveUp, .moveDown:
        let nextID = nextSelectionID(currentID: selectedAccountID, accountIDs: accountIDs, direction: command)
        return .select(nextID)
    case .switchSelected:
        guard let selected = visibleAccounts.first(where: { $0.id == selectedAccountID }) else {
            return .none
        }
        guard canSwitch, !selected.isActive else {
            return .none
        }
        return .switchAccount(selected.id)
    case .deleteSelected:
        guard let selected = visibleAccounts.first(where: { $0.id == selectedAccountID }) else {
            return .none
        }
        return .requestDelete(selected.id)
    case .addAccount:
        return .presentAddAccount
    case .toggleExpanded:
        guard let targetID = selectedAccountID ?? accountIDs.first else {
            return .none
        }
        return .toggleExpanded(targetID)
    }
}

func makeNextBestRecommendation(from accounts: [StatusAccountEntry]) -> NextBestRecommendation? {
    let candidates: [RecommendationCandidate] = accounts.enumerated().compactMap { index, entry in
        guard !entry.isActive else {
            return nil
        }
        guard entry.usageError == nil else {
            return nil
        }
        return RecommendationCandidate(entry: entry, originalIndex: index)
    }

    guard !candidates.isEmpty else {
        return nil
    }

    let weeklyPositive = candidates.filter { ($0.entry.weeklyRemaining ?? 0) > 0 }
    if let bestWeekly = bestCandidate(in: weeklyPositive, isBetter: weeklyRanking) {
        return recommendation(from: bestWeekly.entry)
    }

    let knownFiveHour = candidates.filter { $0.entry.fiveHourRemaining != nil }
    if let bestFiveHour = bestCandidate(in: knownFiveHour, isBetter: fiveHourRanking) {
        return recommendation(from: bestFiveHour.entry)
    }

    return nil
}

private func recommendation(from entry: StatusAccountEntry) -> NextBestRecommendation {
    let severity = usageSeverity(
        fiveHourRemaining: entry.fiveHourRemaining,
        weeklyRemaining: entry.weeklyRemaining,
        isStale: entry.isStale,
        usageError: entry.usageError
    )

    return NextBestRecommendation(
        accountID: entry.id,
        name: entry.name,
        weeklyText: percentLabel(entry.weeklyRemaining),
        fiveHourText: percentLabel(entry.fiveHourRemaining),
        statusLine: usageStatusLine(
            fiveHourRemaining: entry.fiveHourRemaining,
            weeklyRemaining: entry.weeklyRemaining,
            isStale: entry.isStale,
            usageError: entry.usageError
        ),
        severity: severity,
        isStale: entry.isStale
    )
}

private func weeklyRanking(_ lhs: RecommendationCandidate, _ rhs: RecommendationCandidate) -> Bool {
    let lhsWeekly = lhs.entry.weeklyRemaining ?? 0
    let rhsWeekly = rhs.entry.weeklyRemaining ?? 0
    if lhsWeekly != rhsWeekly {
        return lhsWeekly > rhsWeekly
    }

    let lhsFiveHour = lhs.entry.fiveHourRemaining ?? 0
    let rhsFiveHour = rhs.entry.fiveHourRemaining ?? 0
    if lhsFiveHour != rhsFiveHour {
        return lhsFiveHour > rhsFiveHour
    }

    if lhs.entry.isStale != rhs.entry.isStale {
        return !lhs.entry.isStale && rhs.entry.isStale
    }

    return lhs.originalIndex < rhs.originalIndex
}

private func fiveHourRanking(_ lhs: RecommendationCandidate, _ rhs: RecommendationCandidate) -> Bool {
    let lhsFiveHour = lhs.entry.fiveHourRemaining ?? 0
    let rhsFiveHour = rhs.entry.fiveHourRemaining ?? 0
    if lhsFiveHour != rhsFiveHour {
        return lhsFiveHour > rhsFiveHour
    }

    if lhs.entry.isStale != rhs.entry.isStale {
        return !lhs.entry.isStale && rhs.entry.isStale
    }

    return lhs.originalIndex < rhs.originalIndex
}

private func bestCandidate(
    in candidates: [RecommendationCandidate],
    isBetter: (RecommendationCandidate, RecommendationCandidate) -> Bool
) -> RecommendationCandidate? {
    guard var best = candidates.first else {
        return nil
    }

    for candidate in candidates.dropFirst() where isBetter(candidate, best) {
        best = candidate
    }

    return best
}
