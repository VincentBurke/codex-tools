import CodexToolsCore
import Foundation
import XCTest

final class PathsTests: XCTestCase {
    func testConfigDirectoryUsesCodexToolsHomeOverride() throws {
        let temp = try makeTempDirectory()
        try withEnv("CODEX_TOOLS_HOME", temp.path) {
            XCTAssertEqual(
                try CodexPaths.configDirectory().standardizedFileURL,
                temp.standardizedFileURL
            )
        }
    }

    func testCodexHomeUsesCodexHomeOverride() throws {
        let temp = try makeTempDirectory()
        try withEnv("CODEX_HOME", temp.path) {
            XCTAssertEqual(
                try CodexPaths.codexHome().standardizedFileURL,
                temp.standardizedFileURL
            )
        }
    }

    func testPathDirectoriesFallBackToHomeWhenOverridesAreEmpty() throws {
        try withEnv("CODEX_TOOLS_HOME", "") {
            try withEnv("CODEX_HOME", "") {
                let home = FileManager.default.homeDirectoryForCurrentUser
                let expectedConfig = home.appendingPathComponent(".codex-tools", isDirectory: true)
                let expectedCodex = home.appendingPathComponent(".codex", isDirectory: true)

                XCTAssertEqual(
                    try CodexPaths.configDirectory().standardizedFileURL,
                    expectedConfig.standardizedFileURL
                )
                XCTAssertEqual(
                    try CodexPaths.codexHome().standardizedFileURL,
                    expectedCodex.standardizedFileURL
                )
            }
        }
    }
}
