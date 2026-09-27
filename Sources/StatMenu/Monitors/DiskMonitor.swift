import Foundation
import IOKit

final class DiskMonitor {
    private var lastRead: UInt64?
    private var lastWrite: UInt64?
    private var lastTime: TimeInterval = 0
    private var volumes: [VolumeInfo] = []
    private var volumeRefreshCountdown = 0
    private var previousPerDisk: [String: (read: UInt64, write: UInt64)] = [:]
    /// Disk chosen in the Disks tab (BSD name); nil means every physical disk.
    var selected: String? { didSet { if selected != oldValue { lastRead = nil; lastWrite = nil } } }

    /// `detailed` (a dropdown is open) re-reads volume capacity every call instead of every 15th.
    func sample(detailed: Bool = false) -> DiskStats {
        var stats = DiskStats()

        if detailed || volumeRefreshCountdown <= 0 {
            volumes = Self.readVolumes()
            volumeRefreshCountdown = 15
        }
        volumeRefreshCountdown -= 1
        stats.volumes = volumes

        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - lastTime
        var read: UInt64 = 0, write: UInt64 = 0
        var perDisk: [String: (read: UInt64, write: UInt64)] = [:]
        let disks = Self.readDisks()
        let chosen = selected.flatMap { bsd in disks.contains { $0.bsd == bsd } ? bsd : nil }
        stats.isAutomatic = chosen == nil
        for disk in disks {
            let included = chosen.map { $0 == disk.bsd } ?? !disk.isVirtual
            perDisk[disk.bsd] = (disk.read, disk.write)
            var readRate = 0.0, writeRate = 0.0
            if let p = previousPerDisk[disk.bsd], dt > 0, lastRead != nil {
                readRate = disk.read >= p.read ? Double(disk.read - p.read) / dt : 0
                writeRate = disk.write >= p.write ? Double(disk.write - p.write) / dt : 0
            }
            let device = DiskDevice(id: disk.bsd, name: disk.name, location: disk.location, isVirtual: disk.isVirtual,
                                    readRate: readRate, writeRate: writeRate)
            stats.allDevices.append(device)
            guard included else { continue }
            stats.devices.append(device)
            read += disk.read
            write += disk.write
        }
        previousPerDisk = perDisk
        if let lastRead, let lastWrite, now > lastTime {
            let dt = now - lastTime
            stats.readRate = read >= lastRead ? Double(read - lastRead) / dt : 0
            stats.writeRate = write >= lastWrite ? Double(write - lastWrite) / dt : 0
        }
        lastRead = read
        lastWrite = write
        lastTime = now
        stats.totalRead = read
        stats.totalWritten = write
        return stats
    }

    /// Every block-storage driver with its cumulative byte counters, product name and BSD name.
    private static func readDisks() -> [(bsd: String, name: String, location: String, isVirtual: Bool, read: UInt64, write: UInt64)] {
        var result: [(String, String, String, Bool, UInt64, UInt64)] = []
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var driver = IOIteratorNext(iterator)
        while driver != 0 {
            defer { IOObjectRelease(driver); driver = IOIteratorNext(iterator) }
            guard let stats = IORegistryEntryCreateCFProperty(driver, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else { continue }
            var name = "Disk", location = "Unknown", isVirtual = false, bsd: String?
            var parent: io_registry_entry_t = 0
            if IORegistryEntryGetParentEntry(driver, kIOServicePlane, &parent) == KERN_SUCCESS {
                if let chars = IORegistryEntryCreateCFProperty(parent, "Device Characteristics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any], let product = chars["Product Name"] as? String {
                    name = product.trimmingCharacters(in: .whitespaces)
                }
                if let proto = IORegistryEntryCreateCFProperty(parent, "Protocol Characteristics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any], let loc = proto["Physical Interconnect Location"] as? String {
                    location = loc
                    isVirtual = proto["Physical Interconnect"] as? String == "Virtual Interface"
                }
                IOObjectRelease(parent)
            }
            var child: io_registry_entry_t = 0
            if IORegistryEntryGetChildEntry(driver, kIOServicePlane, &child) == KERN_SUCCESS {
                bsd = IORegistryEntryCreateCFProperty(child, "BSD Name" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? String
                IOObjectRelease(child)
            }
            guard let bsd else { continue }
            result.append((bsd, name, location, isVirtual, stats.number("Bytes (Read)")?.uint64Value ?? 0,
                           stats.number("Bytes (Write)")?.uint64Value ?? 0))
        }
        return result.sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
    }

    private static func readVolumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeIsRootFileSystemKey, .volumeIsBrowsableKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        var result: [VolumeInfo] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsBrowsable ?? true,
                  let total = values.volumeTotalCapacity, total > 0 else { continue }
            let isRoot = values.volumeIsRootFileSystem ?? (url.path == "/")
            var available = Int64(values.volumeAvailableCapacity ?? 0)
            if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 {
                available = important
            }
            result.append(VolumeInfo(path: url.path, name: values.volumeName ?? url.lastPathComponent,
                                     total: UInt64(total), available: UInt64(max(available, 0)), isRoot: isRoot))
        }
        return result.sorted { $0.isRoot && !$1.isRoot }
    }
}
