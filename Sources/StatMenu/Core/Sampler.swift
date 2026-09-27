import Foundation

/// Collects a `Snapshot` of every monitor on a background queue and hands it to the main thread.
final class Sampler {
    var onSnapshot: ((Snapshot) -> Void)?

    private let queue = DispatchQueue(label: "StatMenu.sampler", qos: .utility)
    private var timer: DispatchSourceTimer?
    private let cpu = CPUMonitor()
    private let gpu = GPUMonitor()
    private let memory = MemoryMonitor()
    private let disk = DiskMonitor()
    private let network = NetworkMonitor()
    private let battery = BatteryMonitor()
    private let sensors = SensorMonitor()
    private let processes = ProcessMonitor()
    private let frequency = FrequencyMonitor()
    private let diskProcesses = DiskProcessMonitor()
    private let wifi = WiFiMonitor()
    private var wantsProcesses = false
    /// True while a dropdown is open: every value refreshes on every tick instead of on slower schedules.
    private var detailed = false

    func start(interval: TimeInterval) {
        queue.async { [self] in
            timer?.cancel()
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + .milliseconds(300), repeating: interval, leeway: .milliseconds(150))
            t.setEventHandler { [weak self] in self?.tick() }
            timer = t
            t.resume()
        }
    }

    func setDiskSelection(_ bsdName: String?) {
        queue.async { [self] in disk.selected = bsdName }
    }

    func setNetworkInterface(_ bsdName: String?) {
        queue.async { [self] in network.selected = bsdName }
    }

    /// Called when a dropdown opens or closes. `processes` also turns on the process lists.
    func setDropdownOpen(_ open: Bool, processes: Bool = false) {
        queue.async { [self] in
            detailed = open
            wantsProcesses = open && processes
            if open { tick() }
        }
    }

    /// Synchronous sample; used for offscreen preview rendering.
    func sampleNow(includeProcesses: Bool = true) -> Snapshot {
        queue.sync {
            wantsProcesses = includeProcesses
            return collect()
        }
    }

    private func tick() {
        let snapshot = collect()
        DispatchQueue.main.async { [weak self] in self?.onSnapshot?(snapshot) }
    }

    private func collect() -> Snapshot {
        var s = Snapshot()
        s.cpu = cpu.sample()
        s.gpu = gpu.sample()
        s.sensors = sensors.sample(detailed: detailed)
        let clocks = frequency.sample()
        s.cpu.clusters = clocks.clusters
        s.gpu.clock = clocks.gpu
        s.cpu.power = clocks.cpuPower
        s.gpu.power = clocks.gpuPower
        s.sensors.powerBreakdown = PowerBreakdown.make(channels: clocks.channelPower, cpu: clocks.cpuPower,
                                                       gpu: clocks.gpuPower, system: s.sensors.systemPower)
        s.memory = memory.sample()
        s.disk = disk.sample(detailed: detailed)
        s.network = network.sample(detailed: detailed)
        s.network.wifi = wifi.sample(primaryInterface: s.network.interface)
        s.battery = battery.sample(detailed: detailed)
        // The fuel gauge refreshes slowly; use the SMC's live readings where they can be trusted.
        if s.battery.present, !s.battery.onAC, let live = s.sensors.batteryPower {
            s.battery.measuredPower = live
        }
        if let live = s.sensors.batteryVoltage, let gauge = s.battery.voltage, abs(live - gauge) / gauge < 0.05 {
            s.battery.voltage = live   // only when it agrees with the gauge's own reading
        }
        if wantsProcesses {
            let top = processes.sample()
            s.topCPU = top.cpu
            s.topMemory = top.memory
            s.topDisk = diskProcesses.sample()
        }
        return s
    }
}
