import Foundation

public enum CodexPaths {
    private static func resolvedHomeDirectory() throws -> URL {
        guard let home = FileManager.default.homeDirectoryForCurrentUser.path.removingPercentEncoding else {
            throw NSError(
                domain: "CodexPaths",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not resolve home directory"]
            )
        }
        return URL(fileURLWithPath: home, isDirectory: true)
    }

    public static func configDirectory() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_TOOLS_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        return try resolvedHomeDirectory().appendingPathComponent(".codex-tools", isDirectory: true)
    }

    public static func legacyConfigDirectory() throws -> URL {
        if let legacyOverride = ProcessInfo.processInfo.environment["CODEX_SWITCHER_HOME"], !legacyOverride.isEmpty {
            return URL(fileURLWithPath: legacyOverride, isDirectory: true)
        }

        return try resolvedHomeDirectory().appendingPathComponent(".codex-switcher", isDirectory: true)
    }

    public static func accountsFile() throws -> URL {
        try configDirectory().appendingPathComponent("accounts.json", isDirectory: false)
    }

    public static func legacyAccountsFile() throws -> URL {
        try legacyConfigDirectory().appendingPathComponent("accounts.json", isDirectory: false)
    }

    public static func uiFile() throws -> URL {
        try configDirectory().appendingPathComponent("ui.json", isDirectory: false)
    }

    public static func legacyUIFile() throws -> URL {
        try legacyConfigDirectory().appendingPathComponent("ui.json", isDirectory: false)
    }

    public static func codexHome() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        return try resolvedHomeDirectory().appendingPathComponent(".codex", isDirectory: true)
    }

    public static func codexAuthFile() throws -> URL {
        try codexHome().appendingPathComponent("auth.json", isDirectory: false)
    }
}

@discardableResult
func ensureParentDirectory(for fileURL: URL) throws -> URL {
    let parent = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    return parent
}

func setSecurePermissions(fileURL: URL) throws {
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
}
