import Foundation

public let SERVICE_STALE_THRESHOLD_SECONDS: Int64 = 15 * 60

private let oauthPollInterval: TimeInterval = 1
private let processCheckInterval: TimeInterval = 3
private let activeRefreshInterval: TimeInterval = 15 * 60
private let snapshotPublishInterval: TimeInterval = 30
private let weeklyRefreshPauseThresholdPercent: Double = 1.0
private let weeklyRefreshAllSkipThresholdPercent: Double = 3.0

public actor ServiceRuntime {
    private var state = AppState()

    private let storeDomain: StoreDomain
    private let authSwitcher: any AuthSwitcher
    private let usageClient: any UsageClient
    private let oauthClient: any OAuthClient
    private let processInspector: any ProcessInspector
    private let processTerminator: any ProcessTerminator

    private var refreshAllInFlight = false

    private var lastOAuthPoll = Date()
    private var lastProcessCheck = Date()
    private var lastActiveRefresh = Date()
    private var lastSnapshotPublish = Date()
    private var quitRequested = false

    private var statusSnapshot = StatusMenuSnapshot()
    private var manageSnapshot = ManageAccountsWindowSnapshot()

    private var pendingErrorForUI: String?

    public init(
        storeDomain: StoreDomain? = nil,
        authSwitcher: (any AuthSwitcher)? = nil,
        usageClient: (any UsageClient)? = nil,
        oauthClient: (any OAuthClient)? = nil,
        processInspector: (any ProcessInspector)? = nil,
        processTerminator: (any ProcessTerminator)? = nil
    ) {
        let fileRepository = FileStoreRepository()
        self.storeDomain = storeDomain ?? StoreDomain(accountsRepository: fileRepository, uiRepository: fileRepository)
        self.authSwitcher = authSwitcher ?? FileAuthSwitcher()
        self.usageClient = usageClient ?? DefaultUsageClient()
        self.oauthClient = oauthClient ?? DefaultOAuthClient()

        let processService = DefaultProcessService()
        self.processInspector = processInspector ?? processService
        self.processTerminator = processTerminator ?? processService
    }

    public func boot() async {
        let now = Date()
        lastOAuthPoll = now
        lastProcessCheck = now
        lastActiveRefresh = now
        lastSnapshotPublish = now

        do {
            try loadAccounts(preserveUsage: false)
        } catch {
            setError(error.localizedDescription)
        }

        do {
            state.sidebarMode = try storeDomain.loadSidebarMode()
        } catch {
            setError(error.localizedDescription)
        }

        _ = await refreshActiveAccountBackground()

        do {
            state.processInfo = try processInspector.checkCodexProcesses()
        } catch {
            setError(error.localizedDescription)
        }

        publishSnapshots(now: Date())
    }

    public func tick(now: Date = Date()) async -> RuntimeTickOutput {
        var changed = false

        if now.timeIntervalSince(lastOAuthPoll) >= oauthPollInterval {
            lastOAuthPoll = now
            changed = await pollOAuthBackground() || changed
        }

        if now.timeIntervalSince(lastProcessCheck) >= processCheckInterval {
            lastProcessCheck = now
            changed = await checkProcessesBackground() || changed
        }

        if now.timeIntervalSince(lastActiveRefresh) >= activeRefreshInterval {
            lastActiveRefresh = now
            changed = await refreshActiveAccountBackground() || changed
        }

        if changed || now.timeIntervalSince(lastSnapshotPublish) >= snapshotPublishInterval {
            publishSnapshots(now: now)
            changed = true
        }

        let surfacedError = pendingErrorForUI
        pendingErrorForUI = nil

        return RuntimeTickOutput(
            shouldQuit: quitRequested,
            snapshotsChanged: changed,
            surfacedError: surfacedError
        )
    }

    public func currentStatusSnapshot() -> StatusMenuSnapshot {
        statusSnapshot
    }

    public func currentManageSnapshot() -> ManageAccountsWindowSnapshot {
        manageSnapshot
    }

    public func selectedManageAccountID() -> String? {
        state.selectedAccountID
    }

    public func setSelectedManageAccountID(_ value: String?) {
        state.selectedAccountID = value
    }

    public func handleStatusCommand(_ command: StatusMenuCommand) async {
        switch command {
        case .refreshAll:
            await startRefreshAll()
        case .manageAccounts:
            break
        case .switchAccount(let accountID):
            await handleSwitchAccount(accountID)
        case .closeCodex:
            do {
                _ = try processTerminator.terminateCodexProcesses()
            } catch {
                setError(error.localizedDescription)
            }
        case .quitApp:
            quitRequested = true
        }

        do {
            state.processInfo = try processInspector.checkCodexProcesses()
        } catch {
            setError(error.localizedDescription)
        }

        publishSnapshots(now: Date())
    }

    public func handleManageAction(_ action: ManageAccountsAction) async {
        switch action {
        case .addAccount(let input):
            switch input {
            case .oauth(let oauthAction):
                await startOAuthLogin(action: oauthAction)
            case .importAuthJSON(let path):
                await importFromFile(path: path)
            }
        case .switch(let id):
            await handleSwitchAccount(id)
        case .refreshUsage(let id):
            startRefreshSingle(accountID: id)
        case .renameInline(let id, let newName):
            await handleInlineRename(accountID: id, newName: newName)
        case .delete(let id):
            await handleDeleteAccount(accountID: id)
        case .sidebarModeChanged(let mode):
            if state.sidebarMode != mode {
                state.sidebarMode = mode
                do {
                    try storeDomain.saveSidebarMode(mode)
                } catch {
                    setError(error.localizedDescription)
                }
            }
        }

        do {
            state.processInfo = try processInspector.checkCodexProcesses()
        } catch {
            setError(error.localizedDescription)
        }

        publishSnapshots(now: Date())
    }

    private func handleSwitchAccount(_ accountID: String) async {
        let isActive = state.activeAccountID() == accountID
        if state.hasRunningProcesses() && !isActive {
            setError("Cannot switch account while Codex processes are running")
            return
        }

        do {
            let store = try storeDomain.loadStore()
            guard let account = store.accounts.first(where: { $0.id == accountID }) else {
                throw NSError(
                    domain: "ServiceRuntime",
                    code: 100,
                    userInfo: [NSLocalizedDescriptionKey: "Account not found: \(accountID)"]
                )
            }

            try authSwitcher.switchToAccount(account)
            try storeDomain.setActiveAccount(accountID)
            try storeDomain.touchAccount(accountID)
            try loadAccounts(preserveUsage: true)

            do {
                _ = try await refreshSingleUsageAutomatic(accountID: accountID)
            } catch {
                setError(error.localizedDescription)
            }
        } catch {
            setError(error.localizedDescription)
        }
    }

    private func handleInlineRename(accountID: String, newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setError("Account name cannot be empty")
            return
        }

        let currentName = state.accounts.first(where: { $0.account.id == accountID })?.account.name
        if currentName == trimmed {
            return
        }

        do {
            try storeDomain.updateAccountMetadata(accountID: accountID, name: trimmed, email: nil, planType: nil)
            try loadAccounts(preserveUsage: true)
        } catch {
            setError(error.localizedDescription)
        }
    }

    private func handleDeleteAccount(accountID: String) async {
        do {
            try storeDomain.removeAccount(accountID)
            try loadAccounts(preserveUsage: false)
        } catch {
            setError(error.localizedDescription)
        }
    }

    private func importFromFile(path: String) async {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            setError("Please select an auth.json file")
            return
        }

        do {
            let account = try authSwitcher.importFromAuthJSON(path: trimmedPath)
            _ = try storeDomain.addAccount(account)
            try loadAccounts(preserveUsage: false)
            await refreshActiveUsageAfterLoad()
        } catch {
            setError(error.localizedDescription)
        }
    }

    private func startOAuthLogin(action: OAuthLoginAction) async {
        do {
            _ = try await oauthClient.startLogin(action: action)
            state.hasPendingOAuth = true
        } catch {
            setError(error.localizedDescription)
        }
    }

    private func pollOAuthBackground() async -> Bool {
        guard state.hasPendingOAuth else {
            return false
        }

        let result = await oauthClient.pollLogin()
        switch result {
        case .idle:
            state.hasPendingOAuth = false
            return true
        case .pending:
            return false
        case .failed(let message):
            state.hasPendingOAuth = false
            setError(message)
            return true
        case .completed(let loginResult):
            state.hasPendingOAuth = false
            do {
                try completeOAuthLogin(account: loginResult.account)
                await refreshActiveUsageAfterLoad()
            } catch {
                setError(error.localizedDescription)
            }
            return true
        }
    }

    private func completeOAuthLogin(account: StoredAccount) throws {
        let stored = try storeDomain.addAccount(account)
        try storeDomain.setActiveAccount(stored.id)
        try authSwitcher.switchToAccount(stored)
        try storeDomain.touchAccount(stored.id)
        try loadAccounts(preserveUsage: false)
    }

    private func checkProcessesBackground() async -> Bool {
        let previous = state.processInfo
        do {
            let current = try processInspector.checkCodexProcesses()
            state.processInfo = current
            return previous != current
        } catch {
            setError(error.localizedDescription)
            return true
        }
    }

    private func refreshActiveAccountBackground() async -> Bool {
        guard let activeID = state.activeAccountID() else {
            return false
        }

        do {
            return try await refreshSingleUsageAutomatic(accountID: activeID)
        } catch {
            setError(error.localizedDescription)
            return true
        }
    }

    private func refreshActiveUsageAfterLoad() async {
        guard let activeID = state.activeAccountID() else {
            return
        }
        do {
            _ = try await refreshSingleUsageAutomatic(accountID: activeID)
        } catch {
            setError(error.localizedDescription)
        }
    }

    private func loadAccounts(preserveUsage: Bool) throws {
        let accountInfos = try storeDomain.listAccountsInfo()
        var usageByID: [String: (UsageInfo, Int64)] = [:]
        for (accountID, entry) in try storeDomain.loadUsageCache() {
            usageByID[accountID] = (entry.usage, entry.cachedAtUnix)
        }

        if preserveUsage {
            let nowTS = Int64(Date().timeIntervalSince1970)
            for account in state.accounts {
                guard let usage = account.usage else {
                    continue
                }
                let cachedAt = state.usageCachedAtUnix[account.account.id] ?? nowTS
                usageByID[account.account.id] = (usage, cachedAt)
            }
        }

        state.accounts = accountInfos.map { accountInfo in
            var item = AccountWithUsage(account: accountInfo)
            if let (usage, _) = usageByID[accountInfo.id] {
                item.usage = usage
            }
            return item
        }

        var cachedAtByID: [String: Int64] = [:]
        for (id, (_, cachedAt)) in usageByID {
            cachedAtByID[id] = cachedAt
        }
        state.usageCachedAtUnix = cachedAtByID

        let activeID = state.activeAccountID()
        switch state.selectedAccountID {
        case .some(let selected) where state.accounts.contains(where: { $0.account.id == selected }):
            break
        default:
            state.selectedAccountID = activeID ?? state.accounts.first?.account.id
        }
    }

    private func startRefreshAll() async {
        if refreshAllInFlight {
            return
        }

        let nowTS = Int64(Date().timeIntervalSince1970)
        let accountIDs = state.accounts.compactMap { account in
            shouldSkipRefreshAllUsage(usage: account.usage, nowTS: nowTS) ? nil : account.account.id
        }
        if accountIDs.isEmpty {
            return
        }

        do {
            let store = try storeDomain.loadStore()
            let idSet = Set(accountIDs)
            let accounts = store.accounts.filter { idSet.contains($0.id) }
            if accounts.isEmpty {
                return
            }

            refreshAllInFlight = true
            state.refreshingAll = true
            for index in state.accounts.indices where idSet.contains(state.accounts[index].account.id) {
                state.accounts[index].usageLoading = true
            }

            Task {
                let usageList = await self.usageClient.refreshAllUsage(accounts: accounts)
                await self.completeRefreshAll(usageList: usageList)
            }
        } catch {
            setError(error.localizedDescription)
        }
    }

    private func startRefreshSingle(accountID: String) {
        guard let index = state.accounts.firstIndex(where: { $0.account.id == accountID }) else {
            return
        }
        guard !state.accounts[index].usageLoading else {
            return
        }

        state.accounts[index].usageLoading = true
        Task {
            do {
                try await self.refreshSingleUsage(accountID: accountID)
            } catch {
                self.setError(error.localizedDescription)
            }
            self.publishSnapshots(now: Date())
        }
    }

    private func shouldSkipRefreshAllUsage(usage: UsageInfo?, nowTS: Int64) -> Bool {
        guard let usage else {
            return false
        }
        guard let weeklyRemaining = weeklyRemainingPercent(usage: usage) else {
            return false
        }
        guard weeklyRemaining < weeklyRefreshAllSkipThresholdPercent else {
            return false
        }
        guard let resetAt = usage.secondaryResetsAt else {
            return false
        }

        // Refresh-all should avoid accounts that are effectively exhausted this week.
        // Those can still be refreshed explicitly via single-account/manual flows.
        return nowTS < resetAt
    }

    private func completeRefreshAll(usageList: [UsageInfo]) async {
        refreshAllInFlight = false
        state.refreshingAll = false

        do {
            try applyUsageUpdates(usageList: usageList)
        } catch {
            setError(error.localizedDescription)
        }
        publishSnapshots(now: Date())
    }

    private func applyUsageUpdates(usageList: [UsageInfo]) throws {
        var usageByID = Dictionary(uniqueKeysWithValues: usageList.map { ($0.accountID, $0) })
        let nowTS = Int64(Date().timeIntervalSince1970)
        var cacheEntries: [CachedUsageEntry] = []

        for index in state.accounts.indices {
            state.accounts[index].usageLoading = false

            guard let usage = usageByID.removeValue(forKey: state.accounts[index].account.id) else {
                continue
            }

            if usage.error == nil {
                state.staleUsageAccounts.remove(state.accounts[index].account.id)
                state.usageCachedAtUnix[state.accounts[index].account.id] = nowTS
                cacheEntries.append(CachedUsageEntry(usage: usage, cachedAtUnix: nowTS))
                state.accounts[index].usage = usage
            } else {
                state.staleUsageAccounts.insert(state.accounts[index].account.id)
                if state.accounts[index].usage == nil {
                    state.accounts[index].usage = usage
                }
            }
        }

        if !cacheEntries.isEmpty {
            try storeDomain.upsertUsageCacheEntries(cacheEntries)
        }
    }

    private func refreshSingleUsage(accountID: String) async throws {
        if let index = state.accounts.firstIndex(where: { $0.account.id == accountID }) {
            state.accounts[index].usageLoading = true
        }

        do {
            guard let account = try storeDomain.getAccount(accountID) else {
                throw NSError(
                    domain: "ServiceRuntime",
                    code: 200,
                    userInfo: [NSLocalizedDescriptionKey: "Account not found: \(accountID)"]
                )
            }

            let usage = try await usageClient.getUsage(for: account)
            if let index = state.accounts.firstIndex(where: { $0.account.id == accountID }) {
                state.accounts[index].usageLoading = false

                if usage.error == nil {
                    let nowTS = Int64(Date().timeIntervalSince1970)
                    state.accounts[index].usage = usage
                    state.staleUsageAccounts.remove(accountID)
                    state.usageCachedAtUnix[accountID] = nowTS
                    try storeDomain.upsertUsageCacheEntries([CachedUsageEntry(usage: usage, cachedAtUnix: nowTS)])
                } else {
                    state.staleUsageAccounts.insert(accountID)
                    if state.accounts[index].usage == nil {
                        state.accounts[index].usage = usage
                    }
                }
            }
        } catch {
            if let index = state.accounts.firstIndex(where: { $0.account.id == accountID }) {
                state.accounts[index].usageLoading = false
            }
            state.staleUsageAccounts.insert(accountID)
            throw error
        }
    }

    private func refreshSingleUsageAutomatic(accountID: String) async throws -> Bool {
        let nowTS = Int64(Date().timeIntervalSince1970)
        let usage = state.accounts.first { $0.account.id == accountID }?.usage

        if !shouldRefreshUsage(usage: usage, nowTS: nowTS) {
            return false
        }

        try await refreshSingleUsage(accountID: accountID)
        return true
    }

    private func shouldRefreshUsage(usage: UsageInfo?, nowTS: Int64) -> Bool {
        guard let usage else {
            return true
        }

        return !isWeeklyRefreshPaused(usage: usage, nowTS: nowTS)
    }

    private func isWeeklyRefreshPaused(usage: UsageInfo, nowTS: Int64) -> Bool {
        guard let weeklyRemaining = weeklyRemainingPercent(usage: usage) else {
            return false
        }
        guard weeklyRemaining <= weeklyRefreshPauseThresholdPercent else {
            return false
        }
        guard let resetAt = usage.secondaryResetsAt else {
            return false
        }
        return nowTS < resetAt
    }

    private func weeklyRemainingPercent(usage: UsageInfo) -> Double? {
        guard let used = usage.secondaryUsedPercent else {
            return nil
        }
        return max(0, min(100, 100 - used))
    }

    private func publishSnapshots(now: Date) {
        let nowTS = Int64(now.timeIntervalSince1970)
        statusSnapshot = makeStatusSnapshot(nowTS: nowTS)
        manageSnapshot = makeManageSnapshot(nowTS: nowTS)
        lastSnapshotPublish = now
    }

    private func makeStatusSnapshot(nowTS: Int64) -> StatusMenuSnapshot {
        StatusMenuSnapshot(
            processCount: state.processInfo?.count ?? 0,
            canSwitch: !state.hasRunningProcesses(),
            isRefreshingUsage: state.refreshingAll || refreshAllInFlight,
            accounts: orderedAccountsForDisplay(state.accounts).map { row in
                StatusAccountEntry(
                    id: row.account.id,
                    name: row.account.name,
                    isActive: row.account.isActive,
                    isStale: isUsageStale(accountID: row.account.id, usage: row.usage, nowTS: nowTS),
                    fiveHourRemaining: remainingPercentFromUsed(row.usage?.primaryUsedPercent),
                    weeklyRemaining: remainingPercentFromUsed(row.usage?.secondaryUsedPercent),
                    usageError: row.usage?.error
                )
            }
        )
    }

    private func makeManageSnapshot(nowTS: Int64) -> ManageAccountsWindowSnapshot {
        ManageAccountsWindowSnapshot(
            accounts: orderedAccountsForDisplay(state.accounts).map { account in
                ManageAccountItem(
                    id: account.account.id,
                    name: account.account.name,
                    isActive: account.account.isActive,
                    isStale: isUsageStale(accountID: account.account.id, usage: account.usage, nowTS: nowTS),
                    email: account.account.email,
                    authModeLabel: account.account.authMode == .apiKey ? "API key" : "ChatGPT",
                    plan: account.account.planType,
                    lastUsed: account.account.lastUsedAt.map(formatLastUsed),
                    fiveHourRemaining: remainingPercentFromUsed(account.usage?.primaryUsedPercent),
                    weeklyRemaining: remainingPercentFromUsed(account.usage?.secondaryUsedPercent),
                    weeklyResetCountdown: formatWeeklyResetCountdown(resetsAtUnix: account.usage?.secondaryResetsAt, nowTS: nowTS),
                    usageError: account.usage?.error,
                    isUsageRefreshing: account.usageLoading,
                    usageLastRefreshed: state.usageCachedAtUnix[account.account.id].map(formatUsageRefreshed)
                )
            },
            canSwitch: !state.hasRunningProcesses(),
            sidebarMode: state.sidebarMode
        )
    }

    private func isUsageStale(accountID: String, usage: UsageInfo?, nowTS: Int64) -> Bool {
        guard usage != nil else {
            return false
        }

        if state.staleUsageAccounts.contains(accountID) {
            return true
        }

        if let cachedAt = state.usageCachedAtUnix[accountID] {
            return nowTS - cachedAt > SERVICE_STALE_THRESHOLD_SECONDS
        }

        return false
    }

    private func setError(_ message: String) {
        pendingErrorForUI = message
    }
}

private struct DisplayOrderKey {
    let row: AccountWithUsage
    let index: Int
    let weeklyRemaining: UInt8?
    let weeklyResetAtUnix: Int64?
    let isLowWeekly: Bool
}

private func orderedAccountsForDisplay(_ accounts: [AccountWithUsage]) -> [AccountWithUsage] {
    let keyed = accounts.enumerated().map { index, row in
        let weeklyRemaining = remainingPercentFromUsed(row.usage?.secondaryUsedPercent)
        return DisplayOrderKey(
            row: row,
            index: index,
            weeklyRemaining: weeklyRemaining,
            weeklyResetAtUnix: row.usage?.secondaryResetsAt,
            isLowWeekly: weeklyRemaining.map { Double($0) <= weeklyRefreshAllSkipThresholdPercent } ?? false
        )
    }

    return keyed
        .sorted(by: { a, b in
            if a.isLowWeekly && b.isLowWeekly {
                // In the low-weekly bucket, prioritize accounts that reset sooner over raw percentage.
                switch (a.weeklyResetAtUnix, b.weeklyResetAtUnix) {
                case let (aReset?, bReset?):
                    if aReset != bReset {
                        return aReset < bReset
                    }
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    break
                }
                return a.index < b.index
            }

            switch (a.weeklyRemaining, b.weeklyRemaining) {
            case let (aValue?, bValue?):
                if aValue != bValue {
                    return aValue > bValue
                }
                return a.index < b.index
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return a.index < b.index
            }
        })
        .map(\.row)
}

private func formatLastUsed(_ date: Date) -> String {
    RuntimeDateFormatter.lock.lock()
    defer { RuntimeDateFormatter.lock.unlock() }
    return RuntimeDateFormatter.lastUsed.string(from: date)
}

private func formatUsageRefreshed(_ cachedAtUnix: Int64) -> String {
    formatLastUsed(Date(timeIntervalSince1970: TimeInterval(cachedAtUnix)))
}

private func formatWeeklyResetCountdown(resetsAtUnix: Int64?, nowTS: Int64) -> String? {
    guard let resetTS = resetsAtUnix else {
        return nil
    }

    let secondsRemaining = max(0, resetTS - nowTS)
    let hoursRemaining = secondsRemaining == 0 ? 0 : (secondsRemaining + 3599) / 3600
    let days = hoursRemaining / 24
    let hours = hoursRemaining % 24

    if days > 0 {
        return "\(days)d \(hours)h"
    }

    return "\(hours)h"
}

private enum RuntimeDateFormatter {
    static let lock = NSLock()
    static let lastUsed: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter
    }()
}
