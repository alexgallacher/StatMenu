import Darwin
import Foundation
import IOKit

final class CPUMonitor {
    private var previous: [[UInt32]] = []
    private let performanceCores = sysctlInt("hw.perflevel0.logicalcpu") ?? 0
    private let efficiencyCores = sysctlInt("hw.perflevel1.logicalcpu") ?? 0
    private lazy var coreIsEfficiency = Self.readCoreTypes()

    func sample() -> CPUStats {
        var stats = CPUStats()
        stats.performanceCores = performanceCores
        stats.efficiencyCores = efficiencyCores
        stats.coreIsEfficiency = coreIsEfficiency
        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)
        stats.loadAverage = loads

        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &infoArray, &infoCount) == KERN_SUCCESS,
              let infoArray else { return stats }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: infoArray)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        var current: [[UInt32]] = []
        for i in 0..<Int(cpuCount) {
            let base = i * Int(CPU_STATE_MAX)
            current.append([
                UInt32(bitPattern: infoArray[base + Int(CPU_STATE_USER)]),
                UInt32(bitPattern: infoArray[base + Int(CPU_STATE_SYSTEM)]),
                UInt32(bitPattern: infoArray[base + Int(CPU_STATE_IDLE)]),
                UInt32(bitPattern: infoArray[base + Int(CPU_STATE_NICE)]),
            ])
        }
        defer { previous = current }
        guard previous.count == current.count else {
            stats.cores = Array(repeating: 0, count: current.count)
            return stats
        }

        var totalUser = 0.0, totalSystem = 0.0, totalAll = 0.0
        for (now, before) in zip(current, previous) {
            let user = Double(now[0] &- before[0]) + Double(now[3] &- before[3])
            let system = Double(now[1] &- before[1])
            let idle = Double(now[2] &- before[2])
            let total = user + system + idle
            stats.cores.append(total > 0 ? (user + system) / total : 0)
            totalUser += user
            totalSystem += system
            totalAll += total
        }
        if totalAll > 0 {
            stats.user = totalUser / totalAll
            stats.system = totalSystem / totalAll
        }
        return stats
    }

    /// Reads each core's cluster type ("E"/"P") from the device tree, indexed by logical CPU id,
    /// so core classification is right on every Apple Silicon model rather than assumed by position.
    private static func readCoreTypes() -> [Bool] {
        let cpus = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        guard cpus != 0 else { return [] }
        defer { IOObjectRelease(cpus) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(cpus, kIODeviceTreePlane, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var types: [Int: Bool] = [:]
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            let rawID = IORegistryEntryCreateCFProperty(entry, "logical-cpu-id" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue()
            let id: UInt32? = (rawID as? NSNumber)?.uint32Value
                ?? (rawID as? Data).flatMap { $0.count >= 4 ? $0.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } : nil }
            let type = (IORegistryEntryCreateCFProperty(entry, "cluster-type" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Data).flatMap { $0.first }
            if let id, let type { types[Int(id)] = type == UInt8(ascii: "E") }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        guard !types.isEmpty else { return [] }
        return (0...(types.keys.max() ?? 0)).map { types[$0] ?? false }
    }
}
