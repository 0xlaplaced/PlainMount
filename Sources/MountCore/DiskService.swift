import Foundation
import DiskArbitration
import IOKit
import Darwin

public struct DiskIdentity: Codable, Equatable, Sendable {
    public let device: String
    public let parent: String
    public let size: Int64
    public let name: String
    public let treePath: String
    public let offset: Int64
    public let uuid: String
}

public struct DiskVolume: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let parent: String
    public let name: String
    public let filesystem: String
    public let size: Int64
    public let free: Int64?
    public let mountPoint: String?
    public let writable: Bool
    public let mediaWritable: Bool
    public let identity: DiskIdentity
    public var isNTFS: Bool { filesystem.lowercased() == "ntfs" }
    public var mounted: Bool { mountPoint != nil }
    public var status: String { !mounted ? "Bağlı değil" : writable ? "Okuma ve yazma" : "Salt okunur" }
    public var used: Int64? { free.map { max(0, size - $0) } }
    public var usedFraction: Double { size > 0 ? Double(used ?? 0) / Double(size) : 0 }
}

public enum DiskService {
    public static func validDevice(_ id: String, partition: Bool = false) -> Bool {
        let pattern = partition ? "\\Adisk[0-9]+s[0-9]+\\z" : "\\Adisk[0-9]+(?:s[0-9]+)*\\z"
        return id.range(of: pattern, options: .regularExpression) != nil
    }

    public static func plist(_ data: Data) throws -> [String: Any] {
        guard let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw ToolError.message("macOS disk bilgisi okunamadı.")
        }
        return value
    }

    public static func info(_ id: String) throws -> [String: Any] {
        guard validDevice(id) else { throw ToolError.message("Geçersiz disk kimliği.") }
        // Metadata only: diskutil info can block opening a USB whole disk on macOS 27.
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, id),
              let raw = DADiskCopyDescription(disk) else { throw ToolError.message("Disk bilgisi alınamadı: \(id)") }
        let description = raw as NSDictionary
        let parent = DADiskCopyWholeDisk(disk).flatMap { whole in DADiskGetBSDName(whole).map { String(cString: $0) } } ?? id
        let path = description[kDADiskDescriptionVolumePathKey] as? URL
        var result: [String: Any] = [
            "DeviceIdentifier": id, "ParentWholeDisk": parent,
            "WholeDisk": description[kDADiskDescriptionMediaWholeKey] as? Bool ?? false,
            "VolumeName": description[kDADiskDescriptionVolumeNameKey] as? String ?? id,
            "FilesystemType": description[kDADiskDescriptionVolumeKindKey] as? String ?? "",
            "VolumeSize": description[kDADiskDescriptionMediaSizeKey] as? NSNumber ?? 0,
            "WritableMedia": description[kDADiskDescriptionMediaWritableKey] as? Bool ?? false,
            "WritableVolume": false,
            "DeviceTreePath": description[kDADiskDescriptionDevicePathKey] as? String ?? ""
        ]
        if let internalDevice = description[kDADiskDescriptionDeviceInternalKey] as? Bool { result["Internal"] = internalDevice }
        if let path {
            result["MountPoint"] = path.path
            if let values = try? path.resourceValues(forKeys: [.volumeIsReadOnlyKey, .volumeAvailableCapacityKey]) {
                result["WritableVolume"] = values.volumeIsReadOnly == false
                if let free = values.volumeAvailableCapacity { result["FreeSpace"] = free }
            }
        }
        if let uuid = description[kDADiskDescriptionVolumeUUIDKey] ?? description[kDADiskDescriptionMediaUUIDKey], CFGetTypeID(uuid as CFTypeRef) == CFUUIDGetTypeID() {
            result["VolumeUUID"] = CFUUIDCreateString(kCFAllocatorDefault, unsafeBitCast(uuid as CFTypeRef, to: CFUUID.self)) as String
        }
        let media = DADiskCopyIOMedia(disk)
        if media != 0 {
            if let base = IORegistryEntryCreateCFProperty(media, "Base" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber {
                result["PartitionMapPartitionOffset"] = base
            }
            IOObjectRelease(media)
        }
        return result
    }

    public static func candidateIDs(_ list: [String: Any]) -> [String] {
        var result: [String] = []
        func visit(_ entry: [String: Any]) {
            if let id = entry["DeviceIdentifier"] as? String, validDevice(id), entry["Content"] as? String != "EFI" {
                result.append(id)
            }
            for child in entry["Partitions"] as? [[String: Any]] ?? [] { visit(child) }
            for child in entry["APFSVolumes"] as? [[String: Any]] ?? [] { visit(child) }
        }
        for disk in list["AllDisksAndPartitions"] as? [[String: Any]] ?? [] { visit(disk) }
        return Array(Set(result)).sorted()
    }

    public static func candidateRecords(_ list: [String: Any]) -> [String: [String: Any]] {
        var records: [String: [String: Any]] = [:]
        func visit(_ row: [String: Any]) {
            if let id = row["DeviceIdentifier"] as? String, validDevice(id) { records[id] = row }
            for child in row["Partitions"] as? [[String: Any]] ?? [] { visit(child) }
            for child in row["APFSVolumes"] as? [[String: Any]] ?? [] { visit(child) }
        }
        for row in list["AllDisksAndPartitions"] as? [[String: Any]] ?? [] { visit(row) }
        return records
    }

    public static func completeMetadata(_ info: [String: Any], record: [String: Any]) -> [String: Any] {
        var result = info
        // DA can temporarily clear VolumeKind during/after an unsuccessful FSKit unmount.
        if (result["FilesystemType"] as? String ?? "").isEmpty,
           record["Content"] as? String == "Windows_NTFS" { result["FilesystemType"] = "ntfs" }
        if let id = result["DeviceIdentifier"] as? String,
           (result["VolumeName"] as? String ?? id) == id,
           let name = record["VolumeName"] as? String, !name.isEmpty { result["VolumeName"] = name }
        // Mount paths/writability always come from current metadata or kernel mounts, never cached list fields.
        return result
    }

    public static func validateSnapshot(previous: [DiskVolume], current: [DiskVolume], mounts: String) throws {
        for old in previous where !current.contains(where: { $0.id == old.id }) {
            let stillMounted = mounts.components(separatedBy: .newlines).contains {
                $0.hasPrefix("/dev/" + old.id + " on ") || $0.contains(" on " + personalMountPoint(old.id) + " (")
            }
            if stillMounted {
                throw ToolError.message("\(old.name) hâlâ bağlı, ancak güncel disk bilgisi alınamadı. Son doğrulanan liste korunuyor; Yenile ile tekrar deneyin.")
            }
        }
    }

    public static func parse(_ info: [String: Any], allowedParents: Set<String>) -> DiskVolume? {
        guard let id = info["DeviceIdentifier"] as? String, validDevice(id),
              info["Internal"] as? Bool == false,
              info["WholeDisk"] as? Bool == false || info["FilesystemType"] != nil,
              let parent = info["ParentWholeDisk"] as? String ?? (info["WholeDisk"] as? Bool == true ? id : nil),
              validDevice(parent), allowedParents.contains(parent),
              let fs = info["FilesystemType"] as? String, !fs.isEmpty else { return nil }
        let size = (info["VolumeSize"] as? NSNumber ?? info["TotalSize"] as? NSNumber ?? info["Size"] as? NSNumber)?.int64Value ?? 0
        let name = (info["VolumeName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
        let mp = (info["MountPoint"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let identity = DiskIdentity(device: id, parent: parent, size: size, name: name,
                                    treePath: info["DeviceTreePath"] as? String ?? "",
                                    offset: (info["PartitionMapPartitionOffset"] as? NSNumber)?.int64Value ?? 0,
                                    uuid: info["VolumeUUID"] as? String ?? info["DiskUUID"] as? String ?? "")
        return DiskVolume(id: id, parent: parent, name: name, filesystem: fs, size: size,
                          free: (info["FreeSpace"] as? NSNumber ?? info["VolumeFreeSpace"] as? NSNumber)?.int64Value,
                          mountPoint: mp, writable: info["WritableVolume"] as? Bool ?? info["Writable"] as? Bool ?? false,
                          mediaWritable: info["WritableMedia"] as? Bool ?? false, identity: identity)
    }

    public static func scan(previous: [DiskVolume] = []) throws -> [DiskVolume] {
        let list = try plist(Runner.checked("/usr/sbin/diskutil", ["list", "-plist", "external", "physical"]))
        let allowed = Set(list["WholeDisks"] as? [String] ?? [])
        let records = candidateRecords(list)
        var result: [DiskVolume] = []
        for id in candidateIDs(list) {
            let details = completeMetadata(try info(id), record: records[id] ?? [:])
            if let disk = parse(details, allowedParents: allowed) { result.append(disk) }
        }
        let mounts = String(data: try Runner.checked("/sbin/mount", []), encoding: .utf8) ?? ""
        try validateSnapshot(previous: previous, current: result, mounts: mounts)
        return result.map { original in
            let point = personalMountPoint(original.id)
            guard let writable = personalMountState(mounts, point: point) else { return original }
            let free = (try? FileManager.default.attributesOfFileSystem(forPath: point)[.systemFreeSize] as? NSNumber)?.int64Value
            return DiskVolume(id: original.id, parent: original.parent, name: original.name, filesystem: original.filesystem,
                              size: original.size, free: free ?? original.free, mountPoint: point, writable: writable,
                              mediaWritable: original.mediaWritable, identity: original.identity)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func personalMountPoint(_ id: String) -> String { "/Volumes/PlainMount-" + id }

    public static func personalMountState(_ rows: String, point: String) -> Bool? {
        guard let row = rows.components(separatedBy: .newlines).first(where: { $0.contains(" on " + point + " (") }),
              let start = row.range(of: " on " + point + " (") else { return nil }
        let options = row[start.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: ") "))
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard options.contains("nfs") || options.contains("fuse-t") else { return nil }
        return !options.contains("read-only") && !options.contains("ro")
    }

    public static func revalidate(_ original: DiskVolume) throws -> DiskVolume {
        guard let current = try scan().first(where: { $0.id == original.id }), current.identity == original.identity else {
            throw ToolError.message("Disk değişti veya çıkarıldı. Listeyi yenileyip diski yeniden seçin.")
        }
        return current
    }

    public static func perform(_ action: String, on original: DiskVolume) throws {
        let current = try revalidate(original)
        switch action {
        case "mount": _ = try Runner.checked("/usr/sbin/diskutil", ["mount", "readOnly", current.id])
        case "unmount":
            if current.mountPoint == personalMountPoint(current.id) { try WriteMount.requestUnmount(current) }
            else { _ = try Runner.checked("/usr/sbin/diskutil", ["unmount", current.id]) }
        case "eject":
            for sibling in try scan().filter({ $0.parent == current.parent && $0.mountPoint == personalMountPoint($0.id) }) {
                try WriteMount.requestUnmount(sibling)
            }
            _ = try Runner.checked("/usr/sbin/diskutil", ["eject", current.parent])
        default: throw ToolError.message("Desteklenmeyen disk işlemi.")
        }
    }
}
