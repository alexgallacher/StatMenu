import SwiftUI

/// What a status item shows: every enabled module side by side, or a single module.
enum ItemContent: Hashable {
    case combined
    case single(Module)
}

struct MenuBarItemView: View {
    let content: ItemContent
    let store: SystemStore
    let settings: AppSettings

    private var modules: [Module] {
        switch content {
        case .combined: settings.enabledModules
        case .single(let m): [m]
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(modules) { cell(for: $0) }
        }
        .padding(.horizontal, 5)
        .frame(height: 22)
        .fixedSize()
    }

    @ViewBuilder private func cell(for module: Module) -> some View {
        switch module {
        case .cpu:
            HStack(spacing: 5) {
                if settings.showGraphs { Sparkline(values: zip(store.cpuUser.tail(16), store.cpuSystem.tail(16)).map(+), hue: Module.cpu.hue) }
                MenuBarCell(label: "CPU", value: Fmt.percent(store.cpu.total), hue: Module.cpu.hue, color: Theme.level(store.cpu.total),
                            showLabel: settings.showLabels)
            }
        case .gpu:
            HStack(spacing: 5) {
                if settings.showGraphs { Sparkline(values: store.gpuHistory.tail(16), hue: Module.gpu.hue) }
                MenuBarCell(label: "GPU", value: Fmt.percent(store.gpu.utilization), hue: Module.gpu.hue, showLabel: settings.showLabels)
            }
        case .memory:
            MenuBarCell(label: "MEM", value: Fmt.percent(store.memory.usage), hue: Module.memory.hue,
                        color: Theme.pressure(store.memory.pressureLevel), showLabel: settings.showLabels)
        case .disk:
            MenuBarCell(label: "DISK", value: Fmt.percent(store.disk.root?.usage ?? 0), hue: Module.disk.hue, showLabel: settings.showLabels)
        case .network:
            HStack(alignment: .top, spacing: 3) {
                Circle().fill(Module.network.hue).frame(width: 4, height: 4).padding(.top, 3)
                VStack(alignment: .trailing, spacing: -1) {
                    Text(Fmt.compactRate(store.network.upRate) + " ↑")
                    Text(Fmt.compactRate(store.network.downRate) + " ↓")
                }
                .font(Typo.inter(9, .medium).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .frame(width: 38, alignment: .trailing)
            }
        case .sensors:
            MenuBarCell(label: "TEMP", value: Fmt.temperature(store.sensors.cpu, fahrenheit: settings.useFahrenheit), hue: Module.sensors.hue,
                        color: Theme.heat(store.sensors.cpu), showLabel: settings.showLabels, width: 34)
        case .battery:
            MenuBarCell(label: "PWR",
                        value: store.battery.present ? Fmt.percent(store.battery.percent)
                            : store.sensors.systemPower.map { "\(Int($0.rounded()))W" } ?? "—",
                        hue: Module.battery.hue, showLabel: settings.showLabels)
        }
    }
}

/// Tiny label (with the module's hue dot) above the value — the one menu bar pattern.
struct MenuBarCell: View {
    let label: String
    let value: String
    let hue: Color
    var color: Color = Theme.ink
    let showLabel: Bool
    var width: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: -1.5) {
            if showLabel {
                HStack(spacing: 3) {
                    Circle().fill(hue).frame(width: 4, height: 4)
                    Text(label)
                        .font(Typo.inter(7, .semibold))
                        .tracking(0.3)
                        .foregroundStyle(Theme.ink.opacity(0.6))
                }
            }
            Text(value)
                .font(Typo.inter(showLabel ? 11 : 12, .medium).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(width: width, alignment: .leading)
    }
}

/// Menu bar sized trace with the same accent end point as the dropdown graphs.
struct Sparkline: View {
    let values: [Double]
    let hue: Color

    var body: some View {
        Canvas { ctx, size in
            let n = values.count
            guard n > 1 else { return }
            let w = size.width - 3
            func pt(_ i: Int) -> CGPoint {
                CGPoint(x: w * CGFloat(i) / CGFloat(n - 1), y: size.height - 1.5 - (size.height - 3) * CGFloat(min(max(values[i], 0), 1)))
            }
            var p = Path()
            p.move(to: pt(0))
            for i in 1..<n { p.addLine(to: pt(i)) }
            ctx.stroke(p, with: .color(hue), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            let end = pt(n - 1)
            ctx.fill(Path(ellipseIn: CGRect(x: end.x - 1.75, y: end.y - 1.75, width: 3.5, height: 3.5)), with: .color(hue))
        }
        .frame(width: 24, height: 14)
    }
}
