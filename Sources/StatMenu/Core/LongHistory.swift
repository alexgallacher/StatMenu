import Foundation

/// The time span a chart shows. Every chart is drawn with 60 columns.
enum HistoryRange: String, CaseIterable, Identifiable {
    case recent, hour, day, week

    static let columns = 60
    var id: String { rawValue }

    /// Length of the range; `nil` for `recent`, which shows the last 60 raw samples.
    var seconds: Double? {
        switch self {
        case .recent: nil
        case .hour: 3_600
        case .day: 86_400
        case .week: 604_800
        }
    }

    func shortLabel(interval: Double) -> String {
        switch self {
        case .recent:
            let s = Int(interval * Double(Self.columns))
            return s >= 60 ? "\(s / 60)m" : "\(s)s"
        case .hour: return "1h"
        case .day: return "24h"
        case .week: return "7d"
        }
    }

    func caption(interval: Double) -> String {
        switch self {
        case .recent:
            let s = Int(interval * Double(Self.columns))
            return s >= 60 ? "Last \(s / 60) min" : "Last \(s) s"
        case .hour: return "Last hour"
        case .day: return "Last 24 hours"
        case .week: return "Last 7 days"
        }
    }
}

/// Fixed-size ring of time buckets holding a running sum and count, so each bucket is an average.
struct Rollup: Codable {
    let bucketSeconds: Double
    let capacity: Int
    private var sums: [Float]
    private var counts: [UInt16]
    /// Absolute index (time / bucketSeconds) of the newest bucket, or -1 when empty.
    private var latest = -1

    init(bucketSeconds: Double, capacity: Int) {
        self.bucketSeconds = bucketSeconds
        self.capacity = capacity
        sums = Array(repeating: 0, count: capacity)
        counts = Array(repeating: 0, count: capacity)
    }

    mutating func add(_ value: Double, at time: TimeInterval) {
        guard value.isFinite else { return }
        let bucket = Int(time / bucketSeconds)
        if latest < 0 { latest = bucket }
        if bucket > latest {
            // Clear the buckets we skip over (time the Mac was asleep or the app wasn't running).
            for step in 1...min(bucket - latest, capacity) {
                let slot = (latest + step) % capacity
                sums[slot] = 0
                counts[slot] = 0
            }
            latest = bucket
        }
        guard bucket > latest - capacity else { return }
        let slot = bucket % capacity
        guard counts[slot] < UInt16.max else { return }
        sums[slot] += Float(value)
        counts[slot] += 1
    }

    /// Averages the buckets into `count` equal columns covering the `span` seconds ending at `now`.
    /// Columns with no data are `nil`.
    func columns(span: Double, count: Int, now: TimeInterval) -> [Double?] {
        var sum = [Double](repeating: 0, count: count)
        var n = [Double](repeating: 0, count: count)
        let start = now - span
        if latest >= 0 {
            let first = max(latest - capacity + 1, Int(start / bucketSeconds))
            if first <= latest {
                for bucket in first...latest {
                    let slot = bucket % capacity
                    guard counts[slot] > 0 else { continue }
                    let mid = (Double(bucket) + 0.5) * bucketSeconds
                    let column = Int((mid - start) / span * Double(count))
                    guard column >= 0, column < count else { continue }
                    sum[column] += Double(sums[slot])
                    n[column] += Double(counts[slot])
                }
            }
        }
        return (0..<count).map { n[$0] > 0 ? sum[$0] / n[$0] : nil }
    }

    // Arrays are stored as raw bytes to keep the saved file small and fast to write.
    private enum CodingKeys: String, CodingKey { case bucketSeconds, capacity, sums, counts, latest }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bucketSeconds = try c.decode(Double.self, forKey: .bucketSeconds)
        capacity = try c.decode(Int.self, forKey: .capacity)
        latest = try c.decode(Int.self, forKey: .latest)
        let sumData = try c.decode(Data.self, forKey: .sums)
        let countData = try c.decode(Data.self, forKey: .counts)
        sums = sumData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        counts = countData.withUnsafeBytes { Array($0.bindMemory(to: UInt16.self)) }
        guard sums.count == capacity, counts.count == capacity else {
            throw DecodingError.dataCorruptedError(forKey: .sums, in: c, debugDescription: "Unexpected history size")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(bucketSeconds, forKey: .bucketSeconds)
        try c.encode(capacity, forKey: .capacity)
        try c.encode(latest, forKey: .latest)
        try c.encode(sums.withUnsafeBufferPointer { Data(buffer: $0) }, forKey: .sums)
        try c.encode(counts.withUnsafeBufferPointer { Data(buffer: $0) }, forKey: .counts)
    }
}

/// Long-term history for one value: minute averages for a day, ten-minute averages for a week.
struct LongHistory: Codable {
    var minutes = Rollup(bucketSeconds: 60, capacity: 1_440)
    var tenMinutes = Rollup(bucketSeconds: 600, capacity: 1_008)

    mutating func add(_ value: Double, at time: TimeInterval) {
        minutes.add(value, at: time)
        tenMinutes.add(value, at: time)
    }

    func columns(_ range: HistoryRange, now: TimeInterval) -> [Double?] {
        switch range {
        case .recent: return Array(repeating: nil, count: HistoryRange.columns)
        case .hour, .day: return minutes.columns(span: range.seconds!, count: HistoryRange.columns, now: now)
        case .week: return tenMinutes.columns(span: range.seconds!, count: HistoryRange.columns, now: now)
        }
    }
}

/// Holds every value's long-term history. A reference type so per-tick updates mutate in place.
final class LongTermStore {
    private(set) var histories: [String: LongHistory] = [:]
    private let queue = DispatchQueue(label: "StatMenu.history-save", qos: .utility)

    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StatMenu", isDirectory: true)
            .appendingPathComponent("history.plist")
    }

    func add(_ key: String, _ value: Double, at time: TimeInterval) {
        histories[key, default: LongHistory()].add(value, at: time)
    }

    func columns(_ key: String, _ range: HistoryRange, now: TimeInterval) -> [Double?] {
        histories[key]?.columns(range, now: now) ?? Array(repeating: nil, count: HistoryRange.columns)
    }

    func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? PropertyListDecoder().decode([String: LongHistory].self, from: data) else { return }
        histories = decoded
    }

    /// Writes a snapshot on a background queue (the dictionary is copied, so the main thread keeps going).
    func save(synchronously: Bool = false) {
        let snapshot = histories
        let write = {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            guard let data = try? encoder.encode(snapshot) else { return }
            let url = Self.fileURL
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        if synchronously { queue.sync(execute: write) } else { queue.async(execute: write) }
    }
}
