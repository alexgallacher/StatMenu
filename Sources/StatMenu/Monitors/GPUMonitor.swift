import Foundation
import IOKit

final class GPUMonitor {
    /// The accelerator and its fixed details are looked up once; each sample then reads only the
    /// performance statistics instead of copying the service's whole property dictionary.
    private var service: io_registry_entry_t = 0
    private var name = "GPU"
    private var cores: Int?

    deinit { if service != 0 { IOObjectRelease(service) } }

    func sample() -> GPUStats {
        var stats = GPUStats()
        if service == 0 { findService() }
        guard service != 0,
              let perf = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else {
            // The accelerator can be replaced (e.g. after a GPU restart); look it up again next time.
            if service != 0 { IOObjectRelease(service); service = 0 }
            return stats
        }
        stats.available = true
        stats.utilization = (perf.number("Device Utilization %")?.doubleValue ?? 0) / 100
        stats.renderer = perf.number("Renderer Utilization %").map { $0.doubleValue / 100 }
        stats.tiler = perf.number("Tiler Utilization %").map { $0.doubleValue / 100 }
        stats.memoryUsed = (perf.number("In use system memory") ?? perf.number("vramUsedBytes"))?.uint64Value
        stats.name = name
        stats.cores = cores
        return stats
    }

    /// Finds the first accelerator that publishes performance statistics, as the full scan used to.
    private func findService() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() != nil {
                service = entry
                let model = IORegistryEntryCreateCFProperty(entry, "model" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
                if let model = model as? String {
                    name = model
                } else if let data = model as? Data, let model = String(data: data, encoding: .utf8) {
                    name = model.trimmingCharacters(in: .controlCharacters)
                }
                cores = (IORegistryEntryCreateCFProperty(entry, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? NSNumber)?.intValue
                return
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
    }
}
