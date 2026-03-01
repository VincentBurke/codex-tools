import Foundation

public final class FileAuthSwitcher: AuthSwitcher, @unchecked Sendable {
    public init() {}

    public func switchToAccount(_ account: StoredAccount) throws {
        let codexHome = try CodexPaths.codexHome()
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)

        let auth = createAuthJSON(from: account)
        let data = try CodexJSON.makeEncoder().encode(auth)

        let path = try CodexPaths.codexAuthFile()
        try data.write(to: path, options: [.atomic])
        try setSecurePermissions(fileURL: path)
    }

    public func readCurrentAuth() throws -> AuthDotJSON? {
        let path = try CodexPaths.codexAuthFile()
        guard FileManager.default.fileExists(atPath: path.path) else {
            return nil
        }

        let data = try Data(contentsOf: path)
        return try CodexJSON.makeDecoder().decode(AuthDotJSON.self, from: data)
    }

    public func importFromAuthJSON(path: String) throws -> StoredAccount {
        let fileURL = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: fileURL)
        let auth = try CodexJSON.makeDecoder().decode(AuthDotJSON.self, from: data)

        if auth.openAIApiKey != nil {
            throw NSError(
                domain: "FileAuthSwitcher",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "auth.json API-key imports are not supported without an email-backed account"]
            )
        }

        if let tokens = auth.tokens {
            let claims = parseIDTokenClaims(tokens.idToken)
            guard let email = claims.email?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !email.isEmpty
            else {
                throw NSError(
                    domain: "FileAuthSwitcher",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Could not determine account email from auth.json"]
                )
            }

            return StoredAccount.newChatGPT(
                name: StoredAccount.defaultDisplayName(fromEmail: email),
                email: email,
                planType: claims.planType,
                idToken: tokens.idToken,
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken,
                accountID: claims.accountID ?? tokens.accountID
            )
        }

        throw NSError(
            domain: "FileAuthSwitcher",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "auth.json contains neither API key nor tokens"]
        )
    }
}

public func createAuthJSON(from account: StoredAccount) -> AuthDotJSON {
    switch account.authData {
    case .apiKey(let key):
        return AuthDotJSON(openAIApiKey: key, tokens: nil, lastRefresh: nil)
    case .chatgpt(let idToken, let accessToken, let refreshToken, let accountID):
        return AuthDotJSON(
            openAIApiKey: nil,
            tokens: TokenData(
                idToken: idToken,
                accessToken: accessToken,
                refreshToken: refreshToken,
                accountID: accountID
            ),
            lastRefresh: Date()
        )
    }
}

public struct IDTokenClaims: Sendable, Equatable {
    public var email: String?
    public var planType: String?
    public var accountID: String?

    public init(email: String?, planType: String?, accountID: String?) {
        self.email = email
        self.planType = planType
        self.accountID = accountID
    }
}

public func parseIDTokenClaims(_ idToken: String) -> IDTokenClaims {
    let parts = idToken.split(separator: ".")
    guard parts.count == 3 else {
        return IDTokenClaims(email: nil, planType: nil, accountID: nil)
    }

    guard let payload = decodeBase64URL(String(parts[1])) else {
        return IDTokenClaims(email: nil, planType: nil, accountID: nil)
    }

    guard
        let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
    else {
        return IDTokenClaims(email: nil, planType: nil, accountID: nil)
    }

    let email = object["email"] as? String
    let authClaims = object["https://api.openai.com/auth"] as? [String: Any]
    let planType = authClaims?["chatgpt_plan_type"] as? String
    let accountID = authClaims?["chatgpt_account_id"] as? String

    return IDTokenClaims(email: email, planType: planType, accountID: accountID)
}

func decodeBase64URL(_ value: String) -> Data? {
    var base64 = value.replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")

    let padding = 4 - (base64.count % 4)
    if padding < 4 {
        base64 += String(repeating: "=", count: padding)
    }

    return Data(base64Encoded: base64)
}
