import Foundation

public enum RuntimeMonitoringMode: Sendable, Equatable {
    case idle
    case interactive
}

public struct AccountWithUsage: Sendable, Equatable {
    public var account: AccountInfo
    public var usage: UsageInfo?
    public var usageLoading: Bool

    public init(account: AccountInfo, usage: UsageInfo? = nil, usageLoading: Bool = false) {
        self.account = account
        self.usage = usage
        self.usageLoading = usageLoading
    }
}

public struct AppState: Sendable {
    public var accounts: [AccountWithUsage] = []
    public var processInfo: CodexProcessInfo?
    public var hasPendingOAuth: Bool = false
    public var usageCachedAtUnix: [String: Int64] = [:]
    public var staleUsageAccounts: Set<String> = []

    public init() {}

    public func activeAccountID() -> String? {
        accounts.first { $0.account.isActive }?.account.id
    }

    public func hasRunningProcesses() -> Bool {
        (processInfo?.count ?? 0) > 0
    }
}

public enum StatusMenuCommand: Sendable, Equatable {
    case refreshAll
    case manageAccounts
    case switchAccount(String)
    case closeCodex
    case quitApp
}

public struct StatusAccountEntry: Sendable, Equatable {
    public var id: String
    public var name: String
    public var isActive: Bool
    public var isStale: Bool
    public var fiveHourRemaining: UInt8?
    public var weeklyRemaining: UInt8?
    public var usageError: String?

    public init(
        id: String,
        name: String,
        isActive: Bool,
        isStale: Bool,
        fiveHourRemaining: UInt8?,
        weeklyRemaining: UInt8?,
        usageError: String?
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.isStale = isStale
        self.fiveHourRemaining = fiveHourRemaining
        self.weeklyRemaining = weeklyRemaining
        self.usageError = usageError
    }
}

public struct StatusMenuSnapshot: Sendable, Equatable {
    public var processCount: Int
    public var canSwitch: Bool
    public var isRefreshingUsage: Bool
    public var accounts: [StatusAccountEntry]

    public init(
        processCount: Int = 0,
        canSwitch: Bool = true,
        isRefreshingUsage: Bool = false,
        accounts: [StatusAccountEntry] = []
    ) {
        self.processCount = processCount
        self.canSwitch = canSwitch
        self.isRefreshingUsage = isRefreshingUsage
        self.accounts = accounts
    }
}

public enum OAuthLoginAction: Sendable, Equatable {
    case copyLink
    case openDefaultBrowser
}

public enum AddAccountInput: Sendable, Equatable {
    case oauth(OAuthLoginAction)
    case importAuthJSON(path: String)
}

public enum ManageAccountsAction: Sendable, Equatable {
    case addAccount(AddAccountInput)
    case `switch`(String)
    case refreshUsage(String)
    case renameInline(id: String, newName: String)
    case delete(String)
}

public struct ManageAccountItem: Sendable, Equatable {
    public var id: String
    public var name: String
    public var isActive: Bool
    public var isStale: Bool
    public var email: String?
    public var authModeLabel: String
    public var plan: String?
    public var lastUsed: String?
    public var fiveHourRemaining: UInt8?
    public var weeklyRemaining: UInt8?
    public var weeklyResetCountdown: String?
    public var usageError: String?
    public var isUsageRefreshing: Bool
    public var usageLastRefreshed: String?

    public init(
        id: String,
        name: String,
        isActive: Bool,
        isStale: Bool,
        email: String?,
        authModeLabel: String,
        plan: String?,
        lastUsed: String?,
        fiveHourRemaining: UInt8?,
        weeklyRemaining: UInt8?,
        weeklyResetCountdown: String?,
        usageError: String?,
        isUsageRefreshing: Bool = false,
        usageLastRefreshed: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.isStale = isStale
        self.email = email
        self.authModeLabel = authModeLabel
        self.plan = plan
        self.lastUsed = lastUsed
        self.fiveHourRemaining = fiveHourRemaining
        self.weeklyRemaining = weeklyRemaining
        self.weeklyResetCountdown = weeklyResetCountdown
        self.usageError = usageError
        self.isUsageRefreshing = isUsageRefreshing
        self.usageLastRefreshed = usageLastRefreshed
    }
}

public struct ManageAccountsWindowSnapshot: Sendable, Equatable {
    public var accounts: [ManageAccountItem]
    public var canSwitch: Bool

    public init(
        accounts: [ManageAccountItem] = [],
        canSwitch: Bool = true
    ) {
        self.accounts = accounts
        self.canSwitch = canSwitch
    }
}

public struct RuntimeTickOutput: Sendable, Equatable {
    public var shouldQuit: Bool
    public var snapshotsChanged: Bool
    public var surfacedError: String?
    public var nextTickDelaySeconds: TimeInterval

    public init(
        shouldQuit: Bool,
        snapshotsChanged: Bool,
        surfacedError: String?,
        nextTickDelaySeconds: TimeInterval
    ) {
        self.shouldQuit = shouldQuit
        self.snapshotsChanged = snapshotsChanged
        self.surfacedError = surfacedError
        self.nextTickDelaySeconds = nextTickDelaySeconds
    }
}

public func remainingPercentFromUsed(_ usedPercent: Double?) -> UInt8? {
    guard let usedPercent else {
        return nil
    }
    let value = max(0, min(100, 100 - usedPercent))
    return UInt8(value.rounded())
}
