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

    func setProcessesWanted(_ wanted: Bool) {
        queue.async { [self] in
            wantsProcesses = wanted
            if wanted { tick() }
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
        s.sensors = sensors.sample()
        let clocks = frequency.sample()
        s.cpu.clusters = clocks.clusters
        s.gpu.clock = clocks.gpu
        s.cpu.power = clocks.cpuPower
        s.gpu.power = clocks.gpuPower
        s.sensors.powerBreakdown = PowerBreakdown.make(channels: clocks.channelPower, cpu: clocks.cpuPower,
                                                       gpu: clocks.gpuPower, system: s.sensors.systemPower)
        s.memory = memory.sample()
        s.disk = disk.sample()
        s.network = network.sample()
        s.network.wifi = wifi.sample(primaryInterface: s.network.interface)
        s.battery = battery.sample()
        if wantsProcesses {
            let top = processes.sample()
            s.topCPU = top.cpu
            s.topMemory = top.memory
            s.topDisk = diskProcesses.sample()
        }
        return s
    }
}
