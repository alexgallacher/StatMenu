import Foundation

enum ProcessSort { case cpu, memory }

final class ProcessMonitor {
    func sample(limit: Int = 6) -> (cpu: [ProcessEntry], memory: [ProcessEntry]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Aco", "pid=,pcpu=,rss=,comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return ([], []) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return ([], []) }

        let ownPID = process.processIdentifier
        var entries: [ProcessEntry] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), pid != ownPID,
                  let cpu = Double(parts[1]), let rss = UInt64(parts[2]) else { continue }
            entries.append(ProcessEntry(pid: pid, name: String(parts[3]), cpu: cpu, memory: rss * 1024))
        }
        let byCPU = entries.sorted { $0.cpu > $1.cpu }.prefix(limit)
        let byMemory = entries.sorted { $0.memory > $1.memory }.prefix(limit)
        return (Array(byCPU), Array(byMemory))
    }
}
