import Foundation

public let accountsStoreVersion = 2

public enum AuthMode: Sendable, Equatable {
    case apiKey
    case chatGPT
}

extension AuthMode: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "api_key":
            self = .apiKey
        case "chat_g_p_t":
            self = .chatGPT
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported auth mode: \(value)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .apiKey:
            try container.encode("api_key")
        case .chatGPT:
            // Match Rust serde rename_all = snake_case for ChatGPT.
            try container.encode("chat_g_p_t")
        }
    }
}

public enum AuthData: Sendable, Equatable {
    case apiKey(key: String)
    case chatgpt(
        idToken: String,
        accessToken: String,
        refreshToken: String,
        accountID: String?
    )
}

extension AuthData: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case key
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case accountID = "account_id"
    }

    private enum Kind: String, Codable {
        case apiKey = "api_key"
        case chatGPT = "chat_g_p_t"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = try container.decode(String.self, forKey: .type)
        let type: Kind
        switch rawType {
        case "api_key":
            type = .apiKey
        case "chat_g_p_t":
            type = .chatGPT
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported auth_data.type: \(rawType)"
            )
        }
        switch type {
        case .apiKey:
            let key = try container.decode(String.self, forKey: .key)
            self = .apiKey(key: key)
        case .chatGPT:
            self = .chatgpt(
                idToken: try container.decode(String.self, forKey: .idToken),
                accessToken: try container.decode(String.self, forKey: .accessToken),
                refreshToken: try container.decode(String.self, forKey: .refreshToken),
                accountID: try container.decodeIfPresent(String.self, forKey: .accountID)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .apiKey(let key):
            try container.encode(Kind.apiKey, forKey: .type)
            try container.encode(key, forKey: .key)
        case .chatgpt(let idToken, let accessToken, let refreshToken, let accountID):
            try container.encode(Kind.chatGPT, forKey: .type)
            try container.encode(idToken, forKey: .idToken)
            try container.encode(accessToken, forKey: .accessToken)
            try container.encode(refreshToken, forKey: .refreshToken)
            try container.encodeIfPresent(accountID, forKey: .accountID)
        }
    }
}

public struct StoredAccount: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var email: String?
    public var planType: String?
    public var authMode: AuthMode
    public var authData: AuthData
    public var createdAt: Date
    public var lastUsedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case email
        case planType = "plan_type"
        case authMode = "auth_mode"
        case authData = "auth_data"
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
    }

    public static func newAPIKey(name: String, apiKey: String) -> StoredAccount {
        StoredAccount(
            id: UUID().uuidString.lowercased(),
            name: name,
            email: nil,
            planType: nil,
            authMode: .apiKey,
            authData: .apiKey(key: apiKey),
            createdAt: Date(),
            lastUsedAt: nil
        )
    }

    public static func newChatGPT(
        name: String,
        email: String?,
        planType: String?,
        idToken: String,
        accessToken: String,
        refreshToken: String,
        accountID: String?
    ) -> StoredAccount {
        StoredAccount(
            id: UUID().uuidString.lowercased(),
            name: name,
            email: email,
            planType: planType,
            authMode: .chatGPT,
            authData: .chatgpt(
                idToken: idToken,
                accessToken: accessToken,
                refreshToken: refreshToken,
                accountID: accountID
            ),
            createdAt: Date(),
            lastUsedAt: nil
        )
    }

    public static func defaultDisplayName(fromEmail email: String) -> String {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let atSign = trimmedEmail.firstIndex(of: "@"),
            atSign > trimmedEmail.startIndex
        else {
            return trimmedEmail
        }
        return String(trimmedEmail[..<atSign])
    }
}

public struct CachedUsageEntry: Codable, Sendable, Equatable {
    public var usage: UsageInfo
    public var cachedAtUnix: Int64

    private enum CodingKeys: String, CodingKey {
        case usage
        case cachedAtUnix = "cached_at_unix"
    }

    public init(usage: UsageInfo, cachedAtUnix: Int64) {
        self.usage = usage
        self.cachedAtUnix = cachedAtUnix
    }
}

public struct AccountsStore: Codable, Sendable, Equatable {
    public var version: Int
    public var accounts: [StoredAccount]
    public var activeAccountID: String?
    public var usageCache: [String: CachedUsageEntry]

    private enum CodingKeys: String, CodingKey {
        case version
        case accounts
        case activeAccountID = "active_account_id"
        case usageCache = "usage_cache"
    }

    public init(
        version: Int = accountsStoreVersion,
        accounts: [StoredAccount] = [],
        activeAccountID: String? = nil,
        usageCache: [String: CachedUsageEntry] = [:]
    ) {
        self.version = version
        self.accounts = accounts
        self.activeAccountID = activeAccountID
        self.usageCache = usageCache
    }
}

public struct AuthDotJSON: Codable, Sendable, Equatable {
    public var openAIApiKey: String?
    public var tokens: TokenData?
    public var lastRefresh: Date?

    private enum CodingKeys: String, CodingKey {
        case openAIApiKey = "OPENAI_API_KEY"
        case tokens
        case lastRefresh = "last_refresh"
    }

    public init(openAIApiKey: String?, tokens: TokenData?, lastRefresh: Date?) {
        self.openAIApiKey = openAIApiKey
        self.tokens = tokens
        self.lastRefresh = lastRefresh
    }
}

public struct TokenData: Codable, Sendable, Equatable {
    public var idToken: String
    public var accessToken: String
    public var refreshToken: String
    public var accountID: String?

    private enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case accountID = "account_id"
    }

    public init(idToken: String, accessToken: String, refreshToken: String, accountID: String?) {
        self.idToken = idToken
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accountID = accountID
    }
}

public struct AccountInfo: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var email: String?
    public var planType: String?
    public var authMode: AuthMode
    public var isActive: Bool
    public var createdAt: Date
    public var lastUsedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case email
        case planType = "plan_type"
        case authMode = "auth_mode"
        case isActive = "is_active"
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
    }

    public static func fromStored(_ account: StoredAccount, activeID: String?) -> AccountInfo {
        AccountInfo(
            id: account.id,
            name: account.name,
            email: account.email,
            planType: account.planType,
            authMode: account.authMode,
            isActive: activeID == account.id,
            createdAt: account.createdAt,
            lastUsedAt: account.lastUsedAt
        )
    }
}

public struct UsageInfo: Codable, Sendable, Equatable {
    public var accountID: String
    public var planType: String?
    public var primaryUsedPercent: Double?
    public var primaryWindowMinutes: Int?
    public var primaryResetsAt: Int64?
    public var secondaryUsedPercent: Double?
    public var secondaryWindowMinutes: Int?
    public var secondaryResetsAt: Int64?
    public var hasCredits: Bool?
    public var unlimitedCredits: Bool?
    public var creditsBalance: String?
    public var error: String?

    private enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case planType = "plan_type"
        case primaryUsedPercent = "primary_used_percent"
        case primaryWindowMinutes = "primary_window_minutes"
        case primaryResetsAt = "primary_resets_at"
        case secondaryUsedPercent = "secondary_used_percent"
        case secondaryWindowMinutes = "secondary_window_minutes"
        case secondaryResetsAt = "secondary_resets_at"
        case hasCredits = "has_credits"
        case unlimitedCredits = "unlimited_credits"
        case creditsBalance = "credits_balance"
        case error
    }

    public init(
        accountID: String,
        planType: String?,
        primaryUsedPercent: Double?,
        primaryWindowMinutes: Int?,
        primaryResetsAt: Int64?,
        secondaryUsedPercent: Double?,
        secondaryWindowMinutes: Int?,
        secondaryResetsAt: Int64?,
        hasCredits: Bool?,
        unlimitedCredits: Bool?,
        creditsBalance: String?,
        error: String?
    ) {
        self.accountID = accountID
        self.planType = planType
        self.primaryUsedPercent = primaryUsedPercent
        self.primaryWindowMinutes = primaryWindowMinutes
        self.primaryResetsAt = primaryResetsAt
        self.secondaryUsedPercent = secondaryUsedPercent
        self.secondaryWindowMinutes = secondaryWindowMinutes
        self.secondaryResetsAt = secondaryResetsAt
        self.hasCredits = hasCredits
        self.unlimitedCredits = unlimitedCredits
        self.creditsBalance = creditsBalance
        self.error = error
    }

    public static func error(accountID: String, message: String) -> UsageInfo {
        UsageInfo(
            accountID: accountID,
            planType: nil,
            primaryUsedPercent: nil,
            primaryWindowMinutes: nil,
            primaryResetsAt: nil,
            secondaryUsedPercent: nil,
            secondaryWindowMinutes: nil,
            secondaryResetsAt: nil,
            hasCredits: nil,
            unlimitedCredits: nil,
            creditsBalance: nil,
            error: message
        )
    }
}

public struct OAuthLoginInfo: Codable, Sendable, Equatable {
    public var authURL: String
    public var callbackPort: UInt16

    private enum CodingKeys: String, CodingKey {
        case authURL = "auth_url"
        case callbackPort = "callback_port"
    }

    public init(authURL: String, callbackPort: UInt16) {
        self.authURL = authURL
        self.callbackPort = callbackPort
    }
}

public struct OAuthLoginResult: Sendable, Equatable {
    public var account: StoredAccount

    public init(account: StoredAccount) {
        self.account = account
    }
}

public struct CodexProcessInfo: Codable, Sendable, Equatable {
    public var count: Int
    public var canSwitch: Bool
    public var pids: [Int32]

    private enum CodingKeys: String, CodingKey {
        case count
        case canSwitch = "can_switch"
        case pids
    }

    public init(count: Int, canSwitch: Bool, pids: [Int32]) {
        self.count = count
        self.canSwitch = canSwitch
        self.pids = pids
    }
}

public struct RateLimitStatusPayload: Codable, Sendable, Equatable {
    public var planType: String
    public var rateLimit: RateLimitDetails?
    public var credits: CreditStatusDetails?

    private enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
    }

    public init(planType: String, rateLimit: RateLimitDetails?, credits: CreditStatusDetails?) {
        self.planType = planType
        self.rateLimit = rateLimit
        self.credits = credits
    }
}

public struct RateLimitDetails: Codable, Sendable, Equatable {
    public var primaryWindow: RateLimitWindow?
    public var secondaryWindow: RateLimitWindow?

    private enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }

    public init(primaryWindow: RateLimitWindow?, secondaryWindow: RateLimitWindow?) {
        self.primaryWindow = primaryWindow
        self.secondaryWindow = secondaryWindow
    }
}

public struct RateLimitWindow: Codable, Sendable, Equatable {
    public var usedPercent: Double
    public var limitWindowSeconds: Int?
    public var resetAt: Int64?

    private enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
    }

    public init(usedPercent: Double, limitWindowSeconds: Int?, resetAt: Int64?) {
        self.usedPercent = usedPercent
        self.limitWindowSeconds = limitWindowSeconds
        self.resetAt = resetAt
    }
}

public struct CreditStatusDetails: Codable, Sendable, Equatable {
    public var hasCredits: Bool
    public var unlimited: Bool
    public var balance: String?

    private enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }

    public init(hasCredits: Bool, unlimited: Bool, balance: String?) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }
}
