import Foundation

public enum MountReadiness {
    public static func wait(timeout: TimeInterval = 15,
                            now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                            pause: () -> Void = { Thread.sleep(forTimeInterval: 0.1) },
                            check: () throws -> Bool) throws {
        let deadline = now() + timeout
        while true {
            if try check() { return }
            guard now() < deadline else { throw ToolError.message("NTFS bağlantısı beklenen sürede hazır olmadı.") }
            pause()
        }
    }
}
