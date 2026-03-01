import Foundation

public final class FileStoreRepository: AccountsStoreRepository, UISettingsRepository, @unchecked Sendable {
    public init() {}

    public func loadStore() throws -> AccountsStore {
        // Hard-cutover migration: move persisted state from codex-switcher path
        // into codex-tools path once, so renamed installs keep existing accounts.
        try migrateLegacyFilesIfNeeded()

        let path = try CodexPaths.accountsFile()
        guard FileManager.default.fileExists(atPath: path.path) else {
            return AccountsStore()
        }

        let data = try Data(contentsOf: path)
        let store = try CodexJSON.makeDecoder().decode(AccountsStore.self, from: data)

        if store.version != accountsStoreVersion {
            throw NSError(
                domain: "FileStoreRepository",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Unsupported accounts schema version \(store.version) (required \(accountsStoreVersion))"
                ]
            )
        }

        return store
    }

    public func saveStore(_ store: AccountsStore) throws {
        let path = try CodexPaths.accountsFile()
        try ensureParentDirectory(for: path)

        var normalized = store
        normalized.version = accountsStoreVersion
        _ = pruneUsageCacheToExistingAccounts(&normalized)

        let data = try CodexJSON.makeEncoder().encode(normalized)
        try data.write(to: path, options: [.atomic])
        try setSecurePermissions(fileURL: path)
    }

    public func loadSidebarMode() throws -> SidebarMode {
        try migrateLegacyFilesIfNeeded()

        let path = try CodexPaths.uiFile()
        guard FileManager.default.fileExists(atPath: path.path) else {
            return .compact
        }

        struct UISettings: Codable {
            let sidebarMode: SidebarMode

            enum CodingKeys: String, CodingKey {
                case sidebarMode = "sidebar_mode"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                sidebarMode = try container.decodeIfPresent(SidebarMode.self, forKey: .sidebarMode) ?? .compact
            }

            init(sidebarMode: SidebarMode) {
                self.sidebarMode = sidebarMode
            }
        }

        let data = try Data(contentsOf: path)
        let settings = try CodexJSON.makeDecoder().decode(UISettings.self, from: data)
        return settings.sidebarMode
    }

    public func saveSidebarMode(_ mode: SidebarMode) throws {
        struct UISettings: Codable {
            let sidebarMode: SidebarMode

            enum CodingKeys: String, CodingKey {
                case sidebarMode = "sidebar_mode"
            }

            init(sidebarMode: SidebarMode) {
                self.sidebarMode = sidebarMode
            }
        }

        let path = try CodexPaths.uiFile()
        try ensureParentDirectory(for: path)
        let data = try CodexJSON.makeEncoder().encode(UISettings(sidebarMode: mode))
        try data.write(to: path, options: [.atomic])
        try setSecurePermissions(fileURL: path)
    }

    private func migrateLegacyFilesIfNeeded() throws {
        let env = ProcessInfo.processInfo.environment
        let hasCurrentOverride = !(env["CODEX_TOOLS_HOME"] ?? "").isEmpty
        let hasLegacyOverride = !(env["CODEX_SWITCHER_HOME"] ?? "").isEmpty

        // If callers pin CODEX_TOOLS_HOME explicitly, do not silently pull
        // state from the default legacy directory. Explicit legacy override
        // remains supported for intentional migration.
        if hasCurrentOverride && !hasLegacyOverride {
            return
        }

        let fileManager = FileManager.default

        let currentAccounts = try CodexPaths.accountsFile()
        if !fileManager.fileExists(atPath: currentAccounts.path) {
            let legacyAccounts = try CodexPaths.legacyAccountsFile()
            if fileManager.fileExists(atPath: legacyAccounts.path) {
                try ensureParentDirectory(for: currentAccounts)
                try fileManager.copyItem(at: legacyAccounts, to: currentAccounts)
                try setSecurePermissions(fileURL: currentAccounts)
            }
        }

        let currentUI = try CodexPaths.uiFile()
        if !fileManager.fileExists(atPath: currentUI.path) {
            let legacyUI = try CodexPaths.legacyUIFile()
            if fileManager.fileExists(atPath: legacyUI.path) {
                try ensureParentDirectory(for: currentUI)
                try fileManager.copyItem(at: legacyUI, to: currentUI)
                try setSecurePermissions(fileURL: currentUI)
            }
        }
    }
}

public func pruneUsageCacheToExistingAccounts(_ store: inout AccountsStore) -> Bool {
    let validIDs = Set(store.accounts.map(\.id))
    let before = store.usageCache.count
    store.usageCache = store.usageCache.filter { validIDs.contains($0.key) }
    return store.usageCache.count != before
}

public final class StoreDomain: @unchecked Sendable {
    private let accountsRepository: AccountsStoreRepository
    private let uiRepository: UISettingsRepository

    public init(
        accountsRepository: AccountsStoreRepository,
        uiRepository: UISettingsRepository
    ) {
        self.accountsRepository = accountsRepository
        self.uiRepository = uiRepository
    }

    public func listAccountsInfo() throws -> [AccountInfo] {
        let store = try accountsRepository.loadStore()
        return store.accounts.map { AccountInfo.fromStored($0, activeID: store.activeAccountID) }
    }

    public func addAccount(_ account: StoredAccount) throws -> StoredAccount {
        var store = try accountsRepository.loadStore()
        if let emailKey = normalizedEmailKey(account.email),
           store.accounts.contains(where: { normalizedEmailKey($0.email) == emailKey })
        {
            throw NSError(
                domain: "StoreDomain",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "An account with email '\(emailKey)' already exists"]
            )
        }

        if store.accounts.contains(where: { $0.name == account.name }) {
            throw NSError(
                domain: "StoreDomain",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "An account with name '\(account.name)' already exists"]
            )
        }

        let cloned = account
        store.accounts.append(account)
        if store.accounts.count == 1 {
            store.activeAccountID = cloned.id
        }

        try accountsRepository.saveStore(store)
        return cloned
    }

    public func removeAccount(_ accountID: String) throws {
        var store = try accountsRepository.loadStore()
        let initial = store.accounts.count
        store.accounts.removeAll { $0.id == accountID }
        if store.accounts.count == initial {
            throw NSError(
                domain: "StoreDomain",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Account not found: \(accountID)"]
            )
        }

        if store.activeAccountID == accountID {
            store.activeAccountID = store.accounts.first?.id
        }
        store.usageCache.removeValue(forKey: accountID)

        try accountsRepository.saveStore(store)
    }

    public func setActiveAccount(_ accountID: String) throws {
        var store = try accountsRepository.loadStore()
        guard store.accounts.contains(where: { $0.id == accountID }) else {
            throw NSError(
                domain: "StoreDomain",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Account not found: \(accountID)"]
            )
        }
        store.activeAccountID = accountID
        try accountsRepository.saveStore(store)
    }

    public func getAccount(_ accountID: String) throws -> StoredAccount? {
        let store = try accountsRepository.loadStore()
        return store.accounts.first { $0.id == accountID }
    }

    public func getActiveAccount() throws -> StoredAccount? {
        let store = try accountsRepository.loadStore()
        guard let activeID = store.activeAccountID else {
            return nil
        }
        return store.accounts.first { $0.id == activeID }
    }

    public func touchAccount(_ accountID: String) throws {
        var store = try accountsRepository.loadStore()
        if let index = store.accounts.firstIndex(where: { $0.id == accountID }) {
            store.accounts[index].lastUsedAt = Date()
            try accountsRepository.saveStore(store)
        }
    }

    public func updateAccountMetadata(
        accountID: String,
        name: String?,
        email: String?,
        planType: String?
    ) throws {
        var store = try accountsRepository.loadStore()

        if let newName = name, store.accounts.contains(where: { $0.id != accountID && $0.name == newName }) {
            throw NSError(
                domain: "StoreDomain",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "An account with name '\(newName)' already exists"]
            )
        }

        if let emailKey = normalizedEmailKey(email),
           store.accounts.contains(where: { $0.id != accountID && normalizedEmailKey($0.email) == emailKey })
        {
            throw NSError(
                domain: "StoreDomain",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "An account with email '\(emailKey)' already exists"]
            )
        }

        guard let index = store.accounts.firstIndex(where: { $0.id == accountID }) else {
            throw NSError(
                domain: "StoreDomain",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Account not found"]
            )
        }

        if let name {
            store.accounts[index].name = name
        }
        if let email {
            store.accounts[index].email = email
        }
        if let planType {
            store.accounts[index].planType = planType
        }

        try accountsRepository.saveStore(store)
    }

    public func loadUsageCache() throws -> [String: CachedUsageEntry] {
        try accountsRepository.loadStore().usageCache
    }

    public func upsertUsageCacheEntries(_ entries: [CachedUsageEntry]) throws {
        var store = try accountsRepository.loadStore()
        for entry in entries {
            store.usageCache[entry.usage.accountID] = entry
        }
        try accountsRepository.saveStore(store)
    }

    public func removeUsageCacheEntry(accountID: String) throws {
        var store = try accountsRepository.loadStore()
        store.usageCache.removeValue(forKey: accountID)
        try accountsRepository.saveStore(store)
    }

    public func loadStore() throws -> AccountsStore {
        try accountsRepository.loadStore()
    }

    public func saveStore(_ store: AccountsStore) throws {
        try accountsRepository.saveStore(store)
    }

    public func loadSidebarMode() throws -> SidebarMode {
        try uiRepository.loadSidebarMode()
    }

    public func saveSidebarMode(_ mode: SidebarMode) throws {
        try uiRepository.saveSidebarMode(mode)
    }
}

private func normalizedEmailKey(_ email: String?) -> String? {
    guard let email else {
        return nil
    }

    let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }
    return trimmed.lowercased()
}
