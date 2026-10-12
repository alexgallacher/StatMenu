import Foundation

/// Fixed-length rolling series used for graphs: a ring buffer, so appending doesn't shift every sample.
struct History {
    private var buffer: [Double]
    /// Index of the oldest sample (the next one to be overwritten).
    private var head = 0
    /// How many real samples have been recorded (the buffer starts zero-filled).
    private(set) var filled = 0

    init(capacity: Int = 90) {
        buffer = Array(repeating: 0, count: capacity)
    }

    mutating func append(_ value: Double) {
        buffer[head] = value.isFinite ? value : 0
        head = (head + 1) % buffer.count
        filled = min(filled + 1, buffer.count)
    }

    /// The most recent `count` real samples (excluding the zero padding), oldest first.
    func recent(_ count: Int) -> [Double] { tail(min(count, filled)) }

    /// The last `count` slots, oldest first, including zero padding before the first real sample.
    func tail(_ count: Int) -> [Double] {
        let n = min(max(count, 0), buffer.count)
        return (buffer.count - n..<buffer.count).map { buffer[(head + $0) % buffer.count] }
    }
}
