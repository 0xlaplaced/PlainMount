import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case turkish = "tr"
    public var id: String { rawValue }
    public var nativeName: String { self == .english ? "English" : "Türkçe" }
    public var locale: Locale { Locale(identifier: rawValue) }
}

public enum L10n {
    private static let lock = NSLock()
    private static var processLanguage: AppLanguage?
    public static func selected(in defaults: UserDefaults) -> AppLanguage {
        AppLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .english
    }
    public static var language: AppLanguage {
        lock.lock()
        let value = processLanguage
        lock.unlock()
        return value ?? selected(in: .standard)
    }
    // Helpers receive this explicitly; root's preferences never determine the UI language.
    public static func configureProcess(_ language: AppLanguage?) {
        lock.lock(); processLanguage = language; lock.unlock()
    }
    public static func save(_ language: AppLanguage, in defaults: UserDefaults = .standard) {
        defaults.set(language.rawValue, forKey: "language")
        defaults.set([language.rawValue], forKey: "AppleLanguages")
    }
    public static func commandArguments(_ arguments: [String]) -> [String] {
        ["--language", language.rawValue] + arguments
    }
    public static func parseArguments(_ arguments: [String]) throws -> [String] {
        guard arguments.first == "--language" else { return arguments }
        guard arguments.count >= 2, let language = AppLanguage(rawValue: arguments[1]) else {
            throw ToolError.message(L("Unsupported language. Use --language en or --language tr."))
        }
        configureProcess(language)
        return Array(arguments.dropFirst(2))
    }
    public static func text(_ key: String, language: AppLanguage, arguments: [CVarArg] = []) -> String {
        let format = language == .turkish ? (turkish[key] ?? key) : key
        return arguments.isEmpty ? format : String(format: format, locale: language.locale, arguments: arguments)
    }
    public static func contains(_ text: String, key: String) -> Bool {
        AppLanguage.allCases.contains { text.contains(self.text(key, language: $0)) }
    }
    public static let turkish: [String: String] = [
        "Rescan the external drive list": "Harici disk listesini yeniden tara",
        "Unsupported language. Use --language en or --language tr.": "Desteklenmeyen dil. --language en veya --language tr kullanın.",
        "Enable writing for %1$@": "%1$@ için yazmayı etkinleştir",
        "Safely eject %1$@": "%1$@ diskini güvenle çıkar",
        "Disconnect %1$@": "%1$@ bağlantısını kes",
        "%1$@ · %2$@\nThe drive will be disconnected and reconnected with write access. Close open files first. macOS will ask for administrator approval. The app will not repair the drive or remove hibernation data.": "%1$@ · %2$@\nDiskin mevcut bağlantısı kesilip yazılabilir olarak yeniden bağlanacak. Açık dosyaları kapatın. macOS yönetici izni isteyecek. Disk otomatik onarılmaz; hazırda bekletme verisi silinmez.",
        "All volumes on %1$@ will be ejected. Close open files first. Disconnect the cable after the success message.": "%1$@ üzerindeki tüm bölümler çıkarılacak. Açık dosyaları kapatın. Başarı mesajından sonra kabloyu ayırabilirsiniz.",
        "Close open files on this volume. To unplug the physical drive, choose Safely eject.": "Bu bölümün açık dosyalarını kapatın. Fiziksel diski ayırmak için Güvenle çıkar seçeneğini kullanın.",
        "Enable writing": "Yazmayı etkinleştir",
        "Eject drive": "Diski çıkar",
        "Disconnect": "Bağlantıyı kes",
        "%1$@: write access enabled.": "%1$@: yazılabilir bağlama oluşturuldu.",
        "%1$@ safely ejected. You can disconnect the cable.": "%1$@ güvenle çıkarıldı. Kabloyu ayırabilirsiniz.",
        "%1$@ disconnected.": "%1$@ bağlantısı kesildi.",
        "%1$@ mounted read-only.": "%1$@ salt okunur bağlandı.",
        "Access to %1$@ verified. The drive connection was not changed.": "%1$@ aygıtına erişim doğrulandı. Diskin bağlantısı değiştirilmedi.",
        "Open System Settings → Privacy & Security → Full Disk Access.": "Sistem Ayarları → Gizlilik ve Güvenlik → Tam Disk Erişimi bölümünü açın.",
        "The drive mount location changed. Refresh the list.": "Diskin bağlama yolu değişti. Listeyi yenileyin.",
        "Finder could not open this location. Refresh the drive list and try again.": "Finder bu konumu açamadı.",
        "Save drive diagnostics": "Disk tanısını kaydet",
        "Diagnostics saved. The file includes drive names and local paths.": "Tanı dosyası kaydedildi. Disk adlarını ve yerel yolları içerir.",
        "Write access enabled.": "Yazılabilir bağlama oluşturuldu.",
        "Drive access verified. The connection was not changed.": "Disk erişimi doğrulandı. Bağlantı değiştirilmedi.",
        "Drive disconnected.": "Bağlantı kesildi.",
        "Unknown option. Open PlainMount without command-line options.": "Bilinmeyen seçenek.",
        "Show settings": "Ayarları göster",
        "NTFS volumes: %1$@": "%1$@ NTFS bölüm",
        "%1$@ · %2$@": "%1$@ · %2$@",
        "Open in Finder": "Finder’da aç",
        "Open application": "Uygulamayı aç",
        "Quit": "Çıkış",
        "Drive operation in progress…": "Disk işlemi sürüyor…",
        "Scanning drives…": "Diskler taranıyor…",
        "Last verified drive information · Refresh required": "Son doğrulanan disk bilgisi · Yenile gerekiyor",
        "External volumes: %1$@ · NTFS: %2$@": "%1$@ harici bölüm · %2$@ NTFS",
        "Your Mac. Your drives.": "Mac’in, disklerin.",
        "Activity": "İşlem geçmişi",
        "External drives": "Harici diskler",
        "Connect a drive to see it here.": "Disk bağladığında burada görünür.",
        "Personal edition": "Kişisel sürüm",
        "%1$@ · Apple Silicon": "%1$@ · Apple Silicon",
        "Work with your drive.": "Diskinle çalış.",
        "Manage connections and access in one place.": "Bağlantıyı ve erişim durumunu tek yerden yönet.",
        "Only NTFS": "Yalnızca NTFS",
        "Looking for drives": "Diskler aranıyor",
        "Drive information could not be verified": "Disk bilgileri doğrulanamadı",
        "Connect an external drive": "Bir harici disk bağla",
        "%1$@ USB and Thunderbolt drives appear here.": "%1$@ USB ve Thunderbolt diskler burada görünür.",
        "Show all external drives": "Tüm harici diskleri göster",
        "You can open files and copy them to your Mac. Enable writing to add or edit files on the drive.": "Dosyalarını açabilir ve Mac’ine kopyalayabilirsin. Diske dosya eklemek veya düzenlemek için yazmayı etkinleştir.",
        "%1$@ · %2$@ · External drive": "%1$@ · %2$@ · Harici disk",
        "%1$@ used": "%1$@ kullanılıyor",
        "%1$@ free": "%1$@ boş",
        "Used space": "Kullanılan alan",
        "Device": "Aygıt",
        "Location": "Konum",
        "Not mounted": "Bağlı değil",
        "Access": "Erişim",
        "Writing components are missing from this build. Download the complete app from Releases.": "Yazma için uyumlu harici bileşenler gerekir. Bu kaynak dağıtımına dahil değildir.",
        "Safely eject": "Güvenle çıkar",
        "Eject": "Çıkar",
        "Mount read-only": "Salt okunur bağla",
        "A tool of your own.": "Sana ait bir araç.",
        "Appearance": "Görünüm",
        "Theme": "Tema",
        "System": "Sistem",
        "Light": "Açık",
        "Dark": "Koyu",
        "macOS drive access": "macOS disk erişimi",
        "1. Move the app to Applications.\n2. Add and enable PlainMount in Full Disk Access.\n3. Quit the app completely and reopen it.": "1. Uygulamayı Uygulamalar klasörüne taşı.\n2. Tam Disk Erişimi bölümünde PlainMount’i ekleyip etkinleştir.\n3. Uygulamayı tamamen kapatıp yeniden aç.",
        "Permission must be granted to PlainMount itself. Permissions for Terminal or another app do not apply.": "İzin PlainMount uygulamasına verilir. Terminal veya başka bir uygulamanın izni geçerli değildir.",
        "Move to Applications first": "Önce Uygulamalar klasörüne taşı",
        "Show application in Finder": "Uygulamayı Finder’da göster",
        "Open Full Disk Access settings": "Tam Disk Erişimi ayarlarını aç",
        "Check selected drive access": "Seçilen diske erişimi denetle",
        "macOS denied access. Grant permission, reopen the app, and check access again.": "macOS erişimi reddetti. İzni verdikten sonra uygulamayı yeniden açın ve erişimi tekrar denetleyin.",
        "The check does not write files or change the drive connection. Administrator approval is required.": "Denetim dosya yazmaz ve disk bağlantısını değiştirmez. Yönetici izni istenir.",
        "Write support": "Yazma desteği",
        "NTFS writing components ready": "NTFS yazma bileşenleri hazır",
        "Writing components not found": "Yazma bileşenleri bulunamadı",
        "Writing requires macOS administrator approval. Your password is not stored. Connecting a drive does not run an automatic file-writing test.": "Yazma için macOS yönetici izni istenir. Parolan uygulamada saklanmaz. Diski bağlamak, otomatik dosya yazma testi yapmaz.",
        "Privacy and diagnostics": "Gizlilik ve tanı",
        "The app has no accounts, ads, telemetry, or automatic update service. Activity is kept for this session only.": "Uygulama hesap, reklam, telemetri veya otomatik güncelleme servisi kullanmaz. İşlem geçmişi yalnızca bu oturumda tutulur.",
        "Save diagnostics…": "Tanı dosyasını kaydet…",
        "Diagnostics include drive names and local paths. They are saved only to the location you choose.": "Tanı dosyası disk adlarını ve yerel yolları içerir; yalnızca seçtiğin konuma kaydedilir.",
        "PlainMount %1$@ · macOS 14+ · Personal use": "PlainMount %1$@ · macOS 14+ · Kişisel kullanım",
        "Application code is MIT-licensed. NTFS-3G and FUSE-T retain their own licenses; FUSE-T is free for non-commercial use.": "Uygulama kodu MIT lisanslıdır. NTFS-3G ve FUSE-T kendi lisanslarına tabidir; FUSE-T ticari olmayan kullanım için ücretsizdir.",
        "Drive operation results appear here. Activity is cleared when you quit the app.": "Disk işlemlerinin sonuçları burada görünür. Uygulama kapanınca geçmiş temizlenir.",
        "No drive operations yet. Select a drive to get started.": "Henüz disk işlemi yapılmadı.",
        "Technical details": "Teknik ayrıntılar",
        "Dismiss error": "Hata mesajını kapat",
        "Cancel": "Vazgeç",
        "Exit status: %1$@": "Çıkış kodu: %1$@",
        "Output:\n": "Çıktı:\n",
        "Error:\n": "Hata:\n",
        "Could not start the process: %1$@": "İşlem başlatılamadı: %1$@",
        "Process lifecycle has been handed off.": "İşlem yaşam döngüsü devredildi.",
        "The process status could not be verified. Refresh drive status before trying again.": "Başlatılan işlemin durumu doğrulanamadı.",
        "The operation timed out. %1$@\n%2$@": "İşlem zaman aşımına uğradı. %1$@\n%2$@",
        "macOS drive information could not be read. Refresh the list and try again.": "macOS disk bilgisi okunamadı.",
        "Invalid drive identifier. Refresh the list and select the drive again.": "Geçersiz disk kimliği.",
        "Could not get drive information: %1$@": "Disk bilgisi alınamadı: %1$@",
        "%1$@ is still mounted, but current drive information is unavailable. The last verified list is preserved. Choose Refresh to try again.": "%1$@ hâlâ bağlı, ancak güncel disk bilgisi alınamadı. Son doğrulanan liste korunuyor; Yenile ile tekrar deneyin.",
        "The drive changed or was removed. Refresh the list and select it again.": "Disk değişti veya çıkarıldı. Listeyi yenileyip diski yeniden seçin.",
        "Unsupported drive operation. Refresh the list and try again.": "Desteklenmeyen disk işlemi.",
        "This drive is not available for writing. Refresh its status and try again.": "Bu disk yazma işlemi için uygun değil.",
        "Compatible writing components were not found. Download the complete app from Releases.": "Uyumlu harici yazma bileşenleri bulunamadı. Bu kaynak dağıtımına dahil değildir.",
        "Administrator authorization or drive parameters are invalid. Refresh the list and try again.": "Yönetici yetkisi veya disk parametreleri geçersiz.",
        "Drive identity could not be verified. No action was taken. Refresh the list and select the drive again.": "Disk kimliği doğrulanamadı; hiçbir işlem yapılmadı.",
        "The PlainMount connection was not found. Refresh the list.": "Kişisel bağlama bulunamadı. Listeyi yenileyin.",
        "The application location could not be found. Move PlainMount to Applications and reopen it.": "Uygulama yolu bulunamadı.",
        "Authorization or drive parameters are invalid. Refresh the list and try again.": "Yetki veya disk parametreleri geçersiz.",
        "Drive identity or mount location changed. Refresh the list and select the drive again.": "Disk kimliği veya bağlama yolu değişti.",
        "This drive is not available for NTFS writing. Refresh its status and try again.": "Bu disk NTFS yazma için uygun değil.",
        "The bundled NTFS driver is missing. Download the complete app from Releases.": "Paket içindeki NTFS sürücüsü eksik.",
        "The mount folder is in use: %1$@. Check drive status before trying again.": "Bağlama klasörü kullanımda: %1$@. Önce disk durumunu kontrol edin.",
        "macOS remounted the drive. The writing driver was not started. Choose Refresh to try again.": "macOS diski yeniden bağladı. Yazma sürücüsü başlatılmadı; Yenile ile tekrar deneyin.",
        "The NTFS driver exited before the connection was ready.\n": "NTFS sürücüsü bağlantı hazır olmadan kapandı.\n",
        "The NTFS driver could not be confirmed as stopped. A new connection was not started. Check drive status before trying again.": "Başlatılan NTFS sürücüsünün sonlandığı doğrulanamadı. Yeni bağlama başlatılmadı.",
        "The NTFS connection still exists. Reconnection was not started. Refresh drive status before trying again.": "NTFS bağlantısı hâlâ mevcut; yeniden bağlama başlatılmadı.",
        "A new NTFS connection exists. Refresh drive status and manage the connection from the app.": "Yeni NTFS bağlantısı mevcut. Disk durumunu yenileyip bağlantıyı uygulamadan kontrol edin.",
        "Before writing, move the app to Applications: %1$@. Grant Full Disk Access to the app at this location, then reopen it.": "Yazma için uygulamayı önce Uygulamalar klasörüne taşıyın: %1$@. Tam Disk Erişimi iznini bu sabit konumdaki uygulamaya verin ve uygulamayı yeniden açın.",
        "macOS blocked drive access. Follow the macOS drive access steps in Settings, then reopen the app.": "macOS disk erişimini engelledi. Ayarlar bölümündeki macOS disk erişimi adımlarını izleyin, ardından uygulamayı yeniden açın.",
        "The current drive connection could not be disconnected": "Mevcut disk bağlantısı kesilemedi",
        "The current drive connection could not be disconnected. The writing driver was not started. Check the technical details and try again.": "Mevcut disk bağlantısı kesilemedi. Yazma sürücüsü başlatılmadı. Teknik ayrıntıları inceleyip tekrar deneyin.",
        "The NTFS writing connection could not be established": "NTFS yazma bağlantısı kurulamadı",
        "The NTFS writing connection could not be established. Check the technical details for the cause and recovery result.": "NTFS yazma bağlantısı kurulamadı. Nedenini ve geri bağlama sonucunu teknik ayrıntılardan inceleyebilirsiniz.",
        "NTFS_ACCESS_DENIED: macOS blocked drive access (%1$@, errno %2$@: %3$@).\nIn System Settings → Privacy & Security → Full Disk Access, add and enable PlainMount from Applications. Quit the app completely and reopen it. The drive connection was not changed.": "NTFS_ACCESS_DENIED: macOS disk erişimini engelledi (%1$@, errno %2$@: %3$@).\nSistem Ayarları → Gizlilik ve Güvenlik → Tam Disk Erişimi bölümünde Uygulamalar klasöründeki PlainMount uygulamasını ekleyip etkinleştirin. Ardından uygulamayı tamamen kapatıp yeniden açın. Diskin bağlantısı değiştirilmedi.",
        "Administrator approval is required to check drive access. Try again and approve the macOS prompt.": "Disk erişimi denetimi için yönetici yetkisi gerekli.",
        "Drive access could not be checked while the device is mounted (Resource busy). This is not a permission denial. Writing will check access again after a safe disconnect. The drive connection was not changed.": "Disk bağlı olduğu için aygıt erişimi denetimi tamamlanamadı (Resource busy). Bu bir izin reddi değildir. Yazma işlemi, güvenli ayırmadan sonra erişimi yeniden denetler. Disk bağlantısı değiştirilmedi.",
        "Drive access could not be verified (%1$@, errno %2$@: %3$@). The drive connection was not changed. Check the connection and try again.": "Disk erişimi doğrulanamadı (%1$@, errno %2$@: %3$@). Diskin bağlantısı değiştirilmedi.",
        "The current drive connection could not be disconnected. The writing driver was not started.\n": "Mevcut disk bağlantısı kesilemedi. Yazma sürücüsü başlatılmadı.\n",
        "\nThe started driver or connection could not be cleaned up: ": "\nBaşlatılan sürücü/bağlantı temizlenemedi: ",
        "\nThe previous connection was preserved or read-only access was restored.": "\nÖnceki bağlantı durumu korundu veya salt okunur erişim geri açıldı.",
        "\nRead-only access could not be restored:\n": "\nSalt okunur bağlantı geri açılamadı:\n",
        "\nReconnection was not started because safe cleanup could not be verified.": "\nGüvenli temizlik doğrulanmadığı için yeniden bağlama başlatılmadı.",
        "macOS blocked drive access. Follow the Full Disk Access steps in Settings.": "macOS disk erişimini engelledi. Ayarlardaki Tam Disk Erişimi adımlarını izleyin.",
        "The NTFS writing connection could not be established.": "NTFS yazma bağlantısı kurulamadı.",
        "The NTFS connection was not ready in time. Refresh drive status before trying again.": "NTFS bağlantısı beklenen sürede hazır olmadı.",
        "My drives": "Disklerim",
        "Settings": "Ayarlar",
        "Refresh": "Yenile",
        "Last scan %1$@": "Son tarama %1$@",
        "NTFS-formatted": "NTFS biçimli",
        "External": "Harici",
        "What does read-only mean?": "Salt okunur ne demek?",
        "This session.": "Bu oturumda.",
        "Read and write": "Okuma ve yazma",
        "Read-only": "Salt okunur",
        "The started process was stopped.": "Başlatılan işlem durduruldu.",
        "The process has not been confirmed as stopped. Do not start another drive operation.": "İşlemin sonlandığı henüz doğrulanamadı; yeni disk işlemi başlatmayın.",
        "Language": "Dil",
        "Your choice is saved. The interface language changes immediately.": "Seçimin kaydedilir. Arayüz dili hemen değişir.",
    ]
}

public func L(_ key: String, _ arguments: CVarArg...) -> String {
    L10n.text(key, language: L10n.language, arguments: arguments)
}
