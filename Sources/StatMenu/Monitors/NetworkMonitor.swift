import Darwin
import Foundation
import SystemConfiguration

final class NetworkMonitor {
    private var previous: [String: (UInt64, UInt64)] = [:]
    private var lastTime: TimeInterval = 0
    private var infoCountdown = 0
    private var primary: String?
    private var displayName: String?
    private var localIP: String?

    func sample() -> NetworkStats {
        if infoCountdown <= 0 {
            primary = Self.primaryInterface()
            displayName = primary.flatMap(Self.displayName(for:))
            localIP = primary.flatMap(Self.ipv4Address(for:))
            infoCountdown = 10
        }
        infoCountdown -= 1

        let counters = Self.readCounters()
        let names: [String]
        if let primary, counters[primary] != nil {
            names = [primary]
        } else {
            names = counters.keys.filter { $0.hasPrefix("en") }
        }

        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - lastTime
        var stats = NetworkStats()
        for name in names {
            guard let (inBytes, outBytes) = counters[name] else { continue }
            stats.totalIn += inBytes
            stats.totalOut += outBytes
            if let (prevIn, prevOut) = previous[name], dt > 0, lastTime > 0 {
                let dIn = inBytes >= prevIn ? inBytes - prevIn : 0
                let dOut = outBytes >= prevOut ? outBytes - prevOut : 0
                stats.deltaIn += dIn
                stats.deltaOut += dOut
                stats.downRate += Double(dIn) / dt
                stats.upRate += Double(dOut) / dt
            }
        }
        previous = counters
        lastTime = now
        stats.interface = primary
        stats.interfaceName = displayName
        stats.localIP = localIP
        return stats
    }

    private static func readCounters() -> [String: (UInt64, UInt64)] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return [:] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return [:] }

        var result: [String: (UInt64, UInt64)] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let h2 = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(h2.ifm_index), &nameBuffer) != nil {
                        let name = String(cString: nameBuffer)
                        if !name.hasPrefix("lo") {
                            result[name] = (h2.ifm_data.ifi_ibytes, h2.ifm_data.ifi_obytes)
                        }
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return result
    }

    private static func primaryInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "StatMenu" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return nil }
        return value["PrimaryInterface"] as? String
    }

    private static func displayName(for bsdName: String) -> String? {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return nil }
        for interface in interfaces where SCNetworkInterfaceGetBSDName(interface) as String? == bsdName {
            return SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?
        }
        return nil
    }

    private static func ipv4Address(for name: String) -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var pointer = ifaddr
        while let current = pointer {
            let entry = current.pointee
            if let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET), String(cString: entry.ifa_name) == name {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: host)
                }
            }
            pointer = entry.ifa_next
        }
        return nil
    }
}
