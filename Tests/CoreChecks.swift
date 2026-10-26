import Foundation
import Darwin

// Standalone checks run on Command Line Tools, without the full Xcode XCTest framework.
@main enum CoreChecks {
    static var passed = 0
    static var failed = 0
    static func check(_ name: String, _ body: () throws -> Bool) {
        do {
            if try body() { passed += 1; print("PASS \(name)") }
            else { failed += 1; print("FAIL \(name)") }
        } catch { failed += 1; print("FAIL \(name): \(error)") }
    }
    static func fixture() -> [String: Any] {
        ["DeviceIdentifier": "disk9s1", "ParentWholeDisk": "disk9", "Internal": false,
         "WholeDisk": false, "FilesystemType": "ntfs", "VolumeName": "SampleDisk's $(command)",
         "VolumeSize": Int64(128_000_000_000), "FreeSpace": Int64(96_000_000_000),
         "MountPoint": "/Volumes/SampleDisk", "WritableMedia": true, "WritableVolume": false,
         "DeviceTreePath": "USB/path", "PartitionMapPartitionOffset": 32256]
    }
    static func main() {
        check("disk identifiers reject shell syntax, paths and trailing newlines") {
            ["disk9", "disk9s1", "disk12s3s1"].allSatisfy { DiskService.validDevice($0) }
            && ["/dev/disk9", "disk9;id", "disk9\n", "disk9s", "disk-1", "$(id)", "disk9s1/../disk0"].allSatisfy { !DiskService.validDevice($0) }
        }
        check("external NTFS parsing preserves names as data") {
            guard let disk = DiskService.parse(fixture(), allowedParents: ["disk9"]) else { return false }
            return disk.isNTFS && !disk.writable && disk.name == "SampleDisk's $(command)" && disk.used == 32_000_000_000 && disk.identity.offset == 32256
        }
        check("internal, unknown and nonphysical devices are rejected") {
            var value = fixture(); value["Internal"] = true
            guard DiskService.parse(value, allowedParents: ["disk9"]) == nil else { return false }
            value.removeValue(forKey: "Internal")
            return DiskService.parse(value, allowedParents: ["disk9"]) == nil && DiskService.parse(fixture(), allowedParents: ["disk0"]) == nil
        }
        check("missing writable flag defaults to read-only") {
            var value = fixture(); value.removeValue(forKey: "WritableVolume")
            return DiskService.parse(value, allowedParents: ["disk9"])?.writable == false
        }
        check("device change invalidates identity; identity survives encoding") {
            guard let original = DiskService.parse(fixture(), allowedParents: ["disk9"]) else { return false }
            var value = fixture(); value["DeviceTreePath"] = "USB/another-port"
            let decoded = try JSONDecoder().decode(DiskIdentity.self, from: JSONEncoder().encode(original.identity))
            return DiskService.parse(value, allowedParents: ["disk9"])?.identity != original.identity
            && decoded == original.identity
        }
        check("mount table uses exact path, filesystem and write status") {
            let point = DiskService.personalMountPoint("disk9s1")
            return DiskService.personalMountState("host:/x on \(point)0 (nfs, local)", point: point) == nil
            && DiskService.personalMountState("/dev/disk9s1 on \(point) (ntfs, local)", point: point) == nil
            && DiskService.personalMountState("host:/x on \(point) (nfs, local)", point: point) == true
            && DiskService.personalMountState("host:/x on \(point) (nfs, read-only, local)", point: point) == false
        }
        check("shell quoting round-trips labels without evaluating them") {
            let value = "a'b \"quoted\" $(printf injected); `printf injected`\nnext"
            let output = try Runner.checked("/bin/sh", ["-c", "printf '%s' " + Runner.shellQuote(value)])
            return String(data: output, encoding: .utf8) == value
        }
        check("process exit status is checked; stderr alone is not failure") {
            do { _ = try Runner.checked("/bin/sh", ["-c", "exit 7"]); return false } catch {}
            return String(data: try Runner.checked("/bin/sh", ["-c", "printf warning >&2; printf ok"]), encoding: .utf8) == "ok"
        }
        check("invalid helper cannot start a disk operation") {
            do { try WriteMount.helper(["disk0;id", "", "0", "0"]); return false } catch { return true }
        }
        check("missing bundled backend is unavailable") {
            !BackendStatus.detect(resources: URL(fileURLWithPath: "/nonexistent")).ready
        }
        check("invalid unmount helper fails without touching a disk") {
            do { try WriteMount.unmountHelper(["disk9;id", "", "501", "20"]); return false } catch { return true }
        }
        check("process timeout returns a failure instead of hanging") {
            do { _ = try Runner.run("/bin/sleep", ["2"], timeout: 0.05); return false } catch { return true }
        }
        check("background process execution works without a main run loop") {
            let done = DispatchSemaphore(value: 0)
            let state = NSLock()
            var succeeded = false
            DispatchQueue.global().async {
                let result = try? Runner.checked("/usr/bin/printf", ["background"])
                state.lock(); succeeded = result == Data("background".utf8); state.unlock()
                done.signal()
            }
            guard done.wait(timeout: .now() + 5) == .success else { return false }
            state.lock(); defer { state.unlock() }; return succeeded
        }
        check("binary and XML property lists parse without locale dependence") {
            let value: [String: Any] = ["WholeDisks": ["disk9"], "Size": Int64(128_000_000_000)]
            for format: PropertyListSerialization.PropertyListFormat in [.xml, .binary] {
                let parsed = try DiskService.plist(PropertyListSerialization.data(fromPropertyList: value, format: format, options: 0))
                if parsed["WholeDisks"] as? [String] != ["disk9"] { return false }
            }
            return true
        }
        check("unknown disk action fails before executing any command") {
            // Device validation itself rejects injection before diskutil can run.
            do { _ = try DiskService.info("disk9; echo injected"); return false } catch { return true }
        }
        check("permission denial happens before unmount or driver launch") {
            var calls: [String] = []
            do {
                try WriteWorkflow.run(initiallyMounted: true, checkAccess: { calls.append("access"); throw ToolError.message("Operation not permitted") },
                    unmount: { calls.append("unmount") }, mount: { calls.append("driver") }, cleanup: { calls.append("cleanup") }, restore: { calls.append("restore") })
                return false
            } catch { return calls == ["access"] && DiskAccess.isPermissionFailure(error.localizedDescription) }
        }
        check("failed unmount never starts driver or recovery mount") {
            var calls: [String] = []
            do {
                try WriteWorkflow.run(initiallyMounted: true, checkAccess: { calls.append("access") },
                    unmount: { calls.append("unmount"); throw ToolError.message("Volume failed to unmount") },
                    mount: { calls.append("driver") }, restore: { calls.append("restore") })
                return false
            } catch { return calls == ["access", "unmount"] && error.localizedDescription.contains("Yazma sürücüsü başlatılmadı") }
        }
        check("driver failure cleans up and restores an originally mounted disk") {
            var calls: [String] = []
            do {
                try WriteWorkflow.run(initiallyMounted: true, checkAccess: { calls.append("access") }, unmount: { calls.append("unmount") },
                    mount: { calls.append("driver"); throw ToolError.message("driver failure") }, cleanup: { calls.append("cleanup") }, restore: { calls.append("restore") })
                return false
            } catch { return calls == ["access", "unmount", "driver", "cleanup", "restore"] && error.localizedDescription.contains("driver failure") }
        }
        check("failed write preserves an originally unmounted state") {
            var calls: [String] = []
            do {
                try WriteWorkflow.run(initiallyMounted: false, checkAccess: { calls.append("access") }, unmount: { calls.append("unmount") },
                    mount: { calls.append("driver"); throw ToolError.message("failed") }, cleanup: { calls.append("cleanup") }, restore: { calls.append("restore") })
                return false
            } catch { return calls == ["access", "driver", "cleanup"] }
        }
        check("recovery failure retains the original and restoration errors") {
            do {
                try WriteWorkflow.run(initiallyMounted: true, checkAccess: {}, unmount: {},
                    mount: { throw ToolError.message("first cause") }, restore: { throw ToolError.message("restore cause") })
                return false
            } catch { return error.localizedDescription.contains("first cause") && error.localizedDescription.contains("restore cause") }
        }
        check("stdout, stderr and status survive command failure") {
            do { _ = try Runner.checked("/bin/sh", ["-c", "printf stdout-detail; printf stderr-detail >&2; exit 7"]); return false }
            catch { return error.localizedDescription.contains("stdout-detail") && error.localizedDescription.contains("stderr-detail") && error.localizedDescription.contains("7") }
        }
        check("missing FSKit VolumeKind falls back only to known NTFS metadata") {
            var value = fixture(); value["FilesystemType"] = ""
            let completed = DiskService.completeMetadata(value, record: ["Content": "Windows_NTFS"])
            let unknown = DiskService.completeMetadata(value, record: ["Content": "Microsoft_Basic_Data"])
            return DiskService.parse(completed, allowedParents: ["disk9"])?.isNTFS == true && DiskService.parse(unknown, allowedParents: ["disk9"]) == nil
        }
        check("mounted disk cannot disappear from a transiently empty snapshot") {
            let disk = DiskService.parse(fixture(), allowedParents: ["disk9"])!
            do { try DiskService.validateSnapshot(previous: [disk], current: [], mounts: "/dev/disk9s1 on /Volumes/SampleDisk (ntfs, read-only, fskit)"); return false }
            catch { return error.localizedDescription.contains("Son doğrulanan liste korunuyor") }
        }
        check("physical removal can clear the previous disk snapshot") {
            let disk = DiskService.parse(fixture(), allowedParents: ["disk9"])!
            try DiskService.validateSnapshot(previous: [disk], current: [], mounts: "/dev/disk9s10 on /Volumes/Other (ntfs, read-only)")
            return true
        }
        check("a personal NFS mount also prevents a false empty snapshot") {
            let disk = DiskService.parse(fixture(), allowedParents: ["disk9"])!
            do { try DiskService.validateSnapshot(previous: [disk], current: [], mounts: "127.0.0.1:/x on /Volumes/PlainMount-disk9s1 (nfs, local)"); return false }
            catch { return true }
        }
        check("FDA instructions identify the stable app, never a temporary build") {
            AppBuild.isInstalled(at: "/Applications/PlainMount.app")
            && !AppBuild.isInstalled(at: "/private/tmp/PlainMount.app")
            && !AppBuild.isInstalled(at: "/Applications/PlainMount.app-other")
        }
        check("EPERM is classified ahead of misleading driver hibernation text") {
            let detail = "Error opening /dev/disk9s1: Operation not permitted. The NTFS partition is in an unsafe state. Please shutdown Windows."
            let message = DiskAccess.userMessage(detail)
            return message.contains("macOS") && !message.contains("Windows") && !message.contains("hibernation")
        }
        check("a generic mount failure does not diagnose a Windows problem") {
            !DiskAccess.userMessage("NTFS yazma bağlantısı kurulamadı. Driver error 12").contains("Windows")
        }
        check("invalid access helper does not open a device") {
            do { try WriteMount.accessHelper(["disk9;id", "", "0", "0"]); return false } catch { return true }
        }
        check("asynchronous mount readiness is retried instead of immediately failing") {
            var clock = 0.0, calls = 0
            try MountReadiness.wait(timeout: 5, now: { clock }, pause: { clock += 1 }) { calls += 1; return calls == 4 }
            return calls == 4 && clock == 3
        }
        check("mount readiness stops after its bounded deadline") {
            var clock = 0.0, calls = 0
            do {
                try MountReadiness.wait(timeout: 3, now: { clock }, pause: { clock += 1 }) { calls += 1; return false }
                return false
            } catch { return calls == 4 && clock == 3 }
        }
        check("unsafe cleanup prevents a conflicting recovery mount") {
            var restored = false
            do {
                try WriteWorkflow.run(initiallyMounted: true, checkAccess: {}, unmount: {}, mount: { throw ToolError.message("startup timeout") },
                    cleanup: { throw ToolError.message("process still running") }, restore: { restored = true })
                return false
            } catch { return !restored && error.localizedDescription.contains("yeniden bağlama başlatılmadı") }
        }
        check("only the owned long-lived child is stopped and reaped") {
            let child = try Runner.start("/bin/sleep", ["5"])
            guard try child.poll() == nil else { return false }
            let stopped = child.stop()
            let finalStatus = try child.poll()
            return stopped && finalStatus != nil
        }
        check("child startup failure exposes both output streams") {
            let child = try Runner.start("/bin/sh", ["-c", "printf driver-out; printf driver-err >&2; exit 12"])
            var status: Int32?
            try MountReadiness.wait(timeout: 3) { status = try child.poll(); return status != nil }
            let details = try child.output().failureDetails
            return status == 12 && details.contains("driver-out") && details.contains("driver-err")
        }
        check("mounted EBUSY is distinct from a permission denial") {
            DiskAccess.permitsMountedBusy(code: EBUSY, mounted: true)
            && !DiskAccess.permitsMountedBusy(code: EBUSY, mounted: false)
            && !DiskAccess.permitsMountedBusy(code: EPERM, mounted: true)
            && !DiskAccess.permitsMountedBusy(code: EACCES, mounted: true)
        }
        check("a denied strict post-unmount check cannot launch the driver") {
            var calls: [String] = []
            do {
                try WriteWorkflow.run(initiallyMounted: true, checkAccess: { calls.append("mounted-busy") },
                    unmount: { calls.append("unmount") }, mount: {
                        calls.append("strict-access")
                        throw ToolError.message("Operation not permitted")
                    }, cleanup: { calls.append("cleanup") }, restore: { calls.append("readonly") })
                return false
            } catch { return calls == ["mounted-busy", "unmount", "strict-access", "cleanup", "readonly"] && DiskAccess.isPermissionFailure(error.localizedDescription) }
        }
        print("\(passed)/\(passed + failed) checks passed")
        exit(failed == 0 ? 0 : 1)
    }
}
