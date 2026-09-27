import Darwin
import Foundation

/// Top processes by disk read/write rate, from each process's cumulative I/O counters.
/// Processes owned by other users (e.g. root daemons) can't be read without privileges and are skipped.
final class DiskProcessMonitor {
    private var previous: [Int32: (read: UInt64, write: UInt64)] = [:]
    private var lastTime: TimeInterval = 0

    func sample(limit: Int = 5) -> [DiskProcess] {
        var pids = [Int32](repeating: 0, count: 4096)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size)))
        guard count > 0 else { return [] }
        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - lastTime
        var current: [Int32: (UInt64, UInt64)] = [:]
        var result: [DiskProcess] = []
        for pid in pids.prefix(count) where pid > 0 {
            var info = rusage_info_v2()
            let ok = withUnsafeMutablePointer(to: &info) { ptr in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
            }
            guard ok == 0 else { continue }
            let read = info.ri_diskio_bytesread, write = info.ri_diskio_byteswritten
            current[pid] = (read, write)
            guard lastTime > 0, dt > 0, let p = previous[pid] else { continue }
            let r = read >= p.read ? Double(read - p.read) / dt : 0
            let w = write >= p.write ? Double(write - p.write) / dt : 0
            guard r + w > 0 else { continue }
            result.append(DiskProcess(pid: pid, name: Self.name(pid), readRate: r, writeRate: w))
        }
        previous = current.mapValues { (read: $0.0, write: $0.1) }
        lastTime = now
        return Array(result.sorted { $0.total > $1.total }.prefix(limit))
    }

    private static func name(_ pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buffer, UInt32(buffer.count))
        return String(cString: buffer)
    }
}
