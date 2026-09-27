import SwiftUI

/// Describes the history graph shown when a value is hovered.
struct HoverSeries {
    let title: String
    let key: String
    let hue: Color
    let format: (Double) -> String
    var minValue: Double = 0
    var maxValue: Double?
}

/// Shows a history card beside the menu after the pointer rests on the view, like iStat Menus.
struct HistoryHover: ViewModifier {
    let series: HoverSeries?
    @Environment(SystemStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var hovering = false
    @State private var presented = false

    func body(content: Content) -> some View {
        if let series {
            content
                .background(
                    RoundedRectangle(cornerRadius: Theme.radius)
                        .fill(Theme.fill.opacity(hovering ? 0.7 : 0))
                        .padding(.horizontal, -6)
                        .padding(.vertical, -3)
                )
                .contentShape(Rectangle())
                .onHover { inside in
                    hovering = inside
                    if inside {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            if hovering { presented = true }
                        }
                    } else {
                        presented = false
                    }
                }
                .popover(isPresented: $presented, arrowEdge: .leading) {
                    HistoryCard(series: series, store: store, interval: settings.updateInterval)
                }
        } else {
            content
        }
    }
}

extension View {
    func hoverHistory(_ series: HoverSeries?) -> some View { modifier(HistoryHover(series: series)) }
}

private struct HistoryCard: View {
    let series: HoverSeries
    let store: SystemStore
    let interval: Double
    @AppStorage("historyRange") private var rangeRaw = HistoryRange.recent.rawValue

    var body: some View {
        let range = HistoryRange(rawValue: rangeRaw) ?? .recent
        let values = store.columns(series.key, range)
        let recent = values.compactMap { $0 }
        let current = (store.series[series.key] ?? History()).recent(1).last
        VStack(alignment: .leading, spacing: 10) {
            Text(series.title).font(Typo.title).foregroundStyle(Theme.ink)
            Text(current.map(series.format) ?? "—")
                .font(Typo.inter(26, .regular).monospacedDigit())
                .tracking(-0.8)
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.3), value: current ?? 0)
            BarHistory(values: values, minValue: series.minValue, maxValue: series.maxValue, hue: series.hue)
                .frame(height: 64)
                .id(range)
                .transition(.opacity)
            Text(range.caption(interval: interval)).font(Typo.caption).foregroundStyle(Theme.label)
            if !recent.isEmpty {
                StatStrip(items: [
                    Stat(label: "Min", value: series.format(recent.min()!)),
                    Stat(label: "Average", value: series.format(recent.reduce(0, +) / Double(recent.count))),
                    Stat(label: "Max", value: series.format(recent.max()!)),
                ])
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(Theme.canvas)
    }
}
