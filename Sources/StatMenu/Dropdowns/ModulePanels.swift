import SwiftUI

/// Every panel follows the same skeleton: title → readout → trace → stat strip → blocks.
struct ModulePanel: View {
    let module: Module
    let store: SystemStore
    let settings: AppSettings
    @State private var showRawSensors = false
    @AppStorage("historyRange") private var rangeRaw = HistoryRange.recent.rawValue
    private var range: HistoryRange { HistoryRange(rawValue: rangeRaw) ?? .recent }
    private func cols(_ key: String) -> [Double?] { store.columns(key, range) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch module {
            case .cpu: cpu
            case .gpu: gpu
            case .memory: memory
            case .disk: disk
            case .network: network
            case .sensors: sensors
            case .battery: battery
            }
        }
    }

    private func temp(_ c: Double?) -> String {
        guard c != nil else { return "—" }
        return Fmt.temperature(c, fahrenheit: settings.useFahrenheit)
    }

    private var tempUnit: String { settings.useFahrenheit ? "°F" : "°C" }

    // Hover-graph descriptors, one per kind of value.
    private func pct(_ title: String, _ key: String, _ m: Module) -> HoverSeries {
        HoverSeries(title: title, key: key, hue: m.hue, format: { Fmt.percent($0) }, maxValue: 1)
    }
    private func bytes(_ title: String, _ key: String, _ m: Module) -> HoverSeries {
        HoverSeries(title: title, key: key, hue: m.hue, format: { Fmt.bytes($0) })
    }
    private func rate(_ title: String, _ key: String, _ m: Module) -> HoverSeries {
        HoverSeries(title: title, key: key, hue: m.hue, format: { Fmt.rate($0) })
    }
    private func heat(_ title: String, _ key: String) -> HoverSeries {
        HoverSeries(title: title, key: key, hue: Module.sensors.hue,
                    format: { Fmt.temperature($0, fahrenheit: settings.useFahrenheit) }, minValue: 20, maxValue: 105)
    }
    private func clock(_ title: String, _ key: String, _ m: Module, max: Double) -> HoverSeries {
        HoverSeries(title: title, key: key, hue: m.hue, format: { $0 <= 0 ? "Idle" : Fmt.clock($0) }, maxValue: max)
    }
    private func watts(_ title: String, _ key: String, _ m: Module) -> HoverSeries {
        HoverSeries(title: title, key: key, hue: m.hue, format: { String(format: "%.1f W", $0) })
    }

    // MARK: CPU

    @ViewBuilder private var cpu: some View {
        let c = store.cpu
        PanelTitle(title: "CPU", detail: store.chipName)
        Readout(value: "\(Int((c.total * 100).rounded()))", unit: "%", color: Theme.level(c.total))
        let user = cols("cpu.user"), system = cols("cpu.system")
        BarHistory(values: user, lower: system, maxValue: 1, hue: Module.cpu.hue)
            .frame(height: 56).id(range).transition(.opacity)
        ChartCaption(interval: settings.updateInterval,
                     peak: columnPeak(zip(user, system).map { u, s in u.map { $0 + (s ?? 0) } }).map { "Peak \(Fmt.percent($0))" })
        StatStrip(items: [
            Stat(label: "User", value: Fmt.percent(c.user), hover: pct("User", "cpu.user", .cpu)),
            Stat(label: "System", value: Fmt.percent(c.system), hover: pct("System", "cpu.system", .cpu)),
            Stat(label: "Idle", value: Fmt.percent(c.idle), hover: pct("Idle", "cpu.idle", .cpu)),
        ])

        if !c.cores.isEmpty {
            Block(label: "Cores", trailing: c.efficiencyCores > 0 ? "\(c.performanceCores)P · \(c.efficiencyCores)E" : "\(c.cores.count)") {
                CoreColumns(cores: c.cores, isEfficiency: c.coreIsEfficiency, hue: Module.cpu.hue) { index, efficiency in
                    pct("Core \(index + 1) · \(efficiency ? "Efficiency" : "Performance")", "cpu.core.\(index)", .cpu)
                }
            }
        }
        if !c.clusters.isEmpty {
            Block(label: "Clock speed", trailing: "Current / max") {
                ForEach(c.clusters) { r in
                    ClockRow(reading: r, hue: Module.cpu.hue)
                        .hoverHistory(clock("\(r.name) clock", "clock.\(r.name)", .cpu, max: r.maxMHz))
                }
            }
        }
        if let power = c.power {
            Block(label: "Power") {
                Row(label: "CPU power", value: Fmt.watts(power), hover: watts("CPU power", "power.cpu", .cpu))
            }
        }
        Block(label: "Processes") {
            ProcessRows(entries: store.topCPU) { String(format: "%.1f%%", $0.cpu) }
        }
        Block(label: "System") {
            Row(label: "Load average", value: c.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: " "),
                hover: HoverSeries(title: "Load average (1 min)", key: "cpu.load", hue: Module.cpu.hue,
                                   format: { String(format: "%.2f", $0) }))
            Row(label: "Uptime", value: Fmt.uptime(since: store.bootDate))
            if store.sensors.cpu != nil {
                Row(label: "Temperature", value: temp(store.sensors.cpu) + (settings.useFahrenheit ? "F" : "C"),
                    valueColor: Theme.heat(store.sensors.cpu), hover: heat("CPU temperature", "temp.cpu"))
            }
        }
    }

    // MARK: GPU

    @ViewBuilder private var gpu: some View {
        let g = store.gpu
        PanelTitle(title: "GPU", detail: g.cores.map { "\(g.name) · \($0) cores" } ?? g.name)
        Readout(value: g.available ? "\(Int((g.utilization * 100).rounded()))" : "—", unit: "%", color: Theme.level(g.utilization))
        let gpuCols = cols("gpu.util")
        BarHistory(values: gpuCols, maxValue: 1, hue: Module.gpu.hue).frame(height: 56).id(range).transition(.opacity)
        ChartCaption(interval: settings.updateInterval, peak: columnPeak(gpuCols).map { "Peak \(Fmt.percent($0))" })
        StatStrip(items: [
            Stat(label: "Now", value: Fmt.percent(g.utilization), hover: pct("GPU utilization", "gpu.util", .gpu)),
            Stat(label: "Peak", value: columnPeak(gpuCols).map(Fmt.percent) ?? "—"),
            Stat(label: "Temp", value: temp(store.sensors.gpu), hover: heat("GPU temperature", "temp.gpu")),
        ])
        if let clock = g.clock {
            Block(label: "Clock speed", trailing: "Current / max") {
                ClockRow(reading: clock, hue: Module.gpu.hue)
                    .hoverHistory(self.clock("GPU clock", "clock.GPU", .gpu, max: clock.maxMHz))
            }
        }
        if let power = g.power {
            Block(label: "Power") {
                Row(label: "GPU power", value: Fmt.watts(power), hover: watts("GPU power", "power.gpu", .gpu))
            }
        }
        Block(label: "Engines") {
            MeterRow(label: "Device", fraction: g.utilization, value: Fmt.percent(g.utilization), hue: Module.gpu.hue,
                     hover: pct("Device utilization", "gpu.util", .gpu))
            if let r = g.renderer {
                MeterRow(label: "Renderer", fraction: r, value: Fmt.percent(r), hue: Module.gpu.hue,
                         hover: pct("Renderer utilization", "gpu.renderer", .gpu))
            }
            if let t = g.tiler {
                MeterRow(label: "Tiler", fraction: t, value: Fmt.percent(t), hue: Module.gpu.hue,
                         hover: pct("Tiler utilization", "gpu.tiler", .gpu))
            }
        }
        if let mem = g.memoryUsed {
            Block(label: "Memory") {
                Row(label: "In use", value: Fmt.bytes(mem), hover: bytes("GPU memory in use", "gpu.memory", .gpu))
            }
        }
    }

    // MARK: Memory

    @ViewBuilder private var memory: some View {
        let m = store.memory
        PanelTitle(title: "Memory", detail: Fmt.bytes(m.total) + (SystemInfo.isAppleSilicon ? " unified" : ""))
        Readout(value: "\(Int((m.usage * 100).rounded()))", unit: "% used", color: Theme.pressure(m.pressureLevel))
        BarHistory(values: cols("mem.pressure"), maxValue: 1, hue: Module.memory.hue).frame(height: 56).id(range).transition(.opacity)
        ChartCaption(interval: settings.updateInterval, peak: "Memory pressure")
        StatStrip(items: [
            Stat(label: "Used", value: Fmt.bytes(m.used), hover: bytes("Memory used", "mem.used", .memory)),
            Stat(label: "Pressure", value: Fmt.percent(m.pressure), hover: pct("Memory pressure", "mem.pressure", .memory)),
            Stat(label: "Swap", value: Fmt.bytes(m.swapUsed), hover: bytes("Swap used", "mem.swap", .memory)),
        ])
        Block(label: "Composition") {
            CompositionBar(hue: Module.memory.hue, parts: [Double(m.app), Double(m.wired), Double(m.compressed), Double(m.cached), Double(m.free)])
            SwatchRow(label: "App", value: Fmt.bytes(m.app), shade: 1).hoverHistory(bytes("App memory", "mem.app", .memory))
            SwatchRow(label: "Wired", value: Fmt.bytes(m.wired), shade: 0.7).hoverHistory(bytes("Wired memory", "mem.wired", .memory))
            SwatchRow(label: "Compressed", value: Fmt.bytes(m.compressed), shade: 0.45)
                .hoverHistory(bytes("Compressed memory", "mem.compressed", .memory))
            SwatchRow(label: "Cached", value: Fmt.bytes(m.cached), shade: 0.22).hoverHistory(bytes("Cached files", "mem.cached", .memory))
            SwatchRow(label: "Free", value: Fmt.bytes(m.free), shade: 0).hoverHistory(bytes("Free memory", "mem.free", .memory))
        }
        Block(label: "Paging", trailing: "Per second") {
            Row(label: "Page ins", value: Fmt.rate(m.pageInRate), hover: rate("Page ins", "mem.pagein", .memory))
            Row(label: "Page outs", value: Fmt.rate(m.pageOutRate), hover: rate("Page outs", "mem.pageout", .memory))
            Row(label: "Swap ins", value: Fmt.rate(m.swapInRate), hover: rate("Swap ins", "mem.swapin", .memory))
            Row(label: "Swap outs", value: Fmt.rate(m.swapOutRate), hover: rate("Swap outs", "mem.swapout", .memory))
        }
        Block(label: "Processes") {
            ProcessRows(entries: store.topMemory) { Fmt.bytes($0.memory) }
        }
    }

    // MARK: Disk

    @ViewBuilder private var disk: some View {
        let d = store.disk
        PanelTitle(title: "Disks", detail: d.root.map { "\(Fmt.capacity($0.available)) free" } ?? "No volumes")
        Readout(value: "\(Int(((d.root?.usage ?? 0) * 100).rounded()))", unit: "% used", color: Theme.level(d.root?.usage ?? 0))
        MirrorBars(top: cols("disk.read"), bottom: cols("disk.write"), minimumScale: 1_000_000, hue: Module.disk.hue)
            .frame(height: 56).id(range).transition(.opacity)
        ChartCaption(interval: settings.updateInterval, peak: "Read above · write below")
        StatStrip(items: [
            Stat(label: "Read", value: Fmt.rate(d.readRate), hover: rate("Disk read", "disk.read", .disk)),
            Stat(label: "Write", value: Fmt.rate(d.writeRate), hover: rate("Disk write", "disk.write", .disk)),
        ])
        if !d.devices.isEmpty {
            Block(label: "Disks") {
                ForEach(d.devices) { dev in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(dev.name).font(Typo.body).foregroundStyle(Theme.ink).lineLimit(1)
                            Spacer()
                            Text("\(dev.id) · \(dev.location)").font(Typo.caption).foregroundStyle(Theme.label)
                        }
                        StatStrip(items: [
                            Stat(label: "Read", value: Fmt.rate(dev.readRate), hover: rate("\(dev.name) read", "disk.\(dev.id).read", .disk)),
                            Stat(label: "Write", value: Fmt.rate(dev.writeRate), hover: rate("\(dev.name) write", "disk.\(dev.id).write", .disk)),
                        ])
                    }
                }
            }
        }
        Block(label: "Processes", trailing: "Read + write") {
            if store.topDisk.isEmpty {
                Text("No disk activity from your apps right now.").font(Typo.body).foregroundStyle(Theme.label)
            }
            ForEach(store.topDisk) { p in
                Row(label: p.name, value: Fmt.rate(p.total))
            }
        }
        Block(label: "Volumes") {
            ForEach(d.volumes) { v in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(v.name).font(Typo.body).foregroundStyle(Theme.ink).lineLimit(1)
                        Spacer()
                        AnimatedValue(text: "\(Fmt.capacity(v.used)) of \(Fmt.capacity(v.total))", color: Theme.label, font: Typo.caption)
                    }
                    Meter(fraction: v.usage, hue: v.usage >= 0.95 ? Theme.critical : Module.disk.hue)
                }
            }
        }
        Block(label: "Since boot") {
            Row(label: "Read", value: Fmt.bytes(d.totalRead))
            Row(label: "Written", value: Fmt.bytes(d.totalWritten))
        }
    }

    // MARK: Network

    @ViewBuilder private var network: some View {
        let n = store.network
        let down = Fmt.rateParts(n.downRate)
        PanelTitle(title: "Network", detail: n.interface.map { "\(n.interfaceName ?? $0) · \($0)" } ?? "Offline")
        Readout(value: down.0, unit: "\(down.1) down")
        let downCols = cols("net.down"), upCols = cols("net.up")
        MirrorBars(top: downCols, bottom: upCols, hue: Module.network.hue).frame(height: 56).id(range).transition(.opacity)
        ChartCaption(interval: settings.updateInterval, peak: "Down above · up below")
        StatStrip(items: [
            Stat(label: "Upload", value: Fmt.rate(n.upRate), hover: rate("Upload", "net.up", .network)),
            Stat(label: "Peak down", value: Fmt.rate(columnPeak(downCols) ?? 0), hover: rate("Download", "net.down", .network)),
            Stat(label: "Peak up", value: Fmt.rate(columnPeak(upCols) ?? 0), hover: rate("Upload", "net.up", .network)),
        ])
        Block(label: "Connection") {
            Row(label: "Interface", value: n.interfaceName ?? "—")
            Row(label: "Local IP", value: n.localIP ?? "—")
        }
        if let w = n.wifi {
            Block(label: "Wi-Fi") {
                if let ssid = w.ssid {
                    Row(label: "Network", value: ssid)
                } else {
                    HStack {
                        Text("Network").font(Typo.body).foregroundStyle(Theme.text)
                        Spacer()
                        LinkButton(title: LocationAccess.shared.isDenied ? "Turn on Location access" : "Allow Location access",
                                   prominent: false) { LocationAccess.shared.request() }
                    }
                }
                Row(label: "Signal", value: "\(w.rssi) dBm",
                    hover: HoverSeries(title: "Signal strength", key: "wifi.rssi", hue: Module.network.hue,
                                       format: { "\(Int($0)) dBm" }, minValue: -100, maxValue: -20))
                Row(label: "Noise", value: "\(w.noise) dBm")
                Row(label: "Signal to noise", value: "\(w.snr) dB",
                    hover: HoverSeries(title: "Signal to noise", key: "wifi.snr", hue: Module.network.hue, format: { "\(Int($0)) dB" }))
                if let channel = w.channel {
                    Row(label: "Channel", value: [String(channel), w.bandGHz, w.widthMHz.map { "\($0) MHz" }]
                        .compactMap { $0 }.joined(separator: " · "))
                }
                Row(label: "Link rate", value: "\(Int(w.transmitRate)) Mbps",
                    hover: HoverSeries(title: "Link rate", key: "wifi.rate", hue: Module.network.hue, format: { "\(Int($0)) Mbps" }))
                if let standard = w.standard { Row(label: "Standard", value: standard) }
                if let security = w.security { Row(label: "Security", value: security) }
            }
        }
        let today = store.usageToday(), month = store.usageMonth()
        Block(label: "Data usage", trailing: "Down · Up") {
            Row(label: "Today", value: "\(Fmt.bytes(today.received)) · \(Fmt.bytes(today.sent))")
            Row(label: "This month", value: "\(Fmt.bytes(month.received)) · \(Fmt.bytes(month.sent))")
            Text("Counted while StatMenu is running.").font(Typo.caption).foregroundStyle(Theme.label)
        }
        Block(label: "Since boot") {
            Row(label: "Received", value: Fmt.bytes(n.totalIn))
            Row(label: "Sent", value: Fmt.bytes(n.totalOut))
        }
    }

    // MARK: Sensors

    @ViewBuilder private var sensors: some View {
        let s = store.sensors
        PanelTitle(title: "Sensors", detail: s.fans.isEmpty ? "Temperatures" : "Temperatures and fans")
        Readout(value: s.cpu.map { _ in String(temp(s.cpu).dropLast()) } ?? "—", unit: "\(tempUnit) CPU", color: Theme.heat(s.cpu))
        let tempCols = cols("temp.cpu")
        BarHistory(values: tempCols, minValue: 20, maxValue: 105, hue: Module.sensors.hue).frame(height: 56).id(range).transition(.opacity)
        ChartCaption(interval: settings.updateInterval, peak: columnPeak(tempCols).map { "Peak \(temp($0))" })
        StatStrip(items: [
            Stat(label: "GPU", value: temp(s.gpu), hover: heat("GPU temperature", "temp.gpu")),
            Stat(label: "SSD", value: temp(s.ssd), hover: heat("SSD temperature", "temp.ssd")),
            Stat(label: "Battery", value: temp(s.battery), hover: heat("Battery temperature", "temp.battery")),
        ])
        if !s.fans.isEmpty {
            Block(label: "Fans") {
                ForEach(s.fans) { fan in
                    MeterRow(label: "Fan \(fan.index + 1)", fraction: fan.fraction, value: "\(Int(fan.rpm)) rpm", hue: Module.sensors.hue,
                             hover: HoverSeries(title: "Fan \(fan.index + 1)", key: "fan.\(fan.index)", hue: Module.sensors.hue,
                                                format: { "\(Int($0)) rpm" }, maxValue: fan.max > 0 ? fan.max : nil))
                }
            }
        }
        let labelled = s.readings.filter { !$0.isRaw }
        let raw = s.readings.filter(\.isRaw)
        if !labelled.isEmpty {
            Block(label: "Temperatures") {
                ForEach(labelled) { r in
                    Row(label: r.name, value: temp(r.value), valueColor: Theme.heat(r.value), hover: heat(r.name, "temp.\(r.name)"))
                }
            }
        }
        if !raw.isEmpty {
            Block(label: "Other sensors") {
                LinkButton(title: showRawSensors ? "Hide \(raw.count) unlabelled sensors" : "Show \(raw.count) unlabelled sensors",
                           arrow: !showRawSensors, prominent: false) { showRawSensors.toggle() }
                if showRawSensors {
                    Text("Shown with the names the hardware reports.").font(Typo.caption).foregroundStyle(Theme.label)
                    ForEach(raw) { r in
                        Row(label: r.name, value: temp(r.value), valueColor: Theme.heat(r.value), hover: heat(r.name, "temp.\(r.name)"))
                    }
                }
            }
        }
    }

    // MARK: Battery

    @ViewBuilder private var battery: some View {
        let b = store.battery
        PanelTitle(title: "Power", detail: b.present ? "Battery · \(b.statusText)" : "Power adapter")
        if b.present {
            Readout(value: "\(Int((b.percent * 100).rounded()))", unit: "% battery",
                    color: b.percent < 0.15 && !b.onAC ? Theme.critical : Theme.ink)
            BarHistory(values: cols("battery.percent"), maxValue: 1, autoRange: true, hue: Module.battery.hue)
                .frame(height: 56).id(range).transition(.opacity)
            ChartCaption(interval: settings.updateInterval,
                         peak: b.power.map { "\(b.isCharging ? "Charging" : "Draw") \(Fmt.watts($0))" })
        } else if let total = store.sensors.systemPower {
            Readout(value: String(format: "%.1f", total), unit: "W system")
            BarHistory(values: cols("power.system"), hue: Module.battery.hue).frame(height: 56).id(range).transition(.opacity)
            ChartCaption(interval: settings.updateInterval, peak: nil)
        }
        if b.present {
            StatStrip(items: [
                Stat(label: b.isCharging ? "Until full" : "Remaining", value: b.timeRemaining.map(Fmt.minutes) ?? "—"),
                Stat(label: "Health", value: b.health.map(Fmt.percent) ?? "—"),
                Stat(label: "Cycles", value: b.cycleCount.map(String.init) ?? "—"),
            ])
        }
        if b.onAC, let rated = b.adapterWatts {
            let input = store.sensors.adapterInput ?? 0
            Block(label: "Charging", trailing: "\(rated) W adapter") {
                MeterRow(label: "Charge rate", fraction: b.isCharging ? (b.power ?? 0) / Double(rated) : 0,
                         value: b.isCharging ? "\(Fmt.watts(b.power ?? 0)) / \(rated) W" : "Not charging",
                         hue: Module.battery.hue, hover: watts("Charge rate", "battery.power", .battery), valueWidth: 110)
                if input >= 0.5 {
                    MeterRow(label: "Adapter draw", fraction: input / Double(rated), value: "\(Fmt.watts(input)) / \(rated) W",
                             hue: Module.battery.hue, hover: watts("Adapter draw", "power.adapter", .battery), valueWidth: 110)
                }
            }
        }
        if let total = store.sensors.systemPower {
            Block(label: "Where power goes", trailing: "\(Fmt.watts(total)) total") {
                Row(label: "System total", value: Fmt.watts(total), hover: watts("System power", "power.system", .battery))
                ForEach(store.sensors.powerBreakdown) { part in
                    MeterRow(label: part.name, fraction: total > 0 ? part.watts / total : 0, value: Fmt.watts(part.watts),
                             hue: Module.battery.hue, hover: watts(part.name, "power.part.\(part.name)", .battery),
                             valueWidth: 70, labelWidth: 124)
                }
                if let input = store.sensors.adapterInput, input >= 0.5 {
                    Row(label: "Power adapter input", value: Fmt.watts(input), hover: watts("Power adapter input", "power.adapter", .battery))
                }
            }
        }
        if b.present {
            Block(label: "Battery") {
                Row(label: "Source", value: b.onAC ? "Adapter" : "Battery")
                if let w = b.adapterWatts, b.onAC { Row(label: "Adapter", value: "\(w) W") }
                if let p = b.power {
                    Row(label: b.isCharging ? "Charging" : "Draw", value: String(format: "%.1f W", p),
                        hover: watts(b.isCharging ? "Charging rate" : "Power draw", "battery.power", .battery))
                }
                if let v = b.voltage {
                    Row(label: "Voltage", value: String(format: "%.2f V", v),
                        hover: HoverSeries(title: "Battery voltage", key: "battery.voltage", hue: Module.battery.hue,
                                           format: { String(format: "%.2f V", $0) }))
                }
                if let t = b.temperature ?? store.sensors.battery {
                    Row(label: "Temperature", value: temp(t), hover: heat("Battery temperature", "temp.battery"))
                }
            }
        }
    }
}

// MARK: - Panel-specific pieces

/// Cluster name, meter against the chip's top speed, and the current average clock.
struct ClockRow: View {
    let reading: ClockReading
    let hue: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(reading.name).font(Typo.body).foregroundStyle(Theme.text).lineLimit(1).frame(width: 96, alignment: .leading)
            Meter(fraction: reading.fraction, hue: hue)
            let (now, top) = Fmt.clockPair(reading.isIdle ? nil : reading.mhz, reading.maxMHz)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                AnimatedValue(text: now)
                Text("/ " + top).font(Typo.value).foregroundStyle(Theme.label)
            }
            .fixedSize()
        }
    }
}

struct CoreColumns: View {
    let cores: [Double]
    let isEfficiency: [Bool]
    let hue: Color
    var hover: ((Int, Bool) -> HoverSeries)?

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(cores.enumerated()), id: \.offset) { index, load in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 1.5).fill(Theme.fill)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(hue.opacity(index < isEfficiency.count && isEfficiency[index] ? 0.5 : 1))
                        .frame(height: max(2, 30 * min(max(load, 0), 1)))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .animation(.easeOut(duration: 0.35), value: load)
                .hoverHistory(hover?(index, index < isEfficiency.count && isEfficiency[index]))
            }
        }
    }
}

private let compositionShades: [Double] = [1, 0.7, 0.45, 0.22, 0]

struct CompositionBar: View {
    let hue: Color
    let parts: [Double]

    var body: some View {
        GeometryReader { geo in
            let total = max(parts.reduce(0, +), 1)
            HStack(spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(compositionShades[i] == 0 ? Theme.fill : hue.opacity(compositionShades[i]))
                        .frame(width: max(0, (geo.size.width - 2 * CGFloat(parts.count - 1)) * part / total))
                }
            }
        }
        .frame(height: 6)
        .padding(.bottom, 4)
    }
}

struct SwatchRow: View {
    let label: String
    let value: String
    let shade: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(shade <= 0.1 ? Theme.fill : Module.memory.hue.opacity(shade))
                .frame(width: 8, height: 8)
            Text(label).font(Typo.body).foregroundStyle(Theme.text)
            Spacer()
            AnimatedValue(text: value)
        }
    }
}
