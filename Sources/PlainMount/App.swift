import SwiftUI
import MountCore
import Darwin

@main enum Bootstrap {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        do {
            if args.first == "--diagnose" {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(Diagnostic(disks: DiskService.scan(), backend: BackendStatus.detect()))
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
                return
            }
            if args.first == "--mount-helper" {
                try WriteMount.helper(Array(args.dropFirst()))
                print("Yazılabilir bağlama oluşturuldu.")
                return
            }
            if args.first == "--access-helper" {
                try WriteMount.accessHelper(Array(args.dropFirst()))
                print("Disk erişimi doğrulandı. Bağlantı değiştirilmedi.")
                return
            }
            if args.first == "--unmount-helper" {
                try WriteMount.unmountHelper(Array(args.dropFirst()))
                print("Bağlantı kesildi.")
                return
            }
            guard args.isEmpty else { throw ToolError.message("Bilinmeyen seçenek.") }
            PlainMountApp.main()
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
}

struct PlainMountApp: App {
    @StateObject private var model = Model()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("PlainMount", id: "main") {
            ContentView().environmentObject(model)
        }
        .defaultSize(width: Theme.defaultWidth, height: Theme.defaultHeight)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {
                Button("Ayarları göster") { model.page = "settings" }
            }
        }
        MenuBarExtra("PlainMount", systemImage: "externaldrive") {
            MenuContent().environmentObject(model)
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct MenuContent: View {
    @EnvironmentObject var model: Model
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("\(model.ntfsCount) NTFS bölüm")
        ForEach(model.disks.filter(\.isNTFS)) { disk in
            Menu("\(disk.name) · \(disk.status)") {
                Button("Finder’da aç") { model.openFinder(disk) }.disabled(!disk.mounted || model.busy || model.stale)
            }
        }
        Divider()
        Button("Uygulamayı aç") {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        Button("Yenile") { Task { await model.refresh() } }.disabled(model.busy || model.scanning)
        Divider()
        Button("Çıkış") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }
}
