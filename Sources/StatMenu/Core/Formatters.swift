import Foundation

enum Fmt {
    static func percent(_ fraction: Double) -> String {
        "\(Int((max(0, fraction) * 100).rounded()))%"
    }

    static func bytes(_ value: UInt64) -> String { bytes(Double(value)) }

    /// Binary-sized storage/memory amounts, e.g. "12.4 GB".
    static func bytes(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var v = value
        var i = 0
        while v >= 1024, i < units.count - 1 { v /= 1024; i += 1 }
        if i == 0 { return "\(Int(v)) B" }
        return String(format: v < 10 ? "%.2f %@" : (v < 100 ? "%.1f %@" : "%.0f %@"), v, units[i])
    }

    /// Decimal disk capacity like Finder shows, e.g. "994.7 GB".
    static func capacity(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    /// Transfer rate, e.g. "1.2 MB/s".
    static func rate(_ bytesPerSecond: Double) -> String {
        let units = ["KB/s", "MB/s", "GB/s"]
        var v = max(0, bytesPerSecond) / 1000
        var i = 0
        while v >= 1000, i < units.count - 1 { v /= 1000; i += 1 }
        return String(format: v < 10 ? "%.1f %@" : "%.0f %@", v, units[i])
    }

    /// Rate split into number and unit, for large readouts.
    static func rateParts(_ bytesPerSecond: Double) -> (String, String) {
        let parts = rate(bytesPerSecond).split(separator: " ")
        return (String(parts.first ?? "0"), String(parts.last ?? "KB/s"))
    }

    /// Compact rate for the menu bar, e.g. "1.2M", "340K".
    static func compactRate(_ bytesPerSecond: Double) -> String {
        let v = max(0, bytesPerSecond)
        if v >= 1_000_000_000 { return String(format: "%.1fG", v / 1_000_000_000) }
        if v >= 1_000_000 { return String(format: v >= 10_000_000 ? "%.0fM" : "%.1fM", v / 1_000_000) }
        return String(format: "%.0fK", v / 1000)
    }

    /// Clock speed, e.g. "3.21 GHz" or "594 MHz".
    static func clock(_ mhz: Double) -> String {
        mhz >= 1000 ? String(format: "%.2f GHz", mhz / 1000) : String(format: "%.0f MHz", mhz)
    }

    /// Current and top clock sharing one unit, e.g. ("1.56", "2.06 GHz"); nil current shows "Idle".
    static func clockPair(_ mhz: Double?, _ maxMHz: Double) -> (String, String) {
        let ghz = maxMHz >= 1000
        func num(_ v: Double) -> String { ghz ? String(format: "%.2f", v / 1000) : String(format: "%.0f", v) }
        return (mhz.map(num) ?? "Idle", num(maxMHz) + (ghz ? " GHz" : " MHz"))
    }

    static func watts(_ w: Double) -> String { String(format: w < 10 ? "%.2f W" : "%.1f W", w) }

    static func temperature(_ celsius: Double?, fahrenheit: Bool) -> String {
        guard let celsius else { return "—" }
        let v = fahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(v.rounded()))°"
    }

    static func uptime(since date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h \(m)m" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func minutes(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
