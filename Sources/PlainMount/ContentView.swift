import SwiftUI
import Combine
import MountCore

struct ContentView: View {
    @EnvironmentObject var model: Model
    @AppStorage("appearance") private var appearance = "system"
    private let timer = Timer.publish(every: 12, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: Theme.sidebar)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.xl) {
                        if let error = model.error { errorBanner(error) }
                        if model.page == "settings" { settings }
                        else if model.page == "activity" { activity }
                        else { disks }
                    }.padding(Theme.xl)
                }
                Divider()
                HStack(spacing: Theme.sm) {
                    if model.busy || model.scanning { ProgressView().controlSize(.small) }
                    Text(model.busy ? L("Drive operation in progress…") : model.scanning ? L("Scanning drives…") : model.stale ? L("Last verified drive information · Refresh required") : L("External volumes: %1$@ · NTFS: %2$@", String(describing: model.disks.count), String(describing: model.ntfsCount)))
                    Spacer()
                    if let date = model.lastRefresh { Text(L("Last scan %1$@", String(describing: date.formatted(.dateTime.hour().minute().locale(model.language.locale))))) }
                }.font(Theme.small).foregroundStyle(.secondary).padding(.horizontal, Theme.xl).padding(.vertical, Theme.md)
            }
        }
        .background(Theme.page)
        .environment(\.locale, model.language.locale)
        .font(Theme.body)
        .frame(minWidth: Theme.minimumWidth, minHeight: Theme.minimumHeight)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .task { await model.refresh() }
        .onReceive(timer) { _ in if model.error == nil { Task { await model.refresh() } } }
        .sheet(item: $model.pending) { action in
            ConfirmationSheet(action: action) {
                model.pending = nil
                model.execute(action.kind, disk: action.disk)
            } cancel: { model.pending = nil }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Theme.xl) {
            HStack(spacing: Theme.md) {
                Image(systemName: "externaldrive.fill").font(Theme.section).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: Theme.xs) {
                    Text("PlainMount").font(Theme.section)
                    Text(L("Your Mac. Your drives.")).font(Theme.small).foregroundStyle(.secondary)
                }
            }.padding(.top, Theme.lg)
            VStack(spacing: Theme.xs) {
                nav(L("My drives"), icon: "externaldrive", page: "disks")
                nav(L("Activity"), icon: "clock.arrow.circlepath", page: "activity")
                nav(L("Settings"), icon: "slider.horizontal.3", page: "settings")
            }
            Divider()
            VStack(alignment: .leading, spacing: Theme.md) {
                Text(L("External drives")).font(Theme.label).foregroundStyle(.secondary)
                ForEach(model.visible) { disk in
                    Button {
                        model.selected = disk.id
                        model.page = "disks"
                    } label: {
                        HStack(spacing: Theme.sm) {
                            Image(systemName: "externaldrive.fill").foregroundStyle(disk.writable ? Theme.success : .secondary)
                            Text(disk.name).lineLimit(1)
                            Spacer(minLength: 0)
                            if model.selected == disk.id { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                        }.padding(Theme.sm).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(model.selected == disk.id && model.page == "disks" ? Theme.subtle : .clear, in: RoundedRectangle(cornerRadius: Theme.sm))
                    .accessibilityLabel("\(disk.name), \(disk.status)")
                    .accessibilityAddTraits(model.selected == disk.id ? .isSelected : [])
                }
                if model.visible.isEmpty { Text(L("Connect a drive to see it here.")).font(Theme.small).foregroundStyle(.secondary) }
            }
            Spacer()
            VStack(alignment: .leading, spacing: Theme.sm) {
                Label(L("Personal edition"), systemImage: "person.crop.circle").font(Theme.small)
                Text(L("%1$@ · Apple Silicon", String(describing: AppBuild.version))).font(Theme.small).foregroundStyle(.secondary)
            }
        }.padding(Theme.lg).background(.ultraThinMaterial)
    }

    private func nav(_ title: String, icon: String, page: String) -> some View {
        Button { model.page = page } label: {
            HStack(spacing: Theme.md) { Image(systemName: icon); Text(title); Spacer() }
                .padding(Theme.md).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(model.page == page ? Theme.subtle : .clear, in: RoundedRectangle(cornerRadius: Theme.sm))
        .accessibilityAddTraits(model.page == page ? .isSelected : [])
    }

    private var header: some View {
        HStack {
            Text(model.page == "settings" ? L("Settings") : model.page == "activity" ? L("Activity") : L("My drives")).font(Theme.section)
            Spacer()
            Button { Task { await model.refresh() } } label: { Label(L("Refresh"), systemImage: "arrow.clockwise") }
                .disabled(model.scanning || model.busy)
                .keyboardShortcut("r", modifiers: .command)
                .help(L("Rescan the external drive list"))
        }.padding(.horizontal, Theme.xl).padding(.vertical, Theme.lg)
    }

    private var disks: some View {
        VStack(alignment: .leading, spacing: Theme.xl) {
            VStack(alignment: .leading, spacing: Theme.sm) {
                Text(L("Work with your drive.")).font(Theme.title)
                Text(L("Manage connections and access in one place.")).foregroundStyle(.secondary)
            }
            HStack {
                Text(L("NTFS volumes: %1$@", String(describing: model.ntfsCount))).font(Theme.small).foregroundStyle(.secondary)
                Spacer()
                Toggle(L("Only NTFS"), isOn: $model.onlyNTFS).toggleStyle(.checkbox)
                    .onChange(of: model.onlyNTFS) { _, _ in
                        if !model.visible.contains(where: { $0.id == model.selected }) { model.selected = model.visible.first?.id }
                    }
            }
            if let disk = model.selectedDisk, model.visible.contains(where: { $0.id == disk.id }) {
                diskDetail(disk)
            } else {
                VStack(spacing: Theme.lg) {
                    Image(systemName: "externaldrive.badge.plus").font(Theme.title).foregroundStyle(.secondary)
                    Text(model.scanning ? L("Looking for drives") : model.stale ? L("Drive information could not be verified") : L("Connect an external drive")).font(Theme.section)
                    Text(L("%1$@ USB and Thunderbolt drives appear here.", String(describing: model.onlyNTFS ? L("NTFS-formatted") : L("External")))).foregroundStyle(.secondary)
                    if !model.disks.isEmpty && model.onlyNTFS {
                        Button(L("Show all external drives")) { model.onlyNTFS = false; model.selected = model.visible.first?.id }
                    }
                }.frame(maxWidth: .infinity).padding(.vertical, Theme.xxl).panel()
            }
            if model.disks.contains(where: { $0.isNTFS && !$0.writable }) {
                HStack(alignment: .top, spacing: Theme.md) {
                    Image(systemName: "info.circle").foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: Theme.sm) {
                        Text(L("What does read-only mean?")).fontWeight(.semibold)
                        Text(L("You can open files and copy them to your Mac. Enable writing to add or edit files on the drive.")).foregroundStyle(.secondary)
                    }
                }.panel()
            }
            if let recent = model.activities.first {
                Label(recent.message, systemImage: recent.failed ? "exclamationmark.circle" : "checkmark.circle")
                    .foregroundStyle(recent.failed ? Theme.danger : .secondary).font(Theme.small)
            }
        }
    }

    private func diskDetail(_ disk: DiskVolume) -> some View {
        VStack(alignment: .leading, spacing: Theme.lg) {
            HStack(alignment: .center, spacing: Theme.lg) {
                Image(systemName: "externaldrive.fill").font(.system(size: Theme.heroIcon)).foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.sm) {
                    Text(disk.name).font(Theme.section).textSelection(.enabled)
                    Text(L("%1$@ · %2$@ · External drive", String(describing: disk.filesystem.uppercased()), String(describing: capacity(disk.size)))).foregroundStyle(.secondary)
                }
                Spacer()
                Label(disk.status, systemImage: !disk.mounted ? "circle.dashed" : disk.writable ? "checkmark.circle.fill" : "lock.fill")
                    .font(Theme.small).foregroundStyle(disk.writable ? Theme.success : .secondary)
            }
            Divider()
            if let free = disk.free {
                VStack(alignment: .leading, spacing: Theme.sm) {
                    HStack { Text(L("%1$@ used", String(describing: capacity(disk.used ?? 0)))); Spacer(); Text(L("%1$@ free", String(describing: capacity(free)))) }
                        .font(Theme.small).foregroundStyle(.secondary)
                    ProgressView(value: min(1, max(0, disk.usedFraction))).tint(Theme.accent)
                        .accessibilityLabel(L("Used space")).accessibilityValue(capacity(disk.used ?? 0))
                }
            }
            Grid(alignment: .leading, horizontalSpacing: Theme.xl, verticalSpacing: Theme.md) {
                GridRow { Text(L("Device")).foregroundStyle(.secondary); Text("/dev/" + disk.id).textSelection(.enabled) }
                GridRow { Text(L("Location")).foregroundStyle(.secondary); Text(disk.mountPoint ?? L("Not mounted")).textSelection(.enabled).lineLimit(2) }
                GridRow { Text(L("Access")).foregroundStyle(.secondary); Text(disk.status) }
            }.font(Theme.small)
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.md) { diskButtons(disk) }
                VStack(alignment: .leading, spacing: Theme.md) { diskButtons(disk) }
            }.disabled(model.busy || model.scanning || model.stale)
            if disk.isNTFS && !disk.writable && !model.backend.ready {
                Text(L("Writing components are missing from this build. Download the complete app from Releases."))
                    .font(Theme.small).foregroundStyle(Theme.warning)
            }
        }.panel()
    }

    @ViewBuilder private func diskButtons(_ disk: DiskVolume) -> some View {
        if disk.isNTFS && !disk.writable {
            Button { model.action("write", disk: disk) } label: { Label(L("Enable writing"), systemImage: "pencil") }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.backend.ready || !disk.mediaWritable)
        }
        Button { model.openFinder(disk) } label: { Label(L("Open in Finder"), systemImage: "folder") }
            .controlSize(.large).disabled(!disk.mounted)
        if disk.mounted {
            Menu {
                Button(L("Disconnect")) { model.action("unmount", disk: disk) }
                Button(L("Safely eject")) { model.action("eject", disk: disk) }
            } label: { Label(L("Eject"), systemImage: "eject") }.controlSize(.large).fixedSize()
        } else {
            Button(L("Mount read-only")) { model.action("mount", disk: disk) }.controlSize(.large)
            Button(L("Safely eject")) { model.action("eject", disk: disk) }.controlSize(.large)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: Theme.xl) {
            Text(L("A tool of your own.")).font(Theme.title)
            VStack(alignment: .leading, spacing: Theme.md) {
                Picker(L("Language"), selection: $model.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.nativeName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.busy || model.scanning)
                Text(L("Your choice is saved. The interface language changes immediately."))
                    .font(Theme.small).foregroundStyle(.secondary)
            }.panel()
            VStack(alignment: .leading, spacing: Theme.lg) {
                Text(L("Appearance")).font(Theme.section)
                Picker(L("Theme"), selection: $appearance) {
                    Text(L("System")).tag("system"); Text(L("Light")).tag("light"); Text(L("Dark")).tag("dark")
                }.pickerStyle(.segmented)
            }.panel()
            VStack(alignment: .leading, spacing: Theme.md) {
                Text(L("macOS drive access")).font(Theme.section)
                Text(L("1. Move the app to Applications.\n2. Add and enable PlainMount in Full Disk Access.\n3. Quit the app completely and reopen it.")).fixedSize(horizontal: false, vertical: true)
                Text(L("Permission must be granted to PlainMount itself. Permissions for Terminal or another app do not apply.")).foregroundStyle(.secondary)
                if !AppBuild.isInstalled() {
                    Label(L("Move to Applications first"), systemImage: "folder.badge.plus").foregroundStyle(.primary)
                }
                Text(Bundle.main.bundleURL.path).font(Theme.small).foregroundStyle(.secondary).textSelection(.enabled)
                ViewThatFits(in: .horizontal) {
                    HStack { Button(L("Show application in Finder")) { model.revealApplication() }; Button(L("Open Full Disk Access settings")) { model.openDiskAccessSettings() } }
                    VStack(alignment: .leading) { Button(L("Show application in Finder")) { model.revealApplication() }; Button(L("Open Full Disk Access settings")) { model.openDiskAccessSettings() } }
                }
                Button(L("Check selected drive access")) { model.checkDiskAccess() }
                    .disabled(model.busy || model.scanning || model.stale || model.selectedDisk == nil || !AppBuild.isInstalled())
                if let result = model.accessCheckResult { Label(result, systemImage: "checkmark.circle").font(Theme.small) }
                if model.needsDiskAccess { Text(L("macOS denied access. Grant permission, reopen the app, and check access again.")).font(Theme.small).foregroundStyle(.primary) }
                Text(L("The check does not write files or change the drive connection. Administrator approval is required.")).font(Theme.small).foregroundStyle(.secondary)
            }.panel()
            VStack(alignment: .leading, spacing: Theme.md) {
                Text(L("Write support")).font(Theme.section)
                Label(model.backend.ready ? L("NTFS writing components ready") : L("Writing components not found"), systemImage: model.backend.ready ? "checkmark.circle" : "exclamationmark.circle")
                    .foregroundStyle(model.backend.ready ? Theme.success : Theme.warning)
                Text(L("Writing requires macOS administrator approval. Your password is not stored. Connecting a drive does not run an automatic file-writing test."))
                    .foregroundStyle(.secondary)
            }.panel()
            VStack(alignment: .leading, spacing: Theme.md) {
                Text(L("Privacy and diagnostics")).font(Theme.section)
                Text(L("The app has no accounts, ads, telemetry, or automatic update service. Activity is kept for this session only.")).foregroundStyle(.secondary)
                Button(L("Save diagnostics…")) { model.exportDiagnostics() }.disabled(model.busy)
                Text(L("Diagnostics include drive names and local paths. They are saved only to the location you choose.")).font(Theme.small).foregroundStyle(.secondary)
            }.panel()
            Text(L("PlainMount %1$@ · macOS 14+ · Personal use", String(describing: AppBuild.version))).font(Theme.small).foregroundStyle(.secondary)
            if model.backend.ready {
                Text(L("Application code is MIT-licensed. NTFS-3G and FUSE-T retain their own licenses; FUSE-T is free for non-commercial use."))
                    .font(Theme.small).foregroundStyle(.secondary)
            }
        }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: Theme.lg) {
            Text(L("This session.")).font(Theme.title)
            Text(L("Drive operation results appear here. Activity is cleared when you quit the app.")).foregroundStyle(.secondary)
            if model.activities.isEmpty {
                Label(L("No drive operations yet. Select a drive to get started."), systemImage: "clock").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).panel()
            }
            ForEach(model.activities) { item in
                HStack(alignment: .top, spacing: Theme.md) {
                    Image(systemName: item.failed ? "exclamationmark.circle" : "checkmark.circle")
                        .foregroundStyle(item.failed ? Theme.danger : Theme.success)
                    VStack(alignment: .leading, spacing: Theme.sm) {
                        Text(item.message).textSelection(.enabled)
                        Text(item.date.formatted(.dateTime.hour().minute().second().locale(model.language.locale))).font(Theme.small).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).panel()
            }
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.md) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.danger)
            VStack(alignment: .leading, spacing: Theme.md) {
                Text(text).textSelection(.enabled)
                if let details = model.errorDetails, details != text {
                    DisclosureGroup(L("Technical details")) { Text(details).font(Theme.small).textSelection(.enabled) }
                }
            }
            Spacer()
            Button { model.error = nil; model.errorDetails = nil } label: { Image(systemName: "xmark") }
                .accessibilityLabel(L("Dismiss error"))
        }.panel()
    }
}

struct ConfirmationSheet: View {
    let action: PendingAction
    let confirm: () -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.lg) {
            Label(action.title, systemImage: action.kind == "write" ? "pencil.circle" : "eject.circle").font(Theme.section)
            Text(action.detail).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button(L("Cancel"), action: cancel).keyboardShortcut(.cancelAction); Button(action.button, action: confirm).buttonStyle(.borderedProminent) }
        }.padding(Theme.xl).frame(width: Theme.defaultWidth / 2)
    }
}
