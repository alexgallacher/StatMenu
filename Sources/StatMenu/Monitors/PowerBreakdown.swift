import Foundation

/// Groups Apple Silicon "Energy Model" channels into a system power breakdown.
///
/// Only channels whose meaning is established get a line (`namedChannels`). Undocumented channels are
/// not listed; their (small) share ends up in "Rest of system", which is the SMC total minus the lines above.
enum PowerBreakdown {
    /// Channel-name prefix → display name, in display order after CPU and GPU.
    private static let namedChannels: [(prefix: String, name: String)] = [
        ("ANE", "Neural Engine"),
        ("DRAM", "Memory"),
        ("DCS", "Memory controller"),
        ("AMCC", "Memory fabric"),
        ("AVE", "Video encoder"),
        ("ISP", "Camera (ISP)"),
    ]

    static func make(channels: [String: Double], cpu: Double?, gpu: Double?, system: Double?) -> [PowerComponent] {
        guard !channels.isEmpty else { return [] }
        var parts: [PowerComponent] = []
        if let cpu { parts.append(PowerComponent(name: "CPU", watts: cpu)) }
        if let gpu { parts.append(PowerComponent(name: "GPU", watts: gpu)) }
        for (prefix, name) in namedChannels {
            let watts = channels.filter { $0.key.hasPrefix(prefix) }.values.reduce(0, +)
            parts.append(PowerComponent(name: name, watts: watts))
        }
        if let system {
            let listed = parts.reduce(0) { $0 + $1.watts }
            parts.append(PowerComponent(name: "Rest of system", watts: max(system - listed, 0)))
        }
        return parts
    }
}
