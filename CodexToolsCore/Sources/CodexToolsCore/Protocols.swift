import Foundation

public protocol AccountsStoreRepository: Sendable {
    func loadStore() throws -> AccountsStore
    func saveStore(_ store: AccountsStore) throws
}

public protocol AuthSwitcher: Sendable {
    func switchToAccount(_ account: StoredAccount) throws
    func importFromAuthJSON(path: String) throws -> StoredAccount
}

public protocol UsageClient: Sendable {
    func getUsage(for account: StoredAccount) async throws -> UsageInfo
    func refreshAllUsage(accounts: [StoredAccount]) async -> [UsageInfo]
}

public enum OAuthPollResult: Sendable, Equatable {
    case idle
    case pending
    case completed(OAuthLoginResult)
    case failed(String)
}

public protocol OAuthClient: Sendable {
    func startLogin(action: OAuthLoginAction) async throws -> OAuthLoginInfo
    func pollLogin() async -> OAuthPollResult
    func cancelLogin() async
}

public protocol ProcessInspector: Sendable {
    func checkCodexProcesses() throws -> CodexProcessInfo
}

public protocol ProcessTerminator: Sendable {
    func terminateCodexProcesses() throws -> Int
}
