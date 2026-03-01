import Foundation

public enum CodexPaths {
    public static func configDirectory() throws -> URL {
        try resolveDirectory(envKey: "CODEX_TOOLS_HOME", fallbackSubdirectory: ".codex-tools")
    }

    public static func accountsFile() throws -> URL {
        try configDirectory().appendingPathComponent("accounts.json", isDirectory: false)
    }

    public static func codexHome() throws -> URL {
        try resolveDirectory(envKey: "CODEX_HOME", fallbackSubdirectory: ".codex")
    }

    public static func codexAuthFile() throws -> URL {
        try codexHome().appendingPathComponent("auth.json", isDirectory: false)
    }

    private static func resolveDirectory(envKey: String, fallbackSubdirectory: String) throws -> URL {
        if let override = ProcessInfo.processInfo.environment[envKey], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        guard let home = FileManager.default.homeDirectoryForCurrentUser.path.removingPercentEncoding else {
            throw NSError(
                domain: "CodexPaths",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not resolve home directory"]
            )
        }

        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(fallbackSubdirectory, isDirectory: true)
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
