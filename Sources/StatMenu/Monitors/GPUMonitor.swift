import Foundation
import IOKit

final class GPUMonitor {
    func sample() -> GPUStats {
        var stats = GPUStats()
        forEachIOService("IOAccelerator") { props in
            guard let perf = props["PerformanceStatistics"] as? [String: Any] else { return true }
            stats.available = true
            stats.utilization = (perf.number("Device Utilization %")?.doubleValue ?? 0) / 100
            stats.renderer = perf.number("Renderer Utilization %").map { $0.doubleValue / 100 }
            stats.tiler = perf.number("Tiler Utilization %").map { $0.doubleValue / 100 }
            stats.memoryUsed = (perf.number("In use system memory") ?? perf.number("vramUsedBytes"))?.uint64Value
            if let model = props["model"] as? String {
                stats.name = model
            } else if let data = props["model"] as? Data, let model = String(data: data, encoding: .utf8) {
                stats.name = model.trimmingCharacters(in: .controlCharacters)
            }
            stats.cores = props.number("gpu-core-count")?.intValue
            return false
        }
        return stats
    }
}
