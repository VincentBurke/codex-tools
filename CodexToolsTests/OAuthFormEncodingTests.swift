@testable import CodexToolsCore
import Darwin
import XCTest

final class OAuthFormEncodingTests: XCTestCase {
    func testOAuthListenerRetryClassifierAllowsAddressInUse() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(EADDRINUSE))
        XCTAssertTrue(shouldRetryOAuthListenerStart(for: error))
    }

    func testOAuthListenerRetryClassifierRejectsNonAddressInUse() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        XCTAssertFalse(shouldRetryOAuthListenerStart(for: error))
    }

    func testMakeFormURLEncodedBodyPercentEncodesReservedCharacters() throws {
        let body = try makeFormURLEncodedBody(fields: [
            ("code", "a+b&c=d"),
            ("redirect_uri", "http://localhost:1455/auth/callback?x=1&y=2")
        ])

        let text = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertEqual(
            text,
            "code=a%2Bb%26c%3Dd&redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback%3Fx%3D1%26y%3D2"
        )
    }

    func testFormEncodeComponentUsesStrictRFC3986AllowedSet() throws {
        XCTAssertEqual(try formEncodeComponent("scope with spaces", fieldName: "scope"), "scope%20with%20spaces")
        XCTAssertEqual(try formEncodeComponent("~.-_", fieldName: "scope"), "~.-_")
    }
}
