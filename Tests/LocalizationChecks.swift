import Foundation
import Darwin

@main enum LocalizationChecks {
    static var passed = 0
    static var failed = 0
    static func check(_ name: String, _ body: () throws -> Bool) {
        do {
            if try body() { passed += 1; print("PASS \(name)") }
            else { failed += 1; print("FAIL \(name)") }
        } catch { failed += 1; print("FAIL \(name): \(error)") }
    }
    static func main() {
        let domain = "org.plainmount.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain); L10n.configureProcess(nil) }
        check("first launch defaults to English independently of system language") {
            defaults.set(["tr"], forKey: "AppleLanguages")
            return L10n.selected(in: defaults) == .english
        }
        check("Turkish selection survives reading preferences again") {
            L10n.save(.turkish, in: defaults)
            let reloaded = UserDefaults(suiteName: domain)!
            return L10n.selected(in: reloaded) == .turkish && reloaded.stringArray(forKey: "AppleLanguages") == ["tr"]
        }
        check("invalid saved language falls back to English") {
            defaults.set("unsupported", forKey: "language")
            return L10n.selected(in: defaults) == .english
        }
        check("changing language updates drive status without changing disk identity") {
            var value = CoreFixture.value
            value["WritableVolume"] = false
            let disk = DiskService.parse(value, allowedParents: ["disk9"])!
            let identity = disk.identity
            L10n.configureProcess(.english)
            let english = disk.status
            L10n.configureProcess(.turkish)
            return english == "Read-only" && disk.status == "Salt okunur" && disk.identity == identity
        }
        check("privileged helper gets the selected language and unchanged disk arguments") {
            L10n.configureProcess(.turkish)
            let args = ["--mount-helper", "disk9s1", "encoded-identity", "501", "20"]
            let invocation = L10n.commandArguments(args)
            L10n.configureProcess(.english)
            let parsed = try L10n.parseArguments(invocation)
            return invocation.prefix(2) == ["--language", "tr"] && parsed == args && L10n.language == .turkish
        }
        check("invalid helper language fails before a disk operation") {
            do { _ = try L10n.parseArguments(["--language", "invalid", "--mount-helper"]); return false }
            catch { return true }
        }
        check("all catalog placeholders match and preserve labels as literal data") {
            let regex = try NSRegularExpression(pattern: "%[0-9]+\\$@")
            func placeholders(_ text: String) -> [String] {
                let range = NSRange(text.startIndex..., in: text)
                return regex.matches(in: text, range: range).map { (text as NSString).substring(with: $0.range) }.sorted()
            }
            for (english, turkish) in L10n.turkish {
                guard !english.isEmpty, !turkish.isEmpty, placeholders(english) == placeholders(turkish) else { return false }
                let count = Set(placeholders(english)).count
                let args = (0..<count).map { "Drive \($0 + 1) %s %@ '$(command)' çığöşü" }
                for language in AppLanguage.allCases {
                    let result = L10n.text(english, language: language, arguments: args)
                    if !args.allSatisfy({ result.contains($0) }) { return false }
                }
            }
            return true
        }
        check("permission errors remain recognizable in both languages") {
            for language in AppLanguage.allCases {
                L10n.configureProcess(language)
                let message = DiskAccess.permissionMessage(path: "/dev/disk9s1", code: EPERM)
                guard DiskAccess.isPermissionFailure(message), message.contains("PlainMount") else { return false }
            }
            return true
        }
        check("English UI can summarize an older Turkish helper error") {
            L10n.configureProcess(.english)
            let message = DiskAccess.userMessage("Mevcut disk bağlantısı kesilemedi. detail")
            return message.contains("The writing driver was not started") && !message.contains("Mevcut")
        }
        print("\(passed)/\(passed + failed) localization checks passed")
        if failed > 0 { exit(1) }
    }
}

enum CoreFixture {
    static let value: [String: Any] = [
        "DeviceIdentifier": "disk9s1", "ParentWholeDisk": "disk9", "Internal": false,
        "WholeDisk": false, "FilesystemType": "ntfs", "VolumeName": "SampleDisk",
        "VolumeSize": Int64(128_000_000_000), "FreeSpace": Int64(96_000_000_000),
        "MountPoint": "/Volumes/SampleDisk", "WritableMedia": true, "WritableVolume": false,
        "DeviceTreePath": "USB/path", "PartitionMapPartitionOffset": 32256
    ]
}
