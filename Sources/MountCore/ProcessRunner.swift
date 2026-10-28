import Foundation
import Darwin

public enum ToolError: LocalizedError {
    case message(String)
    public var errorDescription: String? { switch self { case .message(let text): return text } }
}

public struct CommandResult {
    public let status: Int32
    public let output: Data
    public let error: String
    public var text: String { String(data: output, encoding: .utf8) ?? "" }
    public var failureDetails: String {
        var parts = [L("Exit status: %1$@", String(describing: status))]
        let stdout = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = error.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stdout.isEmpty { parts.append(L("Output:\n") + String(stdout.prefix(4000))) }
        if !stderr.isEmpty { parts.append(L("Error:\n") + String(stderr.prefix(4000))) }
        return parts.joined(separator: "\n")
    }
}

// Own one exact child PID. Never search/kill processes by name.
public final class RunningCommand {
    public let pid: pid_t
    private let folder: URL
    private let stdoutURL: URL
    private let stderrURL: URL
    private let stdoutHandle: FileHandle
    private let stderrHandle: FileHandle
    private var exitStatus: Int32?
    private var detached = false
    private var reapScheduled = false

    init(path: String, args: [String]) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("plainmount-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let outURL = folder.appendingPathComponent("stdout"), errURL = folder.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        FileManager.default.createFile(atPath: errURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let out = try FileHandle(forWritingTo: outURL), err = try FileHandle(forWritingTo: errURL)
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, out.fileDescriptor, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, err.fileDescriptor, STDERR_FILENO)
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        var words = ([path] + args).map { strdup($0) } + [nil]
        var environment = ProcessInfo.processInfo.environment.map { strdup($0.key + "=" + $0.value) } + [nil]
        defer {
            for word in words { if let word { free(word) } }
            for word in environment { if let word { free(word) } }
        }
        var child: pid_t = 0
        let code = words.withUnsafeMutableBufferPointer { arguments in
            environment.withUnsafeMutableBufferPointer { variables in
                posix_spawn(&child, path, &actions, nil, arguments.baseAddress!, variables.baseAddress!)
            }
        }
        guard code == 0 else {
            try? out.close(); try? err.close(); try? FileManager.default.removeItem(at: folder)
            throw ToolError.message(L("Could not start the process: %1$@", String(describing: String(cString: strerror(code)))))
        }
        pid = child; self.folder = folder; stdoutURL = outURL; stderrURL = errURL
        stdoutHandle = out; stderrHandle = err
    }

    public func poll() throws -> Int32? {
        if let exitStatus { return exitStatus }
        guard !reapScheduled else { throw ToolError.message(L("Process lifecycle has been handed off.")) }
        var raw: Int32 = 0
        let result = waitpid(pid, &raw, WNOHANG)
        if result == 0 || (result == -1 && errno == EINTR) { return nil }
        guard result == pid else { throw ToolError.message(L("The process status could not be verified. Refresh drive status before trying again.")) }
        let decoded = (raw & 0x7f) == 0 ? (raw >> 8) & 0xff : 128 + (raw & 0x7f)
        exitStatus = decoded
        return decoded
    }

    public func output(status: Int32? = nil) throws -> CommandResult {
        CommandResult(status: status ?? exitStatus ?? -1, output: try Data(contentsOf: stdoutURL),
                      error: String(data: try Data(contentsOf: stderrURL), encoding: .utf8) ?? "")
    }

    @discardableResult public func stop() -> Bool {
        if (try? poll()) != nil { return true }
        guard !reapScheduled, !detached else { return false }
        kill(pid, SIGTERM)
        var deadline = ProcessInfo.processInfo.systemUptime + 2
        while ProcessInfo.processInfo.systemUptime < deadline {
            if (try? poll()) != nil { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        kill(pid, SIGKILL)
        deadline = ProcessInfo.processInfo.systemUptime + 1
        while ProcessInfo.processInfo.systemUptime < deadline {
            if (try? poll()) != nil { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        scheduleReap()
        return false
    }

    public func detach() { detached = true; scheduleReap() }

    private func scheduleReap() {
        guard exitStatus == nil, !reapScheduled else { return }
        reapScheduled = true
        let child = pid
        DispatchQueue.global().async { var raw: Int32 = 0; _ = waitpid(child, &raw, 0) }
    }

    deinit {
        if !detached, exitStatus == nil, !reapScheduled { kill(pid, SIGKILL); scheduleReap() }
        try? stdoutHandle.close(); try? stderrHandle.close()
        try? FileManager.default.removeItem(at: folder)
    }
}

public enum Runner {
    public static func start(_ path: String, _ args: [String]) throws -> RunningCommand { try RunningCommand(path: path, args: args) }
    public static func run(_ path: String, _ args: [String], timeout: TimeInterval = 25) throws -> CommandResult {
        let command = try start(path, args)
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while true {
            if let status = try command.poll() { return try command.output(status: status) }
            if ProcessInfo.processInfo.systemUptime >= deadline {
                let stopped = command.stop()
                let details = (try? command.output().failureDetails) ?? ""
                throw ToolError.message(L("The operation timed out. %1$@\n%2$@", String(describing: stopped ? L("The started process was stopped.") : L("The process has not been confirmed as stopped. Do not start another drive operation.")), String(describing: details)))
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }
    public static func checked(_ path: String, _ args: [String], timeout: TimeInterval = 25) throws -> Data {
        let result = try run(path, args, timeout: timeout)
        guard result.status == 0 else { throw ToolError.message(URL(fileURLWithPath: path).lastPathComponent + ": " + result.failureDetails) }
        return result.output
    }
    public static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    public static func appleScriptQuote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") + "\""
    }
}
