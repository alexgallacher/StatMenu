import Foundation
import Observation

/// Observable, main-thread model that every view renders from.
@Observable
final class SystemStore {
    var cpu = CPUStats()
    var cpuUser = History()
    var cpuSystem = History()

    var gpu = GPUStats()
    var gpuHistory = History()

    var memory = MemoryStats()
    var disk = DiskStats()
    var network = NetworkStats()
    var battery = BatteryStats()
    var sensors = SensorStats()

    /// History for every individual value shown in the dropdowns, keyed by `SeriesKey`, for hover graphs.
    /// Updated in place under a single observation change per tick, so the ~150 buffers aren't copied.
    var series: [String: History] {
        access(keyPath: \.series)
        return seriesStorage
    }
    @ObservationIgnored private var seriesStorage: [String: History] = [:]

    /// Minute / ten-minute averages for the longer chart ranges. Not observed directly; views depend on
    /// `longTermVersion`, which changes once per update.
    @ObservationIgnored let longTerm = LongTermStore()
    private(set) var longTermVersion = 0

    /// Uptime of the previous system power reading, for integrating power into energy. Uptime stops while
    /// the Mac sleeps, so sleep isn't counted.
    @ObservationIgnored private var lastPowerTime: TimeInterval?

    @ObservationIgnored let dataUsage = DataUsageStore()
    private(set) var dataUsageVersion = 0

    var topCPU: [ProcessEntry] = []
    var topDisk: [DiskProcess] = []
    var topMemory: [ProcessEntry] = []

    @ObservationIgnored let chipName = sysctlString("machdep.cpu.brand_string") ?? "Processor"
    @ObservationIgnored let bootDate = systemBootDate()

    func apply(_ s: Snapshot) {
        cpu = s.cpu
        cpuUser.append(s.cpu.user)
        cpuSystem.append(s.cpu.system)

        gpu = s.gpu
        gpuHistory.append(s.gpu.utilization)

        memory = s.memory
        disk = s.disk
        network = s.network
        battery = s.battery
        sensors = s.sensors

        withMutation(keyPath: \.series) { recordSeries(s) }

        if let top = s.topCPU { topCPU = top }
        if let top = s.topMemory { topMemory = top }
        if let top = s.topDisk { topDisk = top }
        if s.network.deltaIn > 0 || s.network.deltaOut > 0 {
            dataUsage.add(received: s.network.deltaIn, sent: s.network.deltaOut)
            dataUsageVersion &+= 1
        }
    }

    func usageToday() -> (received: UInt64, sent: UInt64) { _ = dataUsageVersion; return dataUsage.today() }
    func usageMonth() -> (received: UInt64, sent: UInt64) { _ = dataUsageVersion; return dataUsage.month() }

    /// Chart columns for `key` over `range`: the raw recent samples, or long-term averages.
    func columns(_ key: String, _ range: HistoryRange) -> [Double?] {
        if range == .recent {
            let recent = (series[key] ?? History()).recent(HistoryRange.columns)
            return Array(repeating: nil, count: HistoryRange.columns - recent.count) + recent.map { Optional($0) }
        }
        _ = longTermVersion
        return longTerm.columns(key, range, now: Date().timeIntervalSince1970)
    }

    /// Energy the whole computer used over `range`, in watt-hours, counted while StatMenu was running.
    /// Nil when there's no system power reading for that range.
    func energyUsed(_ range: HistoryRange) -> Double? {
        if range == .recent {
            let recent = (series["energy.system"] ?? History()).recent(HistoryRange.columns)
            return recent.isEmpty ? nil : recent.reduce(0, +)
        }
        _ = longTermVersion
        return longTerm.total("energy.system", range, now: Date().timeIntervalSince1970)
    }

    private func recordSeries(_ s: Snapshot) {
        let now = Date().timeIntervalSince1970
        func record(_ key: String, _ value: Double?) {
            guard let value else { return }
            seriesStorage[key, default: History()].append(value)
            longTerm.add(key, value, at: now)
        }
        record("cpu.total", s.cpu.total)
        record("cpu.user", s.cpu.user)
        record("cpu.system", s.cpu.system)
        record("cpu.idle", s.cpu.idle)
        record("cpu.load", s.cpu.loadAverage.first)
        for (i, load) in s.cpu.cores.enumerated() { record("cpu.core.\(i)", load) }
        for c in s.cpu.clusters { record("clock.\(c.name)", c.isIdle ? 0 : c.mhz) }
        if let g = s.gpu.clock { record("clock.GPU", g.isIdle ? 0 : g.mhz) }

        record("gpu.util", s.gpu.utilization)
        record("gpu.renderer", s.gpu.renderer)
        record("gpu.tiler", s.gpu.tiler)
        record("gpu.memory", s.gpu.memoryUsed.map { Double($0) })

        let m = s.memory
        record("mem.used", Double(m.used))
        record("mem.app", Double(m.app))
        record("mem.wired", Double(m.wired))
        record("mem.compressed", Double(m.compressed))
        record("mem.cached", Double(m.cached))
        record("mem.free", Double(m.free))
        record("mem.pressure", m.pressure)
        record("mem.swap", Double(m.swapUsed))

        record("mem.pagein", m.pageInRate)
        record("mem.pageout", m.pageOutRate)
        record("mem.swapin", m.swapInRate)
        record("mem.swapout", m.swapOutRate)
        record("power.cpu", s.cpu.power)
        record("power.gpu", s.gpu.power)
        for p in s.sensors.powerBreakdown { record("power.part.\(p.name)", p.watts) }
        record("power.adapter", s.sensors.adapterInput)
        for d in s.disk.devices {
            record("disk.\(d.id).read", d.readRate)
            record("disk.\(d.id).write", d.writeRate)
        }
        if let w = s.network.wifi {
            record("wifi.rssi", Double(w.rssi))
            record("wifi.snr", Double(w.snr))
            record("wifi.rate", w.transmitRate)
        }
        record("disk.read", s.disk.readRate)
        record("disk.write", s.disk.writeRate)
        record("net.down", s.network.downRate)
        record("net.up", s.network.upRate)

        record("temp.cpu", s.sensors.cpu)
        record("temp.gpu", s.sensors.gpu)
        record("temp.ssd", s.sensors.ssd)
        record("temp.battery", s.sensors.battery ?? s.battery.temperature)
        for r in s.sensors.readings { record("temp.\(r.name)", r.value) }
        for f in s.sensors.fans { record("fan.\(f.index)", f.rpm) }
        record("power.system", s.sensors.systemPower)
        // Watt-hours since the previous reading. Gaps longer than a minute (e.g. the sampler stalled) are
        // skipped rather than guessed at.
        let uptime = ProcessInfo.processInfo.systemUptime
        if let watts = s.sensors.systemPower {
            if let last = lastPowerTime, uptime > last, uptime - last <= 60 {
                record("energy.system", watts * (uptime - last) / 3_600)
            }
            lastPowerTime = uptime
        } else {
            lastPowerTime = nil
        }

        record("battery.percent", s.battery.present ? s.battery.percent : nil)
        record("battery.power", s.battery.power)
        record("battery.voltage", s.battery.voltage)
        longTermVersion &+= 1
    }
}
