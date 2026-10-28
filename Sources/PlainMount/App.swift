import SwiftUI
import MountCore
import Darwin

@main enum Bootstrap {
    static func main() {
        do {
            let args = try L10n.parseArguments(Array(CommandLine.arguments.dropFirst()))
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
                print(L("Write access enabled."))
                return
            }
            if args.first == "--access-helper" {
                try WriteMount.accessHelper(Array(args.dropFirst()))
                print(L("Drive access verified. The connection was not changed."))
                return
            }
            if args.first == "--unmount-helper" {
                try WriteMount.unmountHelper(Array(args.dropFirst()))
                print(L("Drive disconnected."))
                return
            }
            guard args.isEmpty else { throw ToolError.message(L("Unknown option. Open PlainMount without command-line options.")) }
            // Set this app's native menu/dialog language before AppKit initializes.
            UserDefaults.standard.set([L10n.language.rawValue], forKey: "AppleLanguages")
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
                Button(L("Show settings")) { model.page = "settings" }
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
        Text(L("NTFS volumes: %1$@", String(describing: model.ntfsCount)))
        ForEach(model.disks.filter(\.isNTFS)) { disk in
            Menu(L("%1$@ · %2$@", String(describing: disk.name), String(describing: disk.status))) {
                Button(L("Open in Finder")) { model.openFinder(disk) }.disabled(!disk.mounted || model.busy || model.stale)
            }
        }
        Divider()
        Button(L("Open application")) {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        Button(L("Refresh")) { Task { await model.refresh() } }.disabled(model.busy || model.scanning)
        Divider()
        Button(L("Quit")) { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }
}
