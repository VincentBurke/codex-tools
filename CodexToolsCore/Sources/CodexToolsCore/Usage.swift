import Foundation

private let refreshAllUsageMaxConcurrentRequests = 4

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
            return UsageInfo.error(accountID: accountID, message: "API error: \(http.statusCode)")
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
