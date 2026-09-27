import Foundation

/// Bytes received/sent per calendar day on the primary interface, saved to disk.
/// Only traffic seen while StatMenu is running is counted.
final class DataUsageStore {
    private(set) var days: [String: [UInt64]] = [:]   // "yyyy-MM-dd" → [received, sent]
    private let queue = DispatchQueue(label: "StatMenu.data-usage-save", qos: .utility)
    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StatMenu", isDirectory: true)
            .appendingPathComponent("data-usage.json")
    }

    func add(received: UInt64, sent: UInt64, at date: Date = Date()) {
        guard received > 0 || sent > 0 else { return }
        let key = Self.dayFormat.string(from: date)
        var totals = days[key] ?? [0, 0]
        totals[0] &+= received
        totals[1] &+= sent
        days[key] = totals
    }

    func today(_ date: Date = Date()) -> (received: UInt64, sent: UInt64) {
        let t = days[Self.dayFormat.string(from: date)] ?? [0, 0]
        return (t[0], t[1])
    }

    func month(_ date: Date = Date()) -> (received: UInt64, sent: UInt64) {
        let prefix = String(Self.dayFormat.string(from: date).prefix(7))   // "yyyy-MM"
        return days.filter { $0.key.hasPrefix(prefix) }.values.reduce((UInt64(0), UInt64(0))) { ($0.0 &+ $1[0], $0.1 &+ $1[1]) }
    }

    func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode([String: [UInt64]].self, from: data) else { return }
        days = decoded
    }

    func save(synchronously: Bool = false) {
        // Keep roughly 13 months so "this month" always has a full comparison year.
        let cutoff = Self.dayFormat.string(from: Date().addingTimeInterval(-400 * 86_400))
        let snapshot = days.filter { $0.key >= cutoff }
        let write = {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            let url = Self.fileURL
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        if synchronously { queue.sync(execute: write) } else { queue.async(execute: write) }
    }
}
