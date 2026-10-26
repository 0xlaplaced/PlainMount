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
        case "write": return "\(disk.name) için yazmayı etkinleştir"
        case "eject": return "\(disk.name) diskini güvenle çıkar"
        default: return "\(disk.name) bağlantısını kes"
        }
    }
    var detail: String {
        switch kind {
        case "write": return "\(disk.id) · \(capacity(disk.size))\nDiskin mevcut bağlantısı kesilip yazılabilir olarak yeniden bağlanacak. Açık dosyaları kapatın. macOS yönetici izni isteyecek. Disk otomatik onarılmaz; hazırda bekletme verisi silinmez."
        case "eject": return "\(disk.parent) üzerindeki tüm bölümler çıkarılacak. Açık dosyaları kapatın. Başarı mesajından sonra kabloyu ayırabilirsiniz."
        default: return "Bu bölümün açık dosyalarını kapatın. Fiziksel diski ayırmak için Güvenle çıkar seçeneğini kullanın."
        }
    }
    var button: String { kind == "write" ? "Yazmayı etkinleştir" : kind == "eject" ? "Diski çıkar" : "Bağlantıyı kes" }
}

@MainActor final class Model: ObservableObject {
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
                let text = kind == "write" ? "\(disk.name): yazılabilir bağlama oluşturuldu." : kind == "eject" ? "\(disk.name) güvenle çıkarıldı. Kabloyu ayırabilirsiniz." : kind == "unmount" ? "\(disk.name) bağlantısı kesildi." : "\(disk.name) salt okunur bağlandı."
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
                accessCheckResult = "\(disk.name) aygıtına erişim doğrulandı. Diskin bağlantısı değiştirilmedi."
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
        if !NSWorkspace.shared.open(url) { error = "Sistem Ayarları → Gizlilik ve Güvenlik → Tam Disk Erişimi bölümünü açın." }
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
                guard current.mountPoint == path else { throw ToolError.message("Diskin bağlama yolu değişti. Listeyi yenileyin.") }
                if !NSWorkspace.shared.open(URL(fileURLWithPath: path)) { throw ToolError.message("Finder bu konumu açamadı.") }
            } catch { showError(error) }
        }
    }

    func record(_ text: String, failed: Bool = false) {
        activities.insert(Activity(message: text, failed: failed), at: 0)
        activities = Array(activities.prefix(30))
    }

    func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "PlainMount-Tani.json"
        panel.title = "Disk tanısını kaydet"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Diagnostic(disks: disks, backend: backend)).write(to: url, options: .atomic)
            record("Tanı dosyası kaydedildi. Disk adlarını ve yerel yolları içerir.")
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
