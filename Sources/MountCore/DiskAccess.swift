import Foundation
import Darwin

public enum AppBuild {
    public static let version = "1.0.4"
    public static let installationPath = "/Applications/PlainMount.app"

    public static func isInstalled(at path: String = Bundle.main.bundleURL.path) -> Bool {
        URL(fileURLWithPath: path).standardizedFileURL.path == installationPath
    }

    public static func requireInstallation() throws {
        guard isInstalled() else {
            throw ToolError.message("Yazma için uygulamayı önce Uygulamalar klasörüne taşıyın: \(installationPath). Tam Disk Erişimi iznini bu sabit konumdaki uygulamaya verin ve uygulamayı yeniden açın.")
        }
    }
}

public enum DiskAccess {
    public static func permitsMountedBusy(code: Int32, mounted: Bool) -> Bool { code == EBUSY && mounted }
    public static func userMessage(_ details: String) -> String {
        if isPermissionFailure(details) { return "macOS disk erişimini engelledi. Ayarlar bölümündeki macOS disk erişimi adımlarını izleyin, ardından uygulamayı yeniden açın." }
        if details.contains("Mevcut disk bağlantısı kesilemedi") { return "Mevcut disk bağlantısı kesilemedi. Yazma sürücüsü başlatılmadı. Teknik ayrıntıları inceleyip tekrar deneyin." }
        if details.contains("NTFS yazma bağlantısı kurulamadı") { return "NTFS yazma bağlantısı kurulamadı. Nedenini ve geri bağlama sonucunu teknik ayrıntılardan inceleyebilirsiniz." }
        return details
    }
    public static func isPermissionFailure(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("operation not permitted") || lower.contains("permission denied") || lower.contains("ntfs_access_denied")
    }

    public static func permissionMessage(path: String, code: Int32) -> String {
        "NTFS_ACCESS_DENIED: macOS disk erişimini engelledi (\(path), errno \(code): \(String(cString: strerror(code)))).\nSistem Ayarları → Gizlilik ve Güvenlik → Tam Disk Erişimi bölümünde Uygulamalar klasöründeki PlainMount uygulamasını ekleyip etkinleştirin. Ardından uygulamayı tamamen kapatıp yeniden açın. Diskin bağlantısı değiştirilmedi."
    }

    public static func check(_ disk: DiskVolume, allowMountedBusy: Bool = false) throws {
        guard geteuid() == 0, DiskService.validDevice(disk.id) else { throw ToolError.message("Disk erişimi denetimi için yönetici yetkisi gerekli.") }
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
                throw ToolError.message("Disk bağlı olduğu için aygıt erişimi denetimi tamamlanamadı (Resource busy). Bu bir izin reddi değildir. Yazma işlemi, güvenli ayırmadan sonra erişimi yeniden denetler. Disk bağlantısı değiştirilmedi.")
            }
            throw ToolError.message("Disk erişimi doğrulanamadı (\(path), errno \(code): \(String(cString: strerror(code)))). Diskin bağlantısı değiştirilmedi.")
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
            catch { throw ToolError.message("Mevcut disk bağlantısı kesilemedi. Yazma sürücüsü başlatılmadı.\n" + error.localizedDescription) }
        }
        do { try mount() }
        catch {
            let cause = error.localizedDescription
            var recovery = ""
            var cleaned = true
            do { try cleanup() } catch { cleaned = false; recovery += "\nBaşlatılan sürücü/bağlantı temizlenemedi: " + error.localizedDescription }
            if initiallyMounted && cleaned {
                do { try restore(); recovery += "\nÖnceki bağlantı durumu korundu veya salt okunur erişim geri açıldı." }
                catch { recovery += "\nSalt okunur bağlantı geri açılamadı:\n" + error.localizedDescription }
            }
            if !cleaned { recovery += "\nGüvenli temizlik doğrulanmadığı için yeniden bağlama başlatılmadı." }
            let guidance = DiskAccess.isPermissionFailure(cause)
                ? "macOS disk erişimini engelledi. Ayarlardaki Tam Disk Erişimi adımlarını izleyin."
                : "NTFS yazma bağlantısı kurulamadı."
            throw ToolError.message(guidance + "\n" + cause + recovery)
        }
    }
}
