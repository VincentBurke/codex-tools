import CodexToolsCore
import Foundation
import XCTest

final class ModelFormatTests: XCTestCase {
    func testDecodesRustChatGPTSnakeCaseEnumValues() throws {
        let json = """
        {
          "id": "id-1",
          "name": "acct",
          "email": null,
          "plan_type": "team",
          "auth_mode": "chat_g_p_t",
          "auth_data": {
            "type": "chat_g_p_t",
            "id_token": "id",
            "access_token": "access",
            "refresh_token": "refresh",
            "account_id": "acct-id"
          },
          "created_at": "2026-02-23T06:07:20.648606Z",
          "last_used_at": null
        }
        """

        let decoded = try CodexJSON.makeDecoder().decode(StoredAccount.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.authMode, .chatGPT)

        switch decoded.authData {
        case .chatgpt(let idToken, let accessToken, let refreshToken, let accountID):
            XCTAssertEqual(idToken, "id")
            XCTAssertEqual(accessToken, "access")
            XCTAssertEqual(refreshToken, "refresh")
            XCTAssertEqual(accountID, "acct-id")
        default:
            XCTFail("Expected ChatGPT auth data")
        }
    }

    func testRejectsLegacyChatGPTAliasEnumValues() throws {
        let json = """
        {
          "id": "id-1",
          "name": "acct",
          "email": null,
          "plan_type": "team",
          "auth_mode": "chatgpt",
          "auth_data": {
            "type": "chatgpt",
            "id_token": "id",
            "access_token": "access",
            "refresh_token": "refresh",
            "account_id": "acct-id"
          },
          "created_at": "2026-02-23T06:07:20.648606Z",
          "last_used_at": null
        }
        """

        XCTAssertThrowsError(try CodexJSON.makeDecoder().decode(StoredAccount.self, from: Data(json.utf8)))
    }

    func testEncodesChatGPTAsRustSnakeCaseValues() throws {
        let account = StoredAccount.newChatGPT(
            name: "acct",
            email: nil,
            planType: "team",
            idToken: "id",
            accessToken: "access",
            refreshToken: "refresh",
            accountID: "acct-id"
        )

        let data = try CodexJSON.makeEncoder().encode(account)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["auth_mode"] as? String, "chat_g_p_t")

        let authData = object?["auth_data"] as? [String: Any]
        XCTAssertEqual(authData?["type"] as? String, "chat_g_p_t")
    }

    func testDefaultDisplayNameUsesEmailLocalPart() {
        XCTAssertEqual(
            StoredAccount.defaultDisplayName(fromEmail: "devdotme@proton.me"),
            "devdotme"
        )
    }

    func testDefaultDisplayNameFallsBackToTrimmedInputWhenLocalPartMissing() {
        XCTAssertEqual(
            StoredAccount.defaultDisplayName(fromEmail: "  @proton.me  "),
            "@proton.me"
        )
    }
}
