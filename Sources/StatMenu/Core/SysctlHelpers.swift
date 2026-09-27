import Darwin
import Foundation
import IOKit

func sysctlInt(_ name: String) -> Int? {
    var value: Int64 = 0
    var size = MemoryLayout<Int64>.size
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
    if size == 4 { return Int(Int32(truncatingIfNeeded: value)) }
    return Int(value)
}

func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
    return String(cString: buffer)
}

func systemBootDate() -> Date {
    var tv = timeval()
    var size = MemoryLayout<timeval>.size
    guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else { return Date() }
    return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1_000_000)
}

/// Iterates IOKit services matching `className`, handing each one's property dictionary to `body`.
/// Return `false` from `body` to stop early.
func forEachIOService(_ className: String, _ body: ([String: Any]) -> Bool) {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else { return }
    defer { IOObjectRelease(iterator) }
    var entry = IOIteratorNext(iterator)
    while entry != 0 {
        var props: Unmanaged<CFMutableDictionary>?
        var keepGoing = true
        if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
           let dict = props?.takeRetainedValue() as? [String: Any] {
            keepGoing = body(dict)
        }
        IOObjectRelease(entry)
        if !keepGoing { break }
        entry = IOIteratorNext(iterator)
    }
}

extension Dictionary where Key == String, Value == Any {
    func number(_ key: String) -> NSNumber? { self[key] as? NSNumber }
}

enum SystemInfo {
    static let isAppleSilicon = sysctlInt("hw.optional.arm64") == 1
}
