import SwiftUI
import MountCore

struct Activity: Identifiable {
    let id = UUID()
    let date = Date()
    let message: String
    let failed: Bool
}

struct PendingAction: Identifiable {
    let id = UUID()
    let disk: DiskVolume
    let kind: String
    var title: String {
        switch kind {
        case "write": return L("Enable writing for %1$@", String(describing: disk.name))
        case "eject": return L("Safely eject %1$@", String(describing: disk.name))
        default: return L("Disconnect %1$@", String(describing: disk.name))
        }
    }
    var detail: String {
        switch kind {
        case "write": return L("%1$@ · %2$@\nThe drive will be disconnected and reconnected with write access. Close open files first. macOS will ask for administrator approval. The app will not repair the drive or remove hibernation data.", String(describing: disk.id), String(describing: capacity(disk.size)))
        case "eject": return L("All volumes on %1$@ will be ejected. Close open files first. Disconnect the cable after the success message.", String(describing: disk.parent))
        default: return L("Close open files on this volume. To unplug the physical drive, choose Safely eject.")
        }
    }
    var button: String { kind == "write" ? L("Enable writing") : kind == "eject" ? L("Eject drive") : L("Disconnect") }
}

@MainActor final class Model: ObservableObject {
    @Published var language = L10n.language {
        didSet {
            L10n.save(language)
            L10n.configureProcess(language)
        }
    }
    @Published var disks: [DiskVolume] = []
    @Published var selected: String?
    @Published var page = "disks"
    @Published var scanning = false
    @Published var stale = false
    @Published var busy = false
    @Published var error: String?
    @Published var errorDetails: String?
    @Published var activities: [Activity] = []
    @Published var pending: PendingAction?
    @Published var lastRefresh: Date?
    @Published var onlyNTFS = true
    @Published var accessCheckResult: String?
    @Published var needsDiskAccess = false
    let backend = BackendStatus.detect()
    var selectedDisk: DiskVolume? { disks.first { $0.id == selected } }
    var visible: [DiskVolume] { disks.filter { !onlyNTFS || $0.isNTFS } }
    var ntfsCount: Int { disks.filter(\.isNTFS).count }

    func refresh() async {
        guard !scanning, !busy else { return }
        scanning = true
        defer { scanning = false }
        do {
            let previous = disks
            let values = try await Task.detached(priority: .userInitiated) { try DiskService.scan(previous: previous) }.value
            disks = values
            stale = false
            if !visible.contains(where: { $0.id == selected }) { selected = visible.first?.id }
            lastRefresh = Date()
        } catch { stale = true; showError(error) }
    }

    func action(_ kind: String, disk: DiskVolume) {
        guard !busy, !scanning, !stale else { return }
        if kind != "mount" { pending = PendingAction(disk: disk, kind: kind); return }
        execute(kind, disk: disk)
    }

    func execute(_ kind: String, disk: DiskVolume) {
        guard !busy, !scanning, !stale else { return }
        busy = true
        error = nil
        errorDetails = nil
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    if kind == "write" { try WriteMount.request(disk) }
                    else { try DiskService.perform(kind, on: disk) }
                }.value
                let text = kind == "write" ? L("%1$@: write access enabled.", String(describing: disk.name)) : kind == "eject" ? L("%1$@ safely ejected. You can disconnect the cable.", String(describing: disk.name)) : kind == "unmount" ? L("%1$@ disconnected.", String(describing: disk.name)) : L("%1$@ mounted read-only.", String(describing: disk.name))
                record(text)
            } catch {
                showError(error)
                needsDiskAccess = DiskAccess.isPermissionFailure(error.localizedDescription) || !AppBuild.isInstalled()
                if needsDiskAccess { page = "settings" }
                record("\(disk.name): \(error.localizedDescription)", failed: true)
            }
            busy = false
            await refresh()
        }
    }

    func checkDiskAccess() {
        guard !busy, !scanning, !stale, let disk = selectedDisk else { return }
        busy = true
        error = nil
        errorDetails = nil
        Task {
            do {
                try await Task.detached(priority: .userInitiated) { try WriteMount.requestAccessCheck(disk) }.value
                accessCheckResult = L("Access to %1$@ verified. The drive connection was not changed.", String(describing: disk.name))
                needsDiskAccess = false
                record(accessCheckResult!)
            } catch {
                showError(error)
                accessCheckResult = nil
                needsDiskAccess = DiskAccess.isPermissionFailure(error.localizedDescription)
                record(error.localizedDescription, failed: true)
            }
            busy = false
            await refresh()
        }
    }

    func openDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        if !NSWorkspace.shared.open(url) { error = L("Open System Settings → Privacy & Security → Full Disk Access.") }
    }

    func revealApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    private func showError(_ failure: Error) {
        let details = failure.localizedDescription
        error = DiskAccess.userMessage(details)
        errorDetails = details
    }

    func openFinder(_ disk: DiskVolume) {
        guard !busy, !stale, let path = disk.mountPoint else { return }
        Task {
            do {
                let current = try await Task.detached { try DiskService.revalidate(disk) }.value
                guard current.mountPoint == path else { throw ToolError.message(L("The drive mount location changed. Refresh the list.")) }
                if !NSWorkspace.shared.open(URL(fileURLWithPath: path)) { throw ToolError.message(L("Finder could not open this location. Refresh the drive list and try again.")) }
            } catch { showError(error) }
        }
    }

    func record(_ text: String, failed: Bool = false) {
        activities.insert(Activity(message: text, failed: failed), at: 0)
        activities = Array(activities.prefix(30))
    }

    func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "PlainMount-Diagnostics.json"
        panel.title = L("Save drive diagnostics")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Diagnostic(disks: disks, backend: backend)).write(to: url, options: .atomic)
            record(L("Diagnostics saved. The file includes drive names and local paths."))
        } catch { showError(error) }
    }
}

struct Diagnostic: Encodable {
    let version = AppBuild.version
    let applicationPath = Bundle.main.bundleURL.path
    let installedAtStablePath = AppBuild.isInstalled()
    let system = ProcessInfo.processInfo.operatingSystemVersionString
    let disks: [DiskVolume]
    let backend: BackendStatus
}
