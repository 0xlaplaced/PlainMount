import Foundation
import Darwin

public enum AppBuild {
    public static let version = "1.0.5"
    public static let installationPath = "/Applications/PlainMount.app"

    public static func isInstalled(at path: String = Bundle.main.bundleURL.path) -> Bool {
        URL(fileURLWithPath: path).standardizedFileURL.path == installationPath
    }

    public static func requireInstallation() throws {
        guard isInstalled() else {
            throw ToolError.message(L("Before writing, move the app to Applications: %1$@. Grant Full Disk Access to the app at this location, then reopen it.", String(describing: installationPath)))
        }
    }
}

public enum DiskAccess {
    public static func permitsMountedBusy(code: Int32, mounted: Bool) -> Bool { code == EBUSY && mounted }
    public static func userMessage(_ details: String) -> String {
        if isPermissionFailure(details) { return L("macOS blocked drive access. Follow the macOS drive access steps in Settings, then reopen the app.") }
        if L10n.contains(details, key: "The current drive connection could not be disconnected") { return L("The current drive connection could not be disconnected. The writing driver was not started. Check the technical details and try again.") }
        if L10n.contains(details, key: "The NTFS writing connection could not be established") { return L("The NTFS writing connection could not be established. Check the technical details for the cause and recovery result.") }
        return details
    }
    public static func isPermissionFailure(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("operation not permitted") || lower.contains("permission denied") || lower.contains("ntfs_access_denied")
    }

    public static func permissionMessage(path: String, code: Int32) -> String {
        L("NTFS_ACCESS_DENIED: macOS blocked drive access (%1$@, errno %2$@: %3$@).\nIn System Settings → Privacy & Security → Full Disk Access, add and enable PlainMount from Applications. Quit the app completely and reopen it. The drive connection was not changed.", String(describing: path), String(describing: code), String(describing: String(cString: strerror(code))))
    }

    public static func check(_ disk: DiskVolume, allowMountedBusy: Bool = false) throws {
        guard geteuid() == 0, DiskService.validDevice(disk.id) else { throw ToolError.message(L("Administrator approval is required to check drive access. Try again and approve the macOS prompt.")) }
        let path = "/dev/" + disk.id
        // Open read-only solely to test the actual TCC/DAC boundary. No bytes are read or written.
        let descriptor = Darwin.open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            let code = errno
            if code == EPERM || code == EACCES { throw ToolError.message(permissionMessage(path: path, code: code)) }
            // FSKit may hold even read-only raw opens exclusively while mounted.
            // This is not proof of FDA. A second strict check is required after safe unmount.
            if allowMountedBusy && permitsMountedBusy(code: code, mounted: disk.mounted) { return }
            if permitsMountedBusy(code: code, mounted: disk.mounted) {
                throw ToolError.message(L("Drive access could not be checked while the device is mounted (Resource busy). This is not a permission denial. Writing will check access again after a safe disconnect. The drive connection was not changed."))
            }
            throw ToolError.message(L("Drive access could not be verified (%1$@, errno %2$@: %3$@). The drive connection was not changed. Check the connection and try again.", String(describing: path), String(describing: code), String(describing: String(cString: strerror(code)))))
        }
        Darwin.close(descriptor)
    }
}

public enum WriteWorkflow {
    // Ordering is an invariant: denied access must not unmount a user's disk or start the driver.
    public static func run(initiallyMounted: Bool, checkAccess: () throws -> Void,
                           unmount: () throws -> Void, mount: () throws -> Void,
                           cleanup: () throws -> Void = {},
                           restore: () throws -> Void) throws {
        try checkAccess()
        if initiallyMounted {
            do { try unmount() }
            catch { throw ToolError.message(L("The current drive connection could not be disconnected. The writing driver was not started.\n") + error.localizedDescription) }
        }
        do { try mount() }
        catch {
            let cause = error.localizedDescription
            var recovery = ""
            var cleaned = true
            do { try cleanup() } catch { cleaned = false; recovery += L("\nThe started driver or connection could not be cleaned up: ") + error.localizedDescription }
            if initiallyMounted && cleaned {
                do { try restore(); recovery += L("\nThe previous connection was preserved or read-only access was restored.") }
                catch { recovery += L("\nRead-only access could not be restored:\n") + error.localizedDescription }
            }
            if !cleaned { recovery += L("\nReconnection was not started because safe cleanup could not be verified.") }
            let guidance = DiskAccess.isPermissionFailure(cause)
                ? L("macOS blocked drive access. Follow the Full Disk Access steps in Settings.")
                : L("The NTFS writing connection could not be established.")
            throw ToolError.message(guidance + "\n" + cause + recovery)
        }
    }
}
