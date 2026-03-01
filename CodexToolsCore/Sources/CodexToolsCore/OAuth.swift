import AppKit
import CryptoKit
import Foundation
@preconcurrency import Network
import Security

private let oauthIssuer = "https://auth.openai.com"
private let oauthClientID = "app_EMoamEEZ73f0CkXaXp7hrann"
private let oauthDefaultPort: UInt16 = 1455

public final actor DefaultOAuthClient: OAuthClient {
    private struct PendingLogin {
        let id: UUID
        let server: OAuthCallbackServer
        let task: Task<Void, Never>
        var result: Result<OAuthLoginResult, Error>?
    }

    private var pendingLogin: PendingLogin?
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func startLogin(action: OAuthLoginAction) async throws -> OAuthLoginInfo {
        await cancelLogin()

        let pkce = generatePKCECodes()
        let state = generateState()
        let server = OAuthCallbackServer()
        let callbackPort = try await server.start(preferredPort: oauthDefaultPort)
        let redirectURI = "http://localhost:\(callbackPort)/auth/callback"
        let authURL = try buildAuthorizeURL(
            issuer: oauthIssuer,
            clientID: oauthClientID,
            redirectURI: redirectURI,
            pkce: pkce,
            state: state
        )
        server.setExpectedState(state)
        do {
            try await handleLoginLinkAction(authURL: authURL, action: action)
        } catch {
            server.stop()
            throw error
        }

        let loginID = UUID()
        let task = Task { [session] in
            do {
                let callback = try await server.waitForCallback(
                    timeoutSeconds: 300
                )
                try Task.checkCancellation()

                let tokens = try await exchangeCodeForTokens(
                    session: session,
                    issuer: oauthIssuer,
                    clientID: oauthClientID,
                    redirectURI: redirectURI,
                    pkce: pkce,
                    code: callback.code
                )

                let claims = parseIDTokenClaims(tokens.idToken)
                guard let email = claims.email?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !email.isEmpty
                else {
                    throw NSError(
                        domain: "OAuth",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "Could not determine account email from OAuth login"]
                    )
                }

                let account = StoredAccount.newChatGPT(
                    name: StoredAccount.defaultDisplayName(fromEmail: email),
                    email: email,
                    planType: claims.planType,
                    idToken: tokens.idToken,
                    accessToken: tokens.accessToken,
                    refreshToken: tokens.refreshToken,
                    accountID: claims.accountID ?? tokens.accountID
                )

                self.completeLogin(id: loginID, result: .success(OAuthLoginResult(account: account)))
            } catch {
                self.completeLogin(id: loginID, result: .failure(error))
            }
        }

        pendingLogin = PendingLogin(id: loginID, server: server, task: task, result: nil)

        return OAuthLoginInfo(authURL: authURL, callbackPort: callbackPort)
    }

    public func pollLogin() async -> OAuthPollResult {
        guard let pending = pendingLogin else {
            return .idle
        }

        guard let result = pending.result else {
            return .pending
        }

        pendingLogin = nil
        switch result {
        case .success(let value):
            return .completed(value)
        case .failure(let error):
            return .failed(error.localizedDescription)
        }
    }

    public func cancelLogin() async {
        guard let pending = pendingLogin else {
            return
        }

        pending.task.cancel()
        pending.server.stop()
        pendingLogin = nil
    }

    private func completeLogin(id: UUID, result: Result<OAuthLoginResult, Error>) {
        guard var pending = pendingLogin, pending.id == id else {
            return
        }

        pending.result = result
        pending.server.stop()
        pendingLogin = pending
    }

    private func copyToClipboard(_ text: String) async throws {
        try await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.setString(text, forType: .string) else {
                throw NSError(
                    domain: "OAuth",
                    code: 9,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to copy OAuth URL to clipboard"]
                )
            }
        }
    }

    private func openInDefaultBrowser(_ text: String) async throws {
        guard let url = URL(string: text) else {
            throw NSError(
                domain: "OAuth",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Invalid OAuth URL for browser launch"]
            )
        }

        try await MainActor.run {
            guard NSWorkspace.shared.open(url) else {
                throw NSError(
                    domain: "OAuth",
                    code: 11,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to open default browser for OAuth login"]
                )
            }
        }
    }

    private func handleLoginLinkAction(authURL: String, action: OAuthLoginAction) async throws {
        switch action {
        case .copyLink:
            try await copyToClipboard(authURL)
        case .openDefaultBrowser:
            try await openInDefaultBrowser(authURL)
        }
    }
}

private struct OAuthPKCECodes {
    let codeVerifier: String
    let codeChallenge: String
}

private struct OAuthCallback {
    let code: String
}

private struct OAuthTokens: Decodable {
    let idToken: String
    let accessToken: String
    let refreshToken: String
    let accountID: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case accountID = "account_id"
    }
}

private enum OAuthError: LocalizedError {
    case timeout
    case cancelled
    case callbackServerStopped
    case tokenExchangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "OAuth login timed out"
        case .cancelled:
            return "OAuth login cancelled"
        case .callbackServerStopped:
            return "OAuth callback server stopped before completion"
        case .tokenExchangeFailed(let message):
            return "Token exchange failed: \(message)"
        }
    }
}

private final class OAuthCallbackServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "codextools.oauth.callback")
    private var listener: NWListener?
    private var continuation: CheckedContinuation<OAuthCallback, Error>?
    private var completed = false
    private var expectedState: String = ""

    func start(preferredPort: UInt16) async throws -> UInt16 {
        do {
            return try await start(on: preferredPort)
        } catch {
            // Only retry on an ephemeral port when the preferred callback port is occupied.
            // All other listener startup failures should surface immediately.
            guard preferredPort != 0, shouldRetryOAuthListenerStart(for: error) else {
                throw error
            }
            return try await start(on: 0)
        }
    }

    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            if !self.completed {
                self.completed = true
                self.continuation?.resume(throwing: OAuthError.cancelled)
                self.continuation = nil
            }
        }
    }

    func setExpectedState(_ expectedState: String) {
        queue.sync {
            self.expectedState = expectedState
        }
    }

    func waitForCallback(timeoutSeconds: TimeInterval) async throws -> OAuthCallback {
        return try await withThrowingTaskGroup(of: OAuthCallback.self) { group in
            group.addTask {
                try await self.awaitCallback()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw OAuthError.timeout
            }

            guard let first = try await group.next() else {
                throw OAuthError.callbackServerStopped
            }

            group.cancelAll()
            return first
        }
    }

    private func start(on port: UInt16) async throws -> UInt16 {
        final class ResumeBox: @unchecked Sendable {
            private let lock = NSLock()
            private var resumed = false

            func runOnce(_ body: () -> Void) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else {
                    return
                }
                resumed = true
                body()
            }
        }

        let targetPort = port == 0 ? nil : NWEndpoint.Port(rawValue: port)
        let listener: NWListener
        if let targetPort {
            listener = try NWListener(using: .tcp, on: targetPort)
        } else {
            listener = try NWListener(using: .tcp)
        }

        self.listener = listener
        self.completed = false

        return try await withCheckedThrowingContinuation { continuation in
            let resumeBox = ResumeBox()

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resumeBox.runOnce {
                        continuation.resume(returning: UInt16(listener.port?.rawValue ?? 0))
                    }
                case .failed(let error):
                    resumeBox.runOnce {
                        continuation.resume(throwing: error)
                    }
                default:
                    break
                }
            }

            listener.start(queue: queue)
        }
    }

    private func awaitCallback() async throws -> OAuthCallback {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if self.completed {
                    continuation.resume(throwing: OAuthError.callbackServerStopped)
                    return
                }
                self.continuation = continuation
            }
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, _ in
            guard let data,
                  let rawRequest = String(data: data, encoding: .utf8),
                  let firstLine = rawRequest.components(separatedBy: "\r\n").first
            else {
                self.sendResponse(connection, status: "400 Bad Request", body: "Bad Request")
                connection.cancel()
                return
            }

            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2 else {
                self.sendResponse(connection, status: "400 Bad Request", body: "Bad Request")
                connection.cancel()
                return
            }

            let target = String(parts[1])
            guard let components = URLComponents(string: "http://localhost\(target)") else {
                self.sendResponse(connection, status: "400 Bad Request", body: "Bad Request")
                connection.cancel()
                return
            }

            guard components.path == "/auth/callback" else {
                self.sendResponse(connection, status: "404 Not Found", body: "Not Found")
                connection.cancel()
                return
            }

            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

            if let oauthError = query["error"] {
                let description = query["error_description"] ?? "Unknown error"
                self.sendResponse(connection, status: "400 Bad Request", body: "OAuth Error: \(oauthError) - \(description)")
                self.finish(.failure(NSError(
                    domain: "OAuth",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "OAuth error: \(oauthError) - \(description)"]
                )))
                connection.cancel()
                return
            }

            guard query["state"] == self.expectedState else {
                self.sendResponse(connection, status: "400 Bad Request", body: "State mismatch")
                self.finish(.failure(NSError(
                    domain: "OAuth",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "OAuth state mismatch"]
                )))
                connection.cancel()
                return
            }

            guard let code = query["code"], !code.isEmpty else {
                self.sendResponse(connection, status: "400 Bad Request", body: "Missing authorization code")
                self.finish(.failure(NSError(
                    domain: "OAuth",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Missing authorization code"]
                )))
                connection.cancel()
                return
            }

            let successHTML = """
            <!DOCTYPE html>
            <html>
            <head>
              <title>Login Successful</title>
              <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
              <style>
                body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; background: #f5f6f8; color: #111827; }
                .card { padding: 24px 28px; border-radius: 14px; border: 1px solid #d1d5db; background: white; box-shadow: 0 8px 30px rgba(0,0,0,0.08); text-align: center; }
                .ok { font-size: 28px; margin-bottom: 8px; }
              </style>
            </head>
            <body>
              <div class=\"card\">
                <div class=\"ok\">✓</div>
                <h2>Login successful</h2>
                <p>You can close this tab and return to Codex Tools.</p>
              </div>
            </body>
            </html>
            """

            self.sendResponse(connection, status: "200 OK", body: successHTML, contentType: "text/html; charset=utf-8")
            self.finish(.success(OAuthCallback(code: code)))
            connection.cancel()
        }
    }

    private func sendResponse(
        _ connection: NWConnection,
        status: String,
        body: String,
        contentType: String = "text/plain; charset=utf-8"
    ) {
        let bodyData = Data(body.utf8)
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: \(contentType)\r
        Content-Length: \(bodyData.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
    }

    private func finish(_ result: Result<OAuthCallback, Error>) {
        queue.async {
            guard !self.completed else {
                return
            }
            self.completed = true
            self.listener?.cancel()
            self.listener = nil
            self.continuation?.resume(with: result)
            self.continuation = nil
        }
    }
}

func shouldRetryOAuthListenerStart(for error: Error) -> Bool {
    if let networkError = error as? NWError {
        if case .posix(let code) = networkError {
            return code == .EADDRINUSE
        }
        return false
    }

    if let posixError = error as? POSIXError {
        return posixError.code == .EADDRINUSE
    }

    let nsError = error as NSError
    return nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(EADDRINUSE)
}

private func generatePKCECodes() -> OAuthPKCECodes {
    let verifier = base64URLEncode(randomBytes(count: 64))
    let digest = SHA256.hash(data: Data(verifier.utf8))
    let challenge = base64URLEncode(Data(digest))
    return OAuthPKCECodes(codeVerifier: verifier, codeChallenge: challenge)
}

private func generateState() -> String {
    base64URLEncode(randomBytes(count: 32))
}

private func buildAuthorizeURL(
    issuer: String,
    clientID: String,
    redirectURI: String,
    pkce: OAuthPKCECodes,
    state: String
) throws -> String {
    guard var components = URLComponents(string: "\(issuer)/oauth/authorize") else {
        throw NSError(domain: "OAuth", code: 6, userInfo: [NSLocalizedDescriptionKey: "Invalid authorize URL"])
    }

    components.queryItems = [
        URLQueryItem(name: "response_type", value: "code"),
        URLQueryItem(name: "client_id", value: clientID),
        URLQueryItem(name: "redirect_uri", value: redirectURI),
        URLQueryItem(name: "scope", value: "openid profile email offline_access"),
        URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
        URLQueryItem(name: "code_challenge_method", value: "S256"),
        URLQueryItem(name: "id_token_add_organizations", value: "true"),
        URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
        URLQueryItem(name: "state", value: state),
        URLQueryItem(name: "originator", value: "codex_cli_rs")
    ]

    guard let url = components.url else {
        throw NSError(domain: "OAuth", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to build authorize URL"])
    }

    return url.absoluteString
}

private func exchangeCodeForTokens(
    session: URLSession,
    issuer: String,
    clientID: String,
    redirectURI: String,
    pkce: OAuthPKCECodes,
    code: String
) async throws -> OAuthTokens {
    guard let url = URL(string: "\(issuer)/oauth/token") else {
        throw NSError(domain: "OAuth", code: 8, userInfo: [NSLocalizedDescriptionKey: "Invalid token URL"])
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

    request.httpBody = try makeFormURLEncodedBody(fields: [
        ("grant_type", "authorization_code"),
        ("code", code),
        ("redirect_uri", redirectURI),
        ("client_id", clientID),
        ("code_verifier", pkce.codeVerifier)
    ])

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw OAuthError.tokenExchangeFailed("Invalid token response")
    }

    guard (200...299).contains(http.statusCode) else {
        let text = String(data: data, encoding: .utf8) ?? ""
        throw OAuthError.tokenExchangeFailed("\(http.statusCode) - \(text)")
    }

    return try JSONDecoder().decode(OAuthTokens.self, from: data)
}

private func randomBytes(count: Int) -> Data {
    var bytes = [UInt8](repeating: 0, count: count)
    let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
    precondition(status == errSecSuccess, "Failed to generate secure random bytes")
    return Data(bytes)
}

private func base64URLEncode(_ data: Data) -> String {
    data
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private let urlFormAllowedCharacters: CharacterSet = {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return allowed
}()

func makeFormURLEncodedBody(fields: [(String, String)]) throws -> Data {
    let encoded = try fields.map { key, value in
        let encodedKey = try formEncodeComponent(key, fieldName: key)
        let encodedValue = try formEncodeComponent(value, fieldName: key)
        return "\(encodedKey)=\(encodedValue)"
    }.joined(separator: "&")

    return Data(encoded.utf8)
}

func formEncodeComponent(_ value: String, fieldName: String) throws -> String {
    guard let encoded = value.addingPercentEncoding(withAllowedCharacters: urlFormAllowedCharacters) else {
        throw OAuthError.tokenExchangeFailed("Failed to encode OAuth form field '\(fieldName)'")
    }
    return encoded
}
