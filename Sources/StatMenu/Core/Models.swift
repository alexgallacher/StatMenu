import Foundation

/// Average clock of one CPU cluster (or the GPU) over the last interval.
struct ClockReading: Identifiable {
    let name: String
    let mhz: Double
    let maxMHz: Double
    let active: Double

    var id: String { name }
    var isIdle: Bool { active < 0.005 || mhz <= 0 }
    var fraction: Double { maxMHz > 0 && !isIdle ? min(mhz / maxMHz, 1) : 0 }
}

struct CPUStats {
    var user: Double = 0
    var system: Double = 0
    var cores: [Double] = []
    /// Per logical core, whether it is an efficiency core (from the device tree).
    var coreIsEfficiency: [Bool] = []
    var efficiencyCores = 0
    var performanceCores = 0
    var clusters: [ClockReading] = []
    /// Average CPU power in watts over the last few seconds (Apple Silicon).
    var power: Double?
    var loadAverage: [Double] = [0, 0, 0]

    var total: Double { min(user + system, 1) }
    var idle: Double { max(0, 1 - total) }
}

struct GPUStats {
    var available = false
    var clock: ClockReading?
    var power: Double?
    var utilization: Double = 0
    var renderer: Double?
    var tiler: Double?
    var memoryUsed: UInt64?
    var name = "GPU"
    var cores: Int?
}

struct MemoryStats {
    var total: UInt64 = 0
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var pressure: Double = 0
    var pressureLevel = 1
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    /// Bytes per second moved by paging and swapping.
    var pageInRate: Double = 0
    var pageOutRate: Double = 0
    var swapInRate: Double = 0
    var swapOutRate: Double = 0

    var used: UInt64 { app + wired + compressed }
    var free: UInt64 { total > used + cached ? total - used - cached : 0 }
    var usage: Double { total > 0 ? min(Double(used) / Double(total), 1) : 0 }
}

struct VolumeInfo: Identifiable {
    let path: String
    let name: String
    let total: UInt64
    let available: UInt64
    let isRoot: Bool

    var id: String { path }
    var used: UInt64 { total > available ? total - available : 0 }
    var usage: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

/// One physical (or virtual) disk and its current transfer rates.
struct DiskDevice: Identifiable {
    let id: String          // BSD name, e.g. "disk0"
    let name: String        // product name reported by the device
    /// Connection type as the device reports it, e.g. "Internal", "External", "Virtual".
    let location: String
    /// Disk images (.dmg) and other file-backed disks, as reported by the device.
    let isVirtual: Bool
    var readRate: Double
    var writeRate: Double
}

struct DiskStats {
    /// Disks included in the figures (the chosen one, or all physical disks when automatic).
    var devices: [DiskDevice] = []
    /// Every disk, for the picker.
    var allDevices: [DiskDevice] = []
    var isAutomatic = true
    var volumes: [VolumeInfo] = []
    var readRate: Double = 0
    var writeRate: Double = 0
    var totalRead: UInt64 = 0
    var totalWritten: UInt64 = 0

    var root: VolumeInfo? { volumes.first(where: \.isRoot) ?? volumes.first }
}

struct NetworkStats {
    var downRate: Double = 0
    var upRate: Double = 0
    var totalIn: UInt64 = 0
    var totalOut: UInt64 = 0
    var interface: String?
    var interfaceName: String?
    var localIP: String?
    /// Bytes transferred on the primary interface since the previous sample (for data-usage totals).
    var deltaIn: UInt64 = 0
    var deltaOut: UInt64 = 0
    var wifi: WiFiInfo?
    /// Interfaces that can be chosen in the Network tab: (BSD name, display name).
    var available: [NetworkInterface] = []
    /// True when following the system's primary interface rather than a chosen one.
    var isAutomatic = true
}

struct NetworkInterface: Identifiable, Hashable {
    let id: String      // BSD name, e.g. "en0"
    let name: String    // e.g. "Wi-Fi"
}

struct WiFiInfo {
    /// Network name; nil unless StatMenu has Location access (a macOS requirement).
    var ssid: String?
    var rssi: Int
    var noise: Int
    var channel: Int?
    var bandGHz: String?
    var widthMHz: Int?
    var transmitRate: Double
    var standard: String?
    var security: String?

    var snr: Int { rssi - noise }
}

struct BatteryStats {
    var present = false
    var percent: Double = 0
    var isCharging = false
    var onAC = false
    var isCharged = false
    /// macOS shows 100% but is still topping the battery off at a trickle ("finishing charge").
    var isFinishing = false
    var timeRemaining: Int?
    var cycleCount: Int?
    var health: Double?
    var temperature: Double?
    var voltage: Double?
    var amperage: Double?
    var adapterWatts: Int?
    var condition: String?

    /// Live battery power from the SMC while discharging (the fuel gauge only updates every 20–60 s).
    var measuredPower: Double?

    var power: Double? {
        if let measuredPower { return measuredPower }
        guard let voltage, let amperage else { return nil }
        return abs(voltage * amperage)
    }

    /// Plugged in, not charging, and below full: macOS is holding the charge (Optimized Charging or a charge limit).
    var isOnHold: Bool { onAC && !isCharging && !isFull }
    var isFull: Bool { isCharged || percent >= 0.995 }

    var statusText: String {
        if isCharging { return isFinishing ? "Charged · finishing charge" : "Charging" }
        if onAC { return isFull ? "Charged" : "Charging on hold at \(Int((percent * 100).rounded()))%" }
        return "On battery"
    }
}

struct SensorReading: Identifiable {
    let name: String
    let value: Double
    /// True when the name is the hardware's own identifier rather than an established label.
    var isRaw = false
    var id: String { name }
}

struct FanReading: Identifiable {
    let index: Int
    let rpm: Double
    let min: Double
    let max: Double

    var id: Int { index }
    var fraction: Double {
        guard max > 0 else { return 0 }
        return Swift.min(Swift.max(rpm / max, 0), 1)
    }
}

/// Average power of one part of the system over the last few seconds.
struct PowerComponent: Identifiable {
    let name: String
    let watts: Double
    var id: String { name }
}

struct SensorStats {
    var cpu: Double?
    var gpu: Double?
    var ssd: Double?
    var battery: Double?
    var readings: [SensorReading] = []
    var fans: [FanReading] = []
    var systemPower: Double?
    /// Power arriving from the power adapter (0 when unplugged).
    var adapterInput: Double?
    /// Live battery power (SMC PPBR) and a candidate live battery voltage (SMC Vb0f).
    var batteryPower: Double?
    var batteryVoltage: Double?
    var powerBreakdown: [PowerComponent] = []
}

struct DiskProcess: Identifiable {
    let pid: Int32
    let name: String
    let readRate: Double
    let writeRate: Double
    var id: Int32 { pid }
    var total: Double { readRate + writeRate }
}

struct ProcessEntry: Identifiable {
    let pid: Int32
    let name: String
    let cpu: Double
    let memory: UInt64
    var id: Int32 { pid }
}

struct Snapshot {
    var cpu = CPUStats()
    var gpu = GPUStats()
    var memory = MemoryStats()
    var disk = DiskStats()
    var network = NetworkStats()
    var battery = BatteryStats()
    var sensors = SensorStats()
    var topCPU: [ProcessEntry]?
    var topMemory: [ProcessEntry]?
    var topDisk: [DiskProcess]?
}
