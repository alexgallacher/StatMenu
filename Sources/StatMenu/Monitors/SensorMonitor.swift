import CStats
import Foundation

/// Temperatures, fans and system power.
///
/// Only sensors with widely agreed meanings get friendly names (see `knownSMCPrefixes`, `knownHIDNames`);
/// everything else is shown under the name the hardware reports.
final class SensorMonitor {
    private var smcTemperatureKeys: [String] = []
    private var fanCount = 0
    private var didEnumerate = false
    private var tick = 0
    private var otherSMC: [String: [Double]] = [:]
    private var rawSMC: [String: [Double]] = [:]
    private var hidKnown: [String: [Double]] = [:]
    private var hidRaw: [String: [Double]] = [:]
    /// Fan limits are fixed by the hardware; read once rather than every tick.
    private var fanLimits: [Int: (min: Double, max: Double)] = [:]

    /// SMC key prefixes with established meanings on Apple Silicon.
    private static let knownSMCPrefixes: [String: String] = [
        "Tp": "CPU performance cores",
        "Te": "CPU efficiency cores",
        "Tg": "GPU",
        "TB": "Battery",
    ]

    /// HID sensor name fragments with self-describing meanings.
    private static let knownHIDNames: [(fragment: String, name: String)] = [
        ("NAND", "SSD"),
        ("gas gauge battery", "Battery"),
    ]

    /// SMC prefix of the sensors behind the menu bar temperature, read every call.
    private static let menuBarPrefix = "Tp"

    /// `detailed` (a dropdown is open) reads every sensor each call. Otherwise only the CPU sensors
    /// (shown in the menu bar) are read every call; the other labelled sensors every fifth call, and the
    /// long tail of unlabelled SMC keys and HID sensors every fifteenth. Each SMC read is a ~0.2 ms round-trip
    /// to the SMC and a HID sweep takes ~75 ms, so this is most of the app's idle cost. Skipped sensors keep
    /// their last value, and opening a dropdown refreshes everything at once.
    func sample(detailed: Bool = false) -> SensorStats {
        if !didEnumerate { enumerateSMC() }
        var known: [String: [Double]] = [:]
        var raw: [String: [Double]] = [:]

        let refreshOther = detailed || tick % 5 == 0
        let refreshRaw = detailed || tick % 15 == 0
        tick += 1
        if refreshOther { otherSMC = [:] }
        if refreshRaw { rawSMC = [:] }
        for key in smcTemperatureKeys {
            let prefix = String(key.prefix(2))
            let name = Self.knownSMCPrefixes[prefix]
            if let name {
                guard prefix == Self.menuBarPrefix || refreshOther else { continue }
            } else {
                guard refreshRaw else { continue }
            }
            var v = 0.0
            guard smc_read_value(key, &v) == 0, v > 5, v < 130 else { continue }
            if let name {
                if prefix == Self.menuBarPrefix {
                    known[name, default: []].append(v)
                } else {
                    otherSMC[name, default: []].append(v)
                }
            } else {
                rawSMC["SMC \(prefix)··", default: []].append(v)
            }
        }
        known.merge(otherSMC) { $0 + $1 }
        raw = rawSMC
        // HID reads are costly (one IPC round-trip per sensor) and only feed slow-moving readings.
        if refreshRaw {
            hidKnown = [:]
            hidRaw = [:]
            if let hid = hid_copy_temperature_sensors() as? [[String: Any]] {
                for entry in hid {
                    guard let name = entry["name"] as? String, let value = entry["value"] as? Double else { continue }
                    if let match = Self.knownHIDNames.first(where: { name.localizedCaseInsensitiveContains($0.fragment) }) {
                        hidKnown[match.name, default: []].append(value)
                    } else {
                        hidRaw[name, default: []].append(value)
                    }
                }
            }
        }
        known.merge(hidKnown) { $0 + $1 }
        raw.merge(hidRaw) { $0 + $1 }

        func average(_ values: [Double]?) -> Double? {
            guard let values, !values.isEmpty else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }
        var stats = SensorStats()
        stats.readings = known.keys.sorted().map { SensorReading(name: $0, value: average(known[$0])!, isRaw: false) }
            + raw.keys.sorted().map { SensorReading(name: $0, value: average(raw[$0])!, isRaw: true) }
        stats.cpu = average(known["CPU performance cores"]) ?? Self.intelCPU()
        stats.gpu = average(known["GPU"])
        stats.ssd = average(known["SSD"])
        stats.battery = average(known["Battery"])

        for i in 0..<fanCount {
            var rpm = 0.0
            guard smc_read_value("F\(i)Ac", &rpm) == 0 else { continue }
            if fanLimits[i] == nil {
                var lo = 0.0, hi = 0.0
                _ = smc_read_value("F\(i)Mn", &lo)
                _ = smc_read_value("F\(i)Mx", &hi)
                fanLimits[i] = (lo, hi)
            }
            let limits = fanLimits[i]!
            stats.fans.append(FanReading(index: i, rpm: max(rpm, 0), min: limits.min, max: limits.max))
        }
        var power = 0.0
        if smc_read_value("PSTR", &power) == 0, power > 0, power < 1000 {
            stats.systemPower = power
        }
        var batteryPower = 0.0, batteryVoltage = 0.0
        if smc_read_value("PPBR", &batteryPower) == 0, batteryPower >= 0, batteryPower < 1000 {
            stats.batteryPower = batteryPower
        }
        if smc_read_value("Vb0f", &batteryVoltage) == 0, batteryVoltage > 0, batteryVoltage < 30 {
            stats.batteryVoltage = batteryVoltage
        }
        var input = 0.0
        if smc_read_value("PDTR", &input) == 0, input >= 0, input < 1000 {
            stats.adapterInput = input
        }
        return stats
    }

    /// Intel Macs have no Tp keys; they expose documented CPU die / proximity keys instead.
    private static func intelCPU() -> Double? {
        for key in ["TC0D", "TC0E", "TC0P"] {
            var v = 0.0
            if smc_read_value(key, &v) == 0, v > 5, v < 130 { return v }
        }
        return nil
    }

    private func enumerateSMC() {
        didEnumerate = true
        guard smc_open() == 0 else { return }
        var fans = 0.0
        if smc_read_value("FNum", &fans) == 0 { fanCount = Int(fans) }

        let count = smc_key_count()
        guard count > 0 else { return }
        var keys: [String] = []
        var keyBuffer = [CChar](repeating: 0, count: 5)
        var typeBuffer = [CChar](repeating: 0, count: 5)
        for index in 0..<count {
            guard smc_key_at(Int32(index), &keyBuffer) == 0 else { continue }
            let key = String(cString: keyBuffer)
            guard key.hasPrefix("T"), smc_key_type(key, &typeBuffer) == 0 else { continue }
            let type = String(cString: typeBuffer)
            guard type == "flt " || type == "sp78" else { continue }
            var v = 0.0
            if smc_read_value(key, &v) == 0, v > 5, v < 130 { keys.append(key) }
        }
        smcTemperatureKeys = keys
    }
}
