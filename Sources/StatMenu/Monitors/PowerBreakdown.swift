import Foundation

/// Groups Apple Silicon "Energy Model" channels into a system power breakdown.
///
/// Only channels with established meanings get names (CPU, GPU, Neural Engine, DRAM). Everything else on
/// the chip is summed into "Rest of chip", keeping the hardware channel names for the hover detail.
/// "Rest of system" is the SMC total minus the chip, i.e. everything outside the SoC.
enum PowerBreakdown {
    static func make(channels: [String: Double], cpu: Double?, gpu: Double?, system: Double?) -> [PowerComponent] {
        guard !channels.isEmpty else { return [] }
        var neural = 0.0, dram = 0.0
        var other: [(String, Double)] = []
        for (name, watts) in channels where watts > 0 {
            if isCPUChannel(name) || name.hasPrefix("GPU") { continue } // covered by the CPU/GPU aggregates
            if name.hasPrefix("ANE") { neural += watts } else if name.hasPrefix("DRAM") { dram += watts } else {
                other.append((name, watts))
            }
        }
        var parts: [PowerComponent] = []
        if let cpu { parts.append(PowerComponent(name: "CPU", watts: cpu)) }
        if let gpu { parts.append(PowerComponent(name: "GPU", watts: gpu)) }
        parts.append(PowerComponent(name: "Neural Engine", watts: neural))
        parts.append(PowerComponent(name: "Memory", watts: dram))
        let otherTotal = other.reduce(0) { $0 + $1.1 }
        parts.append(PowerComponent(name: "Rest of chip", watts: otherTotal,
                                    parts: other.sorted { $0.1 > $1.1 }))
        if let system {
            let chip = parts.reduce(0) { $0 + $1.watts }
            parts.append(PowerComponent(name: "Rest of system", watts: max(system - chip, 0)))
        }
        return parts
    }

    /// Per-core, per-cluster and aggregate CPU channels (all folded into "CPU Energy").
    private static func isCPUChannel(_ name: String) -> Bool {
        name.contains("CPU") || name.contains("CPM") || name.contains("DTL")
    }
}
