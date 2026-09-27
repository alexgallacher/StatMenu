import Foundation

/// Fixed-length rolling series used for graphs. Oldest sample first.
struct History {
    private(set) var values: [Double]
    /// How many real samples have been recorded (the buffer starts zero-filled).
    private(set) var filled = 0

    init(capacity: Int = 90) {
        values = Array(repeating: 0, count: capacity)
    }

    mutating func append(_ value: Double) {
        values.removeFirst()
        values.append(value.isFinite ? value : 0)
        filled = min(filled + 1, values.count)
    }

    /// The most recent `count` real samples (excluding the zero padding).
    func recent(_ count: Int) -> [Double] { Array(values.suffix(min(count, filled))) }

    func tail(_ count: Int) -> [Double] { Array(values.suffix(count)) }
    var peak: Double { values.max() ?? 0 }
}
