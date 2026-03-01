import Foundation
import XCTest

private func setTemporaryEnvironmentValue(_ key: String, _ value: String) -> () -> Void {
    let previous = ProcessInfo.processInfo.environment[key]
    setenv(key, value, 1)

    return {
        if let previous {
            setenv(key, previous, 1)
        } else {
            unsetenv(key)
        }
    }
}

func withEnv<T>(_ key: String, _ value: String, perform: () throws -> T) rethrows -> T {
    let restore = setTemporaryEnvironmentValue(key, value)
    defer {
        restore()
    }
    return try perform()
}

func withEnv<T>(_ key: String, _ value: String, perform: () async throws -> T) async rethrows -> T {
    let restore = setTemporaryEnvironmentValue(key, value)
    defer {
        restore()
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

extension Optional {
    func unwrap(file: StaticString = #filePath, line: UInt = #line) throws -> Wrapped {
        guard let value = self else {
            XCTFail("Unexpected nil", file: file, line: line)
            throw NSError(domain: "Test", code: 1)
        }
        return value
    }
}
