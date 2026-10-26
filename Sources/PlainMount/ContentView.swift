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
                    Text(model.busy ? "Disk işlemi sürüyor…" : model.scanning ? "Diskler taranıyor…" : model.stale ? "Son doğrulanan disk bilgisi · Yenile gerekiyor" : "\(model.disks.count) harici bölüm · \(model.ntfsCount) NTFS")
                    Spacer()
                    if let date = model.lastRefresh { Text("Son tarama \(date.formatted(date: .omitted, time: .shortened))") }
                }.font(Theme.small).foregroundStyle(.secondary).padding(.horizontal, Theme.xl).padding(.vertical, Theme.md)
            }
        }
        .background(Theme.page)
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
                    Text("Mac’in, disklerin.").font(Theme.small).foregroundStyle(.secondary)
                }
            }.padding(.top, Theme.lg)
            VStack(spacing: Theme.xs) {
                nav("Disklerim", icon: "externaldrive", page: "disks")
                nav("İşlem geçmişi", icon: "clock.arrow.circlepath", page: "activity")
                nav("Ayarlar", icon: "slider.horizontal.3", page: "settings")
            }
            Divider()
            VStack(alignment: .leading, spacing: Theme.md) {
                Text("HARİCİ DİSKLER").font(Theme.label).foregroundStyle(.secondary)
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
                if model.visible.isEmpty { Text("Disk bağladığında burada görünür.").font(Theme.small).foregroundStyle(.secondary) }
            }
            Spacer()
            VStack(alignment: .leading, spacing: Theme.sm) {
                Label("Kişisel sürüm", systemImage: "person.crop.circle").font(Theme.small)
                Text("\(AppBuild.version) · Apple Silicon").font(Theme.small).foregroundStyle(.secondary)
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
            Text(model.page == "settings" ? "Ayarlar" : model.page == "activity" ? "İşlem geçmişi" : "Disklerim").font(Theme.section)
            Spacer()
            Button { Task { await model.refresh() } } label: { Label("Yenile", systemImage: "arrow.clockwise") }
                .disabled(model.scanning || model.busy)
                .keyboardShortcut("r", modifiers: .command)
                .help("Harici disk listesini yeniden tara")
        }.padding(.horizontal, Theme.xl).padding(.vertical, Theme.lg)
    }

    private var disks: some View {
        VStack(alignment: .leading, spacing: Theme.xl) {
            VStack(alignment: .leading, spacing: Theme.sm) {
                Text("Diskinle çalış.").font(Theme.title)
                Text("Bağlantıyı ve erişim durumunu tek yerden yönet.").foregroundStyle(.secondary)
            }
            HStack {
                Text("\(model.ntfsCount) NTFS bölüm").font(Theme.small).foregroundStyle(.secondary)
                Spacer()
                Toggle("Yalnızca NTFS", isOn: $model.onlyNTFS).toggleStyle(.checkbox)
                    .onChange(of: model.onlyNTFS) { _, _ in
                        if !model.visible.contains(where: { $0.id == model.selected }) { model.selected = model.visible.first?.id }
                    }
            }
            if let disk = model.selectedDisk, model.visible.contains(where: { $0.id == disk.id }) {
                diskDetail(disk)
            } else {
                VStack(spacing: Theme.lg) {
                    Image(systemName: "externaldrive.badge.plus").font(Theme.title).foregroundStyle(.secondary)
                    Text(model.scanning ? "Diskler aranıyor" : model.stale ? "Disk bilgileri doğrulanamadı" : "Bir harici disk bağla").font(Theme.section)
                    Text("\(model.onlyNTFS ? "NTFS biçimli" : "Harici") USB ve Thunderbolt diskler burada görünür.").foregroundStyle(.secondary)
                    if !model.disks.isEmpty && model.onlyNTFS {
                        Button("Tüm harici diskleri göster") { model.onlyNTFS = false; model.selected = model.visible.first?.id }
                    }
                }.frame(maxWidth: .infinity).padding(.vertical, Theme.xxl).panel()
            }
            if model.disks.contains(where: { $0.isNTFS && !$0.writable }) {
                HStack(alignment: .top, spacing: Theme.md) {
                    Image(systemName: "info.circle").foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: Theme.sm) {
                        Text("Salt okunur ne demek?").fontWeight(.semibold)
                        Text("Dosyalarını açabilir ve Mac’ine kopyalayabilirsin. Diske dosya eklemek veya düzenlemek için yazmayı etkinleştir.").foregroundStyle(.secondary)
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
                    Text("\(disk.filesystem.uppercased()) · \(capacity(disk.size)) · Harici disk").foregroundStyle(.secondary)
                }
                Spacer()
                Label(disk.status, systemImage: !disk.mounted ? "circle.dashed" : disk.writable ? "checkmark.circle.fill" : "lock.fill")
                    .font(Theme.small).foregroundStyle(disk.writable ? Theme.success : .secondary)
            }
            Divider()
            if let free = disk.free {
                VStack(alignment: .leading, spacing: Theme.sm) {
                    HStack { Text("\(capacity(disk.used ?? 0)) kullanılıyor"); Spacer(); Text("\(capacity(free)) boş") }
                        .font(Theme.small).foregroundStyle(.secondary)
                    ProgressView(value: min(1, max(0, disk.usedFraction))).tint(Theme.accent)
                        .accessibilityLabel("Kullanılan alan").accessibilityValue(capacity(disk.used ?? 0))
                }
            }
            Grid(alignment: .leading, horizontalSpacing: Theme.xl, verticalSpacing: Theme.md) {
                GridRow { Text("Aygıt").foregroundStyle(.secondary); Text("/dev/" + disk.id).textSelection(.enabled) }
                GridRow { Text("Konum").foregroundStyle(.secondary); Text(disk.mountPoint ?? "Bağlı değil").textSelection(.enabled).lineLimit(2) }
                GridRow { Text("Erişim").foregroundStyle(.secondary); Text(disk.status) }
            }.font(Theme.small)
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.md) { diskButtons(disk) }
                VStack(alignment: .leading, spacing: Theme.md) { diskButtons(disk) }
            }.disabled(model.busy || model.scanning || model.stale)
            if disk.isNTFS && !disk.writable && !model.backend.ready {
                Text("Yazma için uyumlu harici bileşenler gerekir. Bu kaynak dağıtımına dahil değildir.")
                    .font(Theme.small).foregroundStyle(Theme.warning)
            }
        }.panel()
    }

    @ViewBuilder private func diskButtons(_ disk: DiskVolume) -> some View {
        if disk.isNTFS && !disk.writable {
            Button { model.action("write", disk: disk) } label: { Label("Yazmayı etkinleştir", systemImage: "pencil") }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.backend.ready || !disk.mediaWritable)
        }
        Button { model.openFinder(disk) } label: { Label("Finder’da aç", systemImage: "folder") }
            .controlSize(.large).disabled(!disk.mounted)
        if disk.mounted {
            Menu {
                Button("Bağlantıyı kes") { model.action("unmount", disk: disk) }
                Button("Güvenle çıkar") { model.action("eject", disk: disk) }
            } label: { Label("Çıkar", systemImage: "eject") }.controlSize(.large).fixedSize()
        } else {
            Button("Salt okunur bağla") { model.action("mount", disk: disk) }.controlSize(.large)
            Button("Güvenle çıkar") { model.action("eject", disk: disk) }.controlSize(.large)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: Theme.xl) {
            Text("Sana ait bir araç.").font(Theme.title)
            VStack(alignment: .leading, spacing: Theme.lg) {
                Text("Görünüm").font(Theme.section)
                Picker("Tema", selection: $appearance) {
                    Text("Sistem").tag("system"); Text("Açık").tag("light"); Text("Koyu").tag("dark")
                }.pickerStyle(.segmented)
            }.panel()
            VStack(alignment: .leading, spacing: Theme.md) {
                Text("macOS disk erişimi").font(Theme.section)
                Text("1. Uygulamayı Uygulamalar klasörüne taşı.\n2. Tam Disk Erişimi bölümünde PlainMount’i ekleyip etkinleştir.\n3. Uygulamayı tamamen kapatıp yeniden aç.").fixedSize(horizontal: false, vertical: true)
                Text("İzin uygulamaya verilir; Terminal veya Codex’in izni bu uygulamanın yerine geçmez.").foregroundStyle(.secondary)
                if !AppBuild.isInstalled() {
                    Label("Önce Uygulamalar klasörüne taşı", systemImage: "folder.badge.plus").foregroundStyle(.primary)
                }
                Text(Bundle.main.bundleURL.path).font(Theme.small).foregroundStyle(.secondary).textSelection(.enabled)
                ViewThatFits(in: .horizontal) {
                    HStack { Button("Uygulamayı Finder’da göster") { model.revealApplication() }; Button("Tam Disk Erişimi ayarlarını aç") { model.openDiskAccessSettings() } }
                    VStack(alignment: .leading) { Button("Uygulamayı Finder’da göster") { model.revealApplication() }; Button("Tam Disk Erişimi ayarlarını aç") { model.openDiskAccessSettings() } }
                }
                Button("Seçilen diske erişimi denetle") { model.checkDiskAccess() }
                    .disabled(model.busy || model.scanning || model.stale || model.selectedDisk == nil || !AppBuild.isInstalled())
                if let result = model.accessCheckResult { Label(result, systemImage: "checkmark.circle").font(Theme.small) }
                if model.needsDiskAccess { Text("macOS erişimi reddetti. İzni verdikten sonra uygulamayı yeniden açın ve erişimi tekrar denetleyin.").font(Theme.small).foregroundStyle(.primary) }
                Text("Denetim dosya yazmaz ve disk bağlantısını değiştirmez. Yönetici izni istenir.").font(Theme.small).foregroundStyle(.secondary)
            }.panel()
            VStack(alignment: .leading, spacing: Theme.md) {
                Text("Yazma desteği").font(Theme.section)
                Label(model.backend.ready ? "NTFS yazma bileşenleri hazır" : "Yazma bileşenleri bulunamadı", systemImage: model.backend.ready ? "checkmark.circle" : "exclamationmark.circle")
                    .foregroundStyle(model.backend.ready ? Theme.success : Theme.warning)
                Text("Yazma için macOS yönetici izni istenir. Parolan uygulamada saklanmaz. Diski bağlamak, otomatik dosya yazma testi yapmaz.")
                    .foregroundStyle(.secondary)
            }.panel()
            VStack(alignment: .leading, spacing: Theme.md) {
                Text("Gizlilik ve tanı").font(Theme.section)
                Text("Uygulama hesap, reklam, telemetri veya otomatik güncelleme servisi kullanmaz. İşlem geçmişi yalnızca bu oturumda tutulur.").foregroundStyle(.secondary)
                Button("Tanı dosyasını kaydet…") { model.exportDiagnostics() }.disabled(model.busy)
                Text("Tanı dosyası disk adlarını ve yerel yolları içerir; yalnızca seçtiğin konuma kaydedilir.").font(Theme.small).foregroundStyle(.secondary)
            }.panel()
            Text("PlainMount \(AppBuild.version) · macOS 14+ · Kişisel kullanım\nHarici yazma bileşenleri bu kaynak dağıtımına dahil değildir.").font(Theme.small).foregroundStyle(.secondary)
        }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: Theme.lg) {
            Text("Bu oturumda.").font(Theme.title)
            Text("Disk işlemlerinin sonuçları burada görünür. Uygulama kapanınca geçmiş temizlenir.").foregroundStyle(.secondary)
            if model.activities.isEmpty {
                Label("Henüz disk işlemi yapılmadı.", systemImage: "clock").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).panel()
            }
            ForEach(model.activities) { item in
                HStack(alignment: .top, spacing: Theme.md) {
                    Image(systemName: item.failed ? "exclamationmark.circle" : "checkmark.circle")
                        .foregroundStyle(item.failed ? Theme.danger : Theme.success)
                    VStack(alignment: .leading, spacing: Theme.sm) {
                        Text(item.message).textSelection(.enabled)
                        Text(item.date.formatted(date: .omitted, time: .standard)).font(Theme.small).foregroundStyle(.secondary)
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
                    DisclosureGroup("Teknik ayrıntılar") { Text(details).font(Theme.small).textSelection(.enabled) }
                }
            }
            Spacer()
            Button { model.error = nil; model.errorDetails = nil } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Hata mesajını kapat")
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
            HStack { Spacer(); Button("Vazgeç", action: cancel).keyboardShortcut(.cancelAction); Button(action.button, action: confirm).buttonStyle(.borderedProminent) }
        }.padding(Theme.xl).frame(width: Theme.defaultWidth / 2)
    }
}
