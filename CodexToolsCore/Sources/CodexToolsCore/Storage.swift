import Foundation

public final class FileStoreRepository: AccountsStoreRepository, @unchecked Sendable {
    public init() {}

    public func loadStore() throws -> AccountsStore {
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

}

public func pruneUsageCacheToExistingAccounts(_ store: inout AccountsStore) -> Bool {
    let validIDs = Set(store.accounts.map(\.id))
    let before = store.usageCache.count
    store.usageCache = store.usageCache.filter { validIDs.contains($0.key) }
    return store.usageCache.count != before
}

public final class StoreDomain: @unchecked Sendable {
    private let accountsRepository: AccountsStoreRepository

    public init(accountsRepository: AccountsStoreRepository) {
        self.accountsRepository = accountsRepository
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

        store.accounts.append(account)
        if store.accounts.count == 1 {
            store.activeAccountID = account.id
        }

        try accountsRepository.saveStore(store)
        return account
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

    public func loadStore() throws -> AccountsStore {
        try accountsRepository.loadStore()
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
