import CodexToolsCore
import Foundation
import XCTest

final class SwitcherTests: XCTestCase {
    func testSwitchToAPIKeyWritesOpenAIKeyAuthJSON() throws {
        let temp = try makeTempDirectory()
        try withEnv("CODEX_HOME", temp.path) {
            let switcher = FileAuthSwitcher()
            let account = StoredAccount.newAPIKey(name: "API", apiKey: "sk-test")

            try switcher.switchToAccount(account)

            let authPath = try CodexPaths.codexAuthFile()
            let data = try Data(contentsOf: authPath)
            let auth = try CodexJSON.makeDecoder().decode(AuthDotJSON.self, from: data)

            XCTAssertEqual(auth.openAIApiKey, "sk-test")
            XCTAssertNil(auth.tokens)
            XCTAssertEqual(try fileMode(authPath) & 0o777, 0o600)
        }
    }

    func testSwitchToChatGPTWritesTokenAuthJSON() throws {
        let temp = try makeTempDirectory()
        try withEnv("CODEX_HOME", temp.path) {
            let switcher = FileAuthSwitcher()
            let account = StoredAccount.newChatGPT(
                name: "ChatGPT",
                email: "user@example.com",
                planType: "plus",
                idToken: "id-token",
                accessToken: "access-token",
                refreshToken: "refresh-token",
                accountID: "account-1"
            )

            try switcher.switchToAccount(account)

            let authPath = try CodexPaths.codexAuthFile()
            let data = try Data(contentsOf: authPath)
            let auth = try CodexJSON.makeDecoder().decode(AuthDotJSON.self, from: data)

            XCTAssertNil(auth.openAIApiKey)
            XCTAssertEqual(auth.tokens?.idToken, "id-token")
            XCTAssertEqual(auth.tokens?.accessToken, "access-token")
            XCTAssertEqual(auth.tokens?.refreshToken, "refresh-token")
            XCTAssertEqual(auth.tokens?.accountID, "account-1")
        }
    }

    func testTouchAccountUpdatesLastUsedAt() throws {
        let temp = try makeTempDirectory()
        try withEnv("CODEX_TOOLS_HOME", temp.path) {
            let repository = FileStoreRepository()
            let domain = StoreDomain(accountsRepository: repository)

            let account = try domain.addAccount(.newAPIKey(name: "Work", apiKey: "sk-123"))
            try domain.touchAccount(account.id)

            let loaded = try domain.getAccount(account.id)
            XCTAssertNotNil(loaded?.lastUsedAt)
        }
    }

    func testImportFromAuthJSONUsesEmailLocalPartAsName() throws {
        let temp = try makeTempDirectory()
        let path = temp.appendingPathComponent("auth.json")
        let email = "devdotme@proton.me"
        let idToken = try makeIDToken(email: email, planType: "team", accountID: "acct-1")
        let raw = """
        {
          "tokens": {
            "id_token": "\(idToken)",
            "access_token": "access-token",
            "refresh_token": "refresh-token",
            "account_id": "acct-1"
          }
        }
        """
        try raw.data(using: .utf8).unwrap().write(to: path)

        let switcher = FileAuthSwitcher()
        let account = try switcher.importFromAuthJSON(path: path.path)

        XCTAssertEqual(account.name, "devdotme")
        XCTAssertEqual(account.email, email)
        XCTAssertEqual(account.planType, "team")
    }

    func testImportFromAuthJSONRejectsAPIKeyOnlyPayload() throws {
        let temp = try makeTempDirectory()
        let path = temp.appendingPathComponent("auth.json")
        let raw = """
        {
          "OPENAI_API_KEY": "sk-test"
        }
        """
        try raw.data(using: .utf8).unwrap().write(to: path)

        let switcher = FileAuthSwitcher()
        XCTAssertThrowsError(try switcher.importFromAuthJSON(path: path.path))
    }
}

private func makeIDToken(email: String, planType: String, accountID: String) throws -> String {
    let header = ["alg": "none", "typ": "JWT"]
    let claims: [String: Any] = [
        "email": email,
        "https://api.openai.com/auth": [
            "chatgpt_plan_type": planType,
            "chatgpt_account_id": accountID
        ]
    ]

    let headerData = try JSONSerialization.data(withJSONObject: header)
    let claimsData = try JSONSerialization.data(withJSONObject: claims)
    return "\(base64URL(headerData)).\(base64URL(claimsData)).signature"
}

private func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
