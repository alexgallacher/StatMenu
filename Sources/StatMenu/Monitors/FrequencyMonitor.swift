import CStats
import Foundation

/// CPU cluster and GPU clock speeds from IOReport performance-state residency (Apple Silicon only).
final class FrequencyMonitor {
    private var buffer = [freq_reading](repeating: freq_reading(), count: 16)
    private var lastTime = ProcessInfo.processInfo.systemUptime
    /// Recent (seconds, cpu joules, gpu joules) samples. The energy counters only advance every couple of
    /// seconds, so power is averaged over a short rolling window instead of per tick.
    private var window: [(dt: Double, cpu: Double, gpu: Double)] = []
    private let windowSeconds = 6.0
    private var energyBuffer = [energy_reading](repeating: energy_reading(), count: 512)
    /// Per-channel energy for the same rolling window.
    private var channelWindow: [[String: Double]] = []

    func sample() -> (clusters: [ClockReading], gpu: ClockReading?, cpuPower: Double?, gpuPower: Double?,
                      channelPower: [String: Double]) {
        var cpuJ = -1.0, gpuJ = -1.0
        let count = Int(freq_sample(&buffer, Int32(buffer.count), &cpuJ, &gpuJ))
        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - lastTime
        lastTime = now
        var cpuPower: Double?, gpuPower: Double?
        var channelPower: [String: Double] = [:]
        if cpuJ >= 0 || gpuJ >= 0, dt > 0 {
            window.append((dt, max(cpuJ, 0), max(gpuJ, 0)))
            let n = Int(energy_channels(&energyBuffer, Int32(energyBuffer.count)))
            var channels: [String: Double] = [:]
            for e in energyBuffer.prefix(n) {
                let name = withUnsafeBytes(of: e.name) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
                channels[name, default: 0] += e.joules
            }
            channelWindow.append(channels)
            while window.count > 1, window.dropFirst().reduce(0, { $0 + $1.dt }) >= windowSeconds {
                window.removeFirst()
                channelWindow.removeFirst()
            }
            let span = window.reduce(0) { $0 + $1.dt }
            if span > 0 {
                cpuPower = cpuJ >= 0 ? window.reduce(0) { $0 + $1.cpu } / span : nil
                gpuPower = gpuJ >= 0 ? window.reduce(0) { $0 + $1.gpu } / span : nil
                for sample in channelWindow {
                    for (name, joules) in sample { channelPower[name, default: 0] += joules / span }
                }
            }
        }
        var clusters: [ClockReading] = []
        var gpu: ClockReading?
        var performanceIndex = 0
        let performanceClusters = buffer.prefix(count).filter { $0.kind == 1 }.count
        for r in buffer.prefix(count) {
            let name: String
            switch r.kind {
            case 0: name = "Efficiency"
            case 1:
                performanceIndex += 1
                name = performanceClusters > 1 ? "Performance \(performanceIndex)" : "Performance"
            default: name = "GPU"
            }
            let reading = ClockReading(name: name, mhz: r.mhz, maxMHz: r.max_mhz, active: r.active)
            if r.kind == 2 { gpu = reading } else { clusters.append(reading) }
        }
        return (clusters, gpu, cpuPower, gpuPower, channelPower)
    }
}
