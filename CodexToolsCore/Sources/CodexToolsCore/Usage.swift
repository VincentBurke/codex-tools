import Foundation

private let refreshAllUsageMaxConcurrentRequests = 4
private let usageErrorPreviewLimit = 140

public final class DefaultUsageClient: UsageClient, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func getUsage(for account: StoredAccount) async throws -> UsageInfo {
        switch account.authData {
        case .apiKey:
            return UsageInfo(
                accountID: account.id,
                planType: "api_key",
                primaryUsedPercent: nil,
                primaryWindowMinutes: nil,
                primaryResetsAt: nil,
                secondaryUsedPercent: nil,
                secondaryWindowMinutes: nil,
                secondaryResetsAt: nil,
                hasCredits: nil,
                unlimitedCredits: nil,
                creditsBalance: nil,
                error: "Usage info not available for API key accounts"
            )
        case .chatgpt(_, let accessToken, _, let accountID):
            return try await getUsageWithChatGPTToken(
                accountID: account.id,
                accessToken: accessToken,
                chatGPTAccountID: accountID
            )
        }
    }

    public func refreshAllUsage(accounts: [StoredAccount]) async -> [UsageInfo] {
        await refreshAllUsageConcurrent(
            accounts: accounts,
            maxConcurrentRequests: refreshAllUsageMaxConcurrentRequests
        ) { account in
            do {
                return try await self.getUsage(for: account)
            } catch {
                return UsageInfo.error(accountID: account.id, message: error.localizedDescription)
            }
        }
    }

    private func getUsageWithChatGPTToken(
        accountID: String,
        accessToken: String,
        chatGPTAccountID: String?
    ) async throws -> UsageInfo {
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            throw NSError(domain: "UsageClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid usage endpoint"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("codex-cli/1.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let chatGPTAccountID, !chatGPTAccountID.isEmpty {
            request.setValue(chatGPTAccountID, forHTTPHeaderField: "chatgpt-account-id")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "UsageClient", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid usage response"])
        }

        guard (200...299).contains(http.statusCode) else {
            return UsageInfo.error(
                accountID: accountID,
                message: usageErrorMessage(statusCode: http.statusCode, data: data)
            )
        }

        let payload = try JSONDecoder().decode(RateLimitStatusPayload.self, from: data)
        return convertPayloadToUsageInfo(accountID: accountID, payload: payload)
    }
}

func refreshAllUsageConcurrent(
    accounts: [StoredAccount],
    maxConcurrentRequests: Int,
    fetch: @escaping @Sendable (StoredAccount) async -> UsageInfo
) async -> [UsageInfo] {
    guard !accounts.isEmpty else {
        return []
    }

    let concurrency = max(1, min(maxConcurrentRequests, accounts.count))

    return await withTaskGroup(of: (Int, UsageInfo).self) { group in
        var nextIndex = 0
        for _ in 0..<concurrency {
            let index = nextIndex
            nextIndex += 1
            let account = accounts[index]
            group.addTask {
                (index, await fetch(account))
            }
        }

        var orderedUsage = Array<UsageInfo?>(repeating: nil, count: accounts.count)

        while let result = await group.next() {
            let (index, usage) = result
            orderedUsage[index] = usage

            if nextIndex < accounts.count {
                let index = nextIndex
                nextIndex += 1
                let account = accounts[index]
                group.addTask {
                    (index, await fetch(account))
                }
            }
        }

        return orderedUsage.enumerated().map { index, usage in
            precondition(usage != nil, "Missing usage result at index \(index)")
            return usage!
        }
    }
}

public func convertPayloadToUsageInfo(accountID: String, payload: RateLimitStatusPayload) -> UsageInfo {
    let primary = payload.rateLimit?.primaryWindow
    let secondary = payload.rateLimit?.secondaryWindow

    return UsageInfo(
        accountID: accountID,
        planType: payload.planType,
        primaryUsedPercent: primary?.usedPercent,
        primaryWindowMinutes: primary?.limitWindowSeconds.map { ($0 + 59) / 60 },
        primaryResetsAt: primary?.resetAt,
        secondaryUsedPercent: secondary?.usedPercent,
        secondaryWindowMinutes: secondary?.limitWindowSeconds.map { ($0 + 59) / 60 },
        secondaryResetsAt: secondary?.resetAt,
        hasCredits: payload.credits?.hasCredits,
        unlimitedCredits: payload.credits?.unlimited,
        creditsBalance: payload.credits?.balance,
        error: nil
    )
}

func terminalManageAvailabilityState(forUsageError usageError: String?) -> ManageAccountAvailabilityState? {
    guard let usageError else {
        return nil
    }

    let normalized = usageError
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

    guard !normalized.isEmpty else {
        return nil
    }

    if normalized.contains("payment required") || normalized.contains("payment_required") {
        return .paymentRequired
    }

    if normalized.contains("disabled")
        || normalized.contains("deactivated")
        || normalized.contains("suspended")
        || normalized.contains("inactive account")
        || normalized.contains("revoked") {
        return .disabled
    }

    if normalized == "expired"
        || normalized.contains("session expired")
        || normalized.contains("token expired")
        || normalized.contains("authorization expired")
        || normalized.contains("auth expired")
        || normalized.contains("invalid_grant") {
        return .expired
    }

    return nil
}

private func usageErrorMessage(statusCode: Int, data: Data) -> String {
    if statusCode == 401 {
        return "expired"
    }

    let responseText = extractUsageErrorText(from: data)
    let normalized = responseText.lowercased()

    if statusCode == 402 || normalized.contains("payment_required") || normalized.contains("payment required") {
        return "payment required"
    }

    if normalized.contains("disabled")
        || normalized.contains("deactivated")
        || normalized.contains("suspended")
        || normalized.contains("inactive")
        || normalized.contains("revoked") {
        return "disabled"
    }

    if normalized.contains("token expired")
        || normalized.contains("session expired")
        || normalized.contains("auth expired")
        || normalized.contains("authorization expired")
        || normalized.contains("invalid_grant") {
        return "expired"
    }

    guard !responseText.isEmpty else {
        return "API error: \(statusCode)"
    }

    return "API error: \(statusCode) - \(responseText)"
}

private func extractUsageErrorText(from data: Data) -> String {
    guard !data.isEmpty else {
        return ""
    }

    if let object = try? JSONSerialization.jsonObject(with: data),
       let extracted = extractUsageErrorText(fromJSONObject: object),
       !extracted.isEmpty {
        return String(extracted.prefix(usageErrorPreviewLimit))
    }

    guard let raw = String(data: data, encoding: .utf8) else {
        return ""
    }

    let collapsed = raw
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    return String(collapsed.prefix(usageErrorPreviewLimit))
}

private func extractUsageErrorText(fromJSONObject object: Any) -> String? {
    switch object {
    case let dictionary as [String: Any]:
        let priorityKeys = ["error", "message", "detail", "reason", "code", "type"]
        for key in priorityKeys {
            if let value = dictionary[key],
               let extracted = extractUsageErrorText(fromJSONObject: value),
               !extracted.isEmpty {
                return extracted
            }
        }

        for value in dictionary.values {
            if let extracted = extractUsageErrorText(fromJSONObject: value),
               !extracted.isEmpty {
                return extracted
            }
        }

        return nil
    case let array as [Any]:
        for value in array {
            if let extracted = extractUsageErrorText(fromJSONObject: value),
               !extracted.isEmpty {
                return extracted
            }
        }
        return nil
    case let string as String:
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    case let number as NSNumber:
        return number.stringValue
    default:
        return nil
    }
}
