import Foundation
import Darwin

public struct BackendStatus: Codable, Sendable {
    public let driver: String?
    public let runtime: String?
    public var ready: Bool { driver != nil && runtime != nil }
    public static func detect(resources: URL? = Bundle.main.resourceURL) -> BackendStatus {
        guard let root = resources?.appendingPathComponent("Backend") else { return .init(driver: nil, runtime: nil) }
        let driver = root.appendingPathComponent("ntfs-3g").path
        let runtime = root.appendingPathComponent("go-nfsv4").path
        let library = root.appendingPathComponent("libfuse-t.dylib").path
        return .init(driver: FileManager.default.isExecutableFile(atPath: driver) && FileManager.default.fileExists(atPath: library) ? driver : nil,
                     runtime: FileManager.default.isExecutableFile(atPath: runtime) ? runtime : nil)
    }
}

public enum WriteMount {
    public static func request(_ disk: DiskVolume) throws {
        try AppBuild.requireInstallation()
        let current = try DiskService.revalidate(disk)
        guard current.isNTFS, current.mediaWritable, !current.writable else {
            throw ToolError.message(L("This drive is not available for writing. Refresh its status and try again."))
        }
        guard BackendStatus.detect().ready else {
            throw ToolError.message(L("Compatible writing components were not found. Download the complete app from Releases."))
        }
        try authorize("--mount-helper", disk: current)
    }

    public static func requestAccessCheck(_ original: DiskVolume) throws {
        try AppBuild.requireInstallation()
        let disk = try DiskService.revalidate(original)
        try authorize("--access-helper", disk: disk)
    }

    public static func accessHelper(_ args: [String]) throws {
        let disk = try validatedDisk(args)
        try DiskAccess.check(disk)
    }

    private static func validatedDisk(_ args: [String]) throws -> DiskVolume {
        guard geteuid() == 0, args.count == 4, DiskService.validDevice(args[0]),
              let encoded = Data(base64Encoded: args[1]), let uid = UInt32(args[2]), uid >= 501,
              let gid = UInt32(args[3]), gid > 0 else { throw ToolError.message(L("Administrator authorization or drive parameters are invalid. Refresh the list and try again.")) }
        let expected = try JSONDecoder().decode(DiskIdentity.self, from: encoded)
        guard let disk = try DiskService.scan().first(where: { $0.id == args[0] }), disk.identity == expected else {
            throw ToolError.message(L("Drive identity could not be verified. No action was taken. Refresh the list and select the drive again."))
        }
        return disk
    }

    public static func requestUnmount(_ original: DiskVolume) throws {
        let current = try DiskService.revalidate(original)
        guard current.mountPoint == DiskService.personalMountPoint(current.id) else {
            throw ToolError.message(L("The PlainMount connection was not found. Refresh the list."))
        }
        // Disk Arbitration handles NFS too, from this already authorized app's user session.
        _ = try Runner.checked("/usr/sbin/diskutil", ["unmount", current.mountPoint!], timeout: 70)
    }

    private static func authorize(_ mode: String, disk: DiskVolume) throws {
        guard let executable = Bundle.main.executableURL else { throw ToolError.message(L("The application location could not be found. Move PlainMount to Applications and reopen it.")) }
        let fingerprint = try JSONEncoder().encode(disk.identity).base64EncodedString()
        let args = [executable.path] + L10n.commandArguments([mode, disk.id, fingerprint, String(getuid()), String(getgid())])
        let command = args.map(Runner.shellQuote).joined(separator: " ")
        let script = "do shell script " + Runner.appleScriptQuote(command) + " with administrator privileges"
        _ = try Runner.checked("/usr/bin/osascript", ["-e", script], timeout: 180)
    }

    public static func unmountHelper(_ args: [String]) throws {
        guard geteuid() == 0, args.count == 4, DiskService.validDevice(args[0]),
              let encoded = Data(base64Encoded: args[1]) else { throw ToolError.message(L("Authorization or drive parameters are invalid. Refresh the list and try again.")) }
        let expected = try JSONDecoder().decode(DiskIdentity.self, from: encoded)
        guard let disk = try DiskService.scan().first(where: { $0.id == args[0] }), disk.identity == expected,
              disk.mountPoint == DiskService.personalMountPoint(disk.id) else { throw ToolError.message(L("Drive identity or mount location changed. Refresh the list and select the drive again.")) }
        let point = DiskService.personalMountPoint(disk.id)
        _ = try Runner.checked("/sbin/umount", [point])
        _ = Darwin.rmdir(point)
    }

    // This entry point is used only for one explicitly requested mount; no persistent helper or sudoers rule.
    public static func helper(_ args: [String]) throws {
        let disk = try validatedDisk(args)
        let uid = UInt32(args[2])!, gid = UInt32(args[3])!
        guard disk.isNTFS, disk.mediaWritable else { throw ToolError.message(L("This drive is not available for NTFS writing. Refresh its status and try again.")) }
        if disk.writable && disk.mounted { return }
        let backend = BackendStatus.detect()
        guard let driver = backend.driver, let runtime = backend.runtime, backend.ready else {
            throw ToolError.message(L("The bundled NTFS driver is missing. Download the complete app from Releases."))
        }
        let point = DiskService.personalMountPoint(disk.id)
        // Access is checked before changing even the mount directory or native connection.
        try DiskAccess.check(disk, allowMountedBusy: true)
        if FileManager.default.fileExists(atPath: point) {
            let rows = String(data: try Runner.checked("/sbin/mount", []), encoding: .utf8) ?? ""
            guard !rows.contains(" on " + point + " ("), Darwin.rmdir(point) == 0 else {
                throw ToolError.message(L("The mount folder is in use: %1$@. Check drive status before trying again.", String(describing: point)))
            }
        }
        let checked = try DiskService.revalidate(disk)
        var driverProcess: RunningCommand?
        try WriteWorkflow.run(initiallyMounted: checked.mounted, checkAccess: { try DiskAccess.check(checked, allowMountedBusy: true) }, unmount: {
            _ = try DiskService.revalidate(checked)
            _ = try Runner.checked("/usr/sbin/diskutil", ["unmount", checked.mountPoint ?? checked.id], timeout: 70)
        }, mount: {
            let latest = try DiskService.revalidate(checked)
            guard !latest.mounted else { throw ToolError.message(L("macOS remounted the drive. The writing driver was not started. Choose Refresh to try again.")) }
            // Mounted EBUSY never authorizes raw access: enforce the real boundary after unmount.
            try DiskAccess.check(latest)
            try FileManager.default.createDirectory(atPath: point, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
            let options = "rw,norecover,no_detach,windows_names,noatime,uid=\(uid),gid=\(gid),umask=022,location=127.0.0.1,backend=nfs"
            // Direct argv: volume labels never become shell commands or driver options.
            let process = try Runner.start("/usr/bin/env", ["FUSE_NFSSRV_PATH=" + runtime, driver, "/dev/" + disk.id, point, "-o", options])
            driverProcess = process
            // Verify mount metadata, without creating any test file on the volume.
            try MountReadiness.wait {
                if let status = try process.poll() { throw ToolError.message(L("The NTFS driver exited before the connection was ready.\n") + (try process.output(status: status)).failureDetails) }
                let rows = try Runner.checked("/sbin/mount", [], timeout: 3)
                return DiskService.personalMountState(String(data: rows, encoding: .utf8) ?? "", point: point) == true
            }
            process.detach()
        }, cleanup: {
            if let process = driverProcess, !process.stop() { throw ToolError.message(L("The NTFS driver could not be confirmed as stopped. A new connection was not started. Check drive status before trying again.")) }
            // Remove only an empty, unmounted directory we created; never recursively delete a volume.
            let rows = String(data: try Runner.checked("/sbin/mount", []), encoding: .utf8) ?? ""
            if rows.contains(" on " + point + " (") {
                _ = try Runner.checked("/usr/sbin/diskutil", ["unmount", point], timeout: 70)
            }
            let after = String(data: try Runner.checked("/sbin/mount", []), encoding: .utf8) ?? ""
            guard !after.contains(" on " + point + " (") else { throw ToolError.message(L("The NTFS connection still exists. Reconnection was not started. Refresh drive status before trying again.")) }
            _ = Darwin.rmdir(point)
        }, restore: {
            let rows = String(data: try Runner.checked("/sbin/mount", []), encoding: .utf8) ?? ""
            guard !rows.contains(" on " + point + " (") else { throw ToolError.message(L("A new NTFS connection exists. Refresh drive status and manage the connection from the app.")) }
            let current = try DiskService.revalidate(disk)
            if !current.mounted { _ = try Runner.checked("/usr/sbin/diskutil", ["mount", "readOnly", disk.id], timeout: 70) }
        })
    }
}
