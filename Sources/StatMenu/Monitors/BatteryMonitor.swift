import Foundation
import IOKit
import IOKit.ps

final class BatteryMonitor {
    private var cached = BatteryStats()
    private var countdown = 0

    func sample() -> BatteryStats {
        guard countdown <= 0 else {
            countdown -= 1
            return cached
        }
        countdown = 4
        var stats = BatteryStats()

        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                      desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
                stats.present = true
                let current = desc.number(kIOPSCurrentCapacityKey)?.doubleValue ?? 0
                let max = desc.number(kIOPSMaxCapacityKey)?.doubleValue ?? 100
                stats.percent = max > 0 ? current / max : 0
                stats.isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
                stats.isCharged = desc[kIOPSIsChargedKey] as? Bool ?? false
                stats.onAC = desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
                let key = stats.isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
                if let minutes = desc.number(key)?.intValue, minutes > 0, minutes < 60 * 24 {
                    stats.timeRemaining = minutes
                }
                stats.condition = desc["BatteryHealth"] as? String
            }
        }

        if stats.present {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
            if service != 0 {
                var props: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let dict = props?.takeRetainedValue() as? [String: Any] {
                    stats.cycleCount = dict.number("CycleCount")?.intValue
                    let data = dict["BatteryData"] as? [String: Any] ?? [:]
                    let design = (dict.number("DesignCapacity") ?? data.number("DesignCapacity"))?.doubleValue ?? 0
                    let maxCap = (dict.number("AppleRawMaxCapacity") ?? dict.number("NominalChargeCapacity")
                        ?? data.number("NominalChargeCapacity") ?? data.number("FullChargeCapacity"))?.doubleValue ?? 0
                    if design > 0, maxCap > 0 { stats.health = min(maxCap / design, 1) }
                    if let t = dict.number("Temperature")?.doubleValue { stats.temperature = t / 100 }
                    if let v = dict.number("Voltage")?.doubleValue { stats.voltage = v / 1000 }
                    if let a = (dict.number("InstantAmperage") ?? dict.number("Amperage"))?.int64Value {
                        stats.amperage = Double(a) / 1000
                    }
                    if let adapter = dict["AdapterDetails"] as? [String: Any], let watts = adapter.number("Watts")?.intValue, watts > 0 {
                        stats.adapterWatts = watts
                    }
                }
                IOObjectRelease(service)
            }
        }
        cached = stats
        return stats
    }
}
