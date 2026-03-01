import Foundation

func withEnv<T>(_ key: String, _ value: String, perform: () throws -> T) rethrows -> T {
    let previous = ProcessInfo.processInfo.environment[key]
    setenv(key, value, 1)
    defer {
        if let previous {
            setenv(key, previous, 1)
        } else {
            unsetenv(key)
        }
    }
    return try perform()
}

func withEnv<T>(_ key: String, _ value: String, perform: () async throws -> T) async rethrows -> T {
    let previous = ProcessInfo.processInfo.environment[key]
    setenv(key, value, 1)
    defer {
        if let previous {
            setenv(key, previous, 1)
        } else {
            unsetenv(key)
        }
    }
    return try await perform()
}

func makeTempDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-tools-swift-tests")
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

func fileMode(_ url: URL) throws -> UInt16 {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let raw = attributes[.posixPermissions] as? NSNumber
    return UInt16(raw?.uint16Value ?? 0)
}
