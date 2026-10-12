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

    var body: some View {
        MenuBarItemContent(model: Self.model(content: content, store: store, settings: settings))
    }

    /// Everything the item draws, as plain values. The view renders from this, and `StatusItemController`
    /// compares it between ticks to skip re-rendering an item whose content hasn't changed.
    struct Model: Hashable {
        struct Cell: Hashable, Identifiable {
            let module: Module
            let label: String
            let value: String
            var color: Color = Theme.ink
            var width: CGFloat = 33
            var sparkline: [Double]?
            var id: Module { module }
        }
        let cells: [Cell]
        let showLabels: Bool
    }

    static func model(content: ItemContent, store: SystemStore, settings: AppSettings) -> Model {
        let modules: [Module] = switch content {
        case .combined: settings.enabledModules
        case .single(let m): [m]
        }
        let cells = modules.map { module -> Model.Cell in
            switch module {
            case .cpu:
                Model.Cell(module: .cpu, label: "CPU", value: Fmt.percent(store.cpu.total), color: Theme.level(store.cpu.total),
                           sparkline: settings.showGraphs ? zip(store.cpuUser.tail(16), store.cpuSystem.tail(16)).map(+) : nil)
            case .gpu:
                Model.Cell(module: .gpu, label: "GPU", value: Fmt.percent(store.gpu.utilization),
                           sparkline: settings.showGraphs ? store.gpuHistory.tail(16) : nil)
            case .memory:
                Model.Cell(module: .memory, label: "MEM", value: Fmt.percent(store.memory.usage),
                           color: Theme.pressure(store.memory.pressureLevel))
            case .disk:
                Model.Cell(module: .disk, label: "DISK", value: Fmt.percent(store.disk.root?.usage ?? 0))
            case .network:
                // Same pattern as every other item: dot + small label (upload) over the main value (download).
                Model.Cell(module: .network, label: "↑ " + Fmt.compactRate(store.network.upRate),
                           value: "↓ " + Fmt.compactRate(store.network.downRate), width: 42)
            case .sensors:
                Model.Cell(module: .sensors, label: "TEMP", value: Fmt.temperature(store.sensors.cpu, fahrenheit: settings.useFahrenheit),
                           color: Theme.heat(store.sensors.cpu), width: 28)
            case .battery:
                Model.Cell(module: .battery, label: "PWR",
                           value: store.battery.present ? Fmt.percent(store.battery.percent)
                               : store.sensors.systemPower.map { "\(Int($0.rounded()))W" } ?? "—")
            }
        }
        return Model(cells: cells, showLabels: settings.showLabels)
    }
}

/// Draws a menu bar item from its model alone, so a renderer given a new model draws it straight away.
struct MenuBarItemContent: View {
    let model: MenuBarItemView.Model

    var body: some View {
        HStack(spacing: 8) {
            ForEach(model.cells) { cell in
                HStack(spacing: 5) {
                    if let values = cell.sparkline { Sparkline(values: values, hue: cell.module.hue) }
                    MenuBarCell(label: cell.label, value: cell.value, hue: cell.module.hue, color: cell.color,
                                showLabel: model.showLabels, width: cell.width)
                }
            }
        }
        .padding(.horizontal, 3)
        .frame(height: 22)
        .fixedSize()
    }
}

/// Tiny label (with the module's hue dot) above the value — the one menu bar pattern.
struct MenuBarCell: View {
    let label: String
    let value: String
    let hue: Color
    var color: Color = Theme.ink
    let showLabel: Bool
    /// Wide enough for "100%" (32.2 pt in Inter 11 Medium) so values never truncate.
    var width: CGFloat = 33

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
