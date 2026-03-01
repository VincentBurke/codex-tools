@testable import CodexToolsCore
import XCTest

final class ProcessServiceTests: XCTestCase {
    func testCheckCodexProcessesThrowsWhenPSFailsToLaunch() {
        let service = DefaultProcessService { _, _ in
            throw NSError(domain: "ProcessServiceTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "ps launch failed"])
        }

        XCTAssertThrowsError(try service.checkCodexProcesses())
    }

    func testCheckCodexProcessesThrowsOnNonZeroPSStatus() {
        let service = DefaultProcessService { _, _ in
            CommandOutput(status: 1, stdout: "", stderr: "permission denied")
        }

        XCTAssertThrowsError(try service.checkCodexProcesses())
    }

    func testCheckCodexProcessesUsesSinglePSOutputAndDedupes() throws {
        let output = """
          100 /usr/local/bin/codex
          100 /usr/local/bin/codex
          101 codex-tools
          102 codex --sandbox workspace-write
          103 /Applications/CodexTools
          104 /opt/homebrew/bin/node /opt/homebrew/lib/node_modules/@openai/codex/bin/codex.js
          105 /bin/zsh -lc cd /Users/vincent/projects/codex-tools && swift test
        """
        let service = DefaultProcessService { _, args in
            XCTAssertEqual(args, ["-axo", "pid=,command="])
            return CommandOutput(status: 0, stdout: output, stderr: "")
        }

        let info = try service.checkCodexProcesses()
        XCTAssertEqual(info.count, 3)
        XCTAssertEqual(info.pids, [100, 102, 104])
        XCTAssertFalse(info.canSwitch)
    }
}
