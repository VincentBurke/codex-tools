import Darwin
import Foundation

public final class DefaultProcessService: ProcessInspector, ProcessTerminator, @unchecked Sendable {
    private let commandRunner: @Sendable (String, [String]) throws -> CommandOutput

    public init() {
        self.commandRunner = runCommand
    }

    init(commandRunner: @escaping @Sendable (String, [String]) throws -> CommandOutput) {
        self.commandRunner = commandRunner
    }

    public func checkCodexProcesses() throws -> CodexProcessInfo {
        let pids = try findCodexProcesses()
        return CodexProcessInfo(count: pids.count, canSwitch: pids.isEmpty, pids: pids)
    }

    public func terminateCodexProcesses() throws -> Int {
        let rootPIDs = try findCodexProcesses()
        if rootPIDs.isEmpty {
            return 0
        }

        let processTreePIDs = try collectProcessTreePIDs(rootPIDs: rootPIDs)
        for pid in processTreePIDs {
            try forceTerminatePID(pid)
        }

        waitForProcessExit(pids: processTreePIDs, timeoutSeconds: 2)

        let stubbornPIDs = processTreePIDs.filter { isProcessAlive($0) }
        if !stubbornPIDs.isEmpty {
            let joined = stubbornPIDs.map(String.init).joined(separator: ", ")
            throw NSError(
                domain: "ProcessService",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Failed to force terminate codex processes: \(joined)"]
            )
        }

        return rootPIDs.count
    }

    private func findCodexProcesses() throws -> [Int32] {
        let output = try commandRunner("/bin/ps", ["-axo", "pid=,command="])
        guard output.status == 0 else {
            throw NSError(
                domain: "ProcessService",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "ps -axo pid=,command= failed: \(output.stderr)"]
            )
        }

        let ownPID = Int32(getpid())
        let lines = output.stdout.split(separator: "\n")
        var pidSet = Set<Int32>()

        for line in lines {
            let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard parts.count == 2, let pid = Int32(parts[0]) else {
                continue
            }

            let commandLine = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard isCodexProcessCommandLine(commandLine), pid != ownPID else {
                continue
            }

            pidSet.insert(pid)
        }

        return pidSet.sorted()
    }

    private func isCodexProcessCommandLine(_ commandLine: String) -> Bool {
        let normalized = commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return false
        }

        let lower = normalized.lowercased()

        if lower.contains("codex-tools")
            || lower.contains("codex_tools")
            || lower.contains("codex-tools-rust")
            || lower.contains("codextools")
        {
            return false
        }

        // Use full command-line matching so wrapper launches (for example Node/Bun scripts)
        // are still recognized as codex sessions.
        for token in lower.split(whereSeparator: { $0.isWhitespace }) {
            if token == "codex" || token.hasSuffix("/codex") {
                return true
            }
            if token.hasPrefix("codex-") || token.contains("/codex") {
                return true
            }
        }

        return false
    }

    private func collectProcessTreePIDs(rootPIDs: [Int32]) throws -> [Int32] {
        let output = try commandRunner("/bin/ps", ["-eo", "pid=,ppid="])
        guard output.status == 0 else {
            throw NSError(
                domain: "ProcessService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "ps -eo pid=,ppid= failed: \(output.stderr)"]
            )
        }

        var childrenByParent: [Int32: [Int32]] = [:]
        for line in output.stdout.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0.isWhitespace })
            guard parts.count >= 2,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1])
            else {
                continue
            }
            childrenByParent[ppid, default: []].append(pid)
        }

        var seen = Set(rootPIDs)
        var stack = rootPIDs

        while let parent = stack.popLast() {
            for child in childrenByParent[parent] ?? [] where !seen.contains(child) {
                seen.insert(child)
                stack.append(child)
            }
        }

        return seen.sorted()
    }
}

private func waitForProcessExit(pids: [Int32], timeoutSeconds: TimeInterval) {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
        if pids.allSatisfy({ !isProcessAlive($0) }) {
            return
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
}

private func isProcessAlive(_ pid: Int32) -> Bool {
    if kill(pid, 0) == 0 {
        return true
    }
    return errno == EPERM
}

private func forceTerminatePID(_ pid: Int32) throws {
    try sendSignal(pid: pid, signal: SIGKILL)
}

private func sendSignal(pid: Int32, signal: Int32) throws {
    if kill(pid, signal) == 0 {
        return
    }

    if errno == ESRCH {
        return
    }

    throw NSError(
        domain: "ProcessService",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "kill(\(signal)) failed for pid \(pid)"]
    )
}

struct CommandOutput {
    let status: Int32
    let stdout: String
    let stderr: String
}

private func runCommand(_ command: String, _ args: [String]) throws -> CommandOutput {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: command)
    process.arguments = args

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    process.waitUntilExit()

    let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    return CommandOutput(status: process.terminationStatus, stdout: stdout, stderr: stderr)
}
