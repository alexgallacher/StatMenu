import Darwin
import Foundation

final class MemoryMonitor {
    private let total = UInt64(sysctlInt("hw.memsize") ?? 0)
    private let pageSize = UInt64(sysctlInt("hw.pagesize") ?? 16384)
    private var previous: (time: TimeInterval, pageins: UInt64, pageouts: UInt64, swapins: UInt64, swapouts: UInt64)?

    func sample() -> MemoryStats {
        var result = MemoryStats()
        result.total = total

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let internalPages = UInt64(stats.internal_page_count)
            let purgeable = UInt64(stats.purgeable_count)
            let external = UInt64(stats.external_page_count)
            result.app = (internalPages - min(purgeable, internalPages)) * pageSize
            result.wired = UInt64(stats.wire_count) * pageSize
            result.compressed = UInt64(stats.compressor_page_count) * pageSize
            result.cached = (external + purgeable) * pageSize

            let now = ProcessInfo.processInfo.systemUptime
            let current = (now, UInt64(stats.pageins), UInt64(stats.pageouts), UInt64(stats.swapins), UInt64(stats.swapouts))
            if let p = previous, now > p.time {
                let dt = now - p.time
                func rate(_ a: UInt64, _ b: UInt64) -> Double { a >= b ? Double(a - b) * Double(pageSize) / dt : 0 }
                result.pageInRate = rate(current.1, p.pageins)
                result.pageOutRate = rate(current.2, p.pageouts)
                result.swapInRate = rate(current.3, p.swapins)
                result.swapOutRate = rate(current.4, p.swapouts)
            }
            previous = current
        }

        if let level = sysctlInt("kern.memorystatus_level") {
            result.pressure = Double(100 - min(max(level, 0), 100)) / 100
        }
        result.pressureLevel = sysctlInt("kern.memorystatus_vm_pressure_level") ?? 1

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            result.swapUsed = swap.xsu_used
            result.swapTotal = swap.xsu_total
        }
        return result
    }
}
