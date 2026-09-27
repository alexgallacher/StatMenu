import AppKit
import SwiftUI

// MARK: - Panel skeleton

/// Title row shared by every panel: module name on the left, context on the right.
struct PanelTitle: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Typo.title).foregroundStyle(Theme.ink)
            Spacer(minLength: 12)
            Text(detail).font(Typo.caption).foregroundStyle(Theme.label).lineLimit(1)
        }
    }
}

/// The single large reading of a panel.
struct Readout: View {
    let value: String
    var unit: String?
    var color: Color = Theme.ink

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value)
                .font(Typo.readout)
                .tracking(-1.4)
                .foregroundStyle(color)
                .contentTransition(.numericText())
            if let unit {
                Text(unit).font(Typo.readoutUnit).foregroundStyle(Theme.label)
            }
            Spacer(minLength: 0)
        }
        .animation(.snappy(duration: 0.3), value: value)
    }
}

/// A labelled group of content. Separation comes from whitespace, not rules.
struct Block<Content: View>: View {
    let label: String
    var trailing: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(Typo.section).foregroundStyle(Theme.label)
                Spacer()
                if let trailing {
                    Text(trailing).font(Typo.section.monospacedDigit()).foregroundStyle(Theme.label)
                }
            }
            content
        }
        .padding(.top, 6)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.stroke).frame(height: 1)
    }
}

/// Label on the left, value on the right.
struct Row: View {
    let label: String
    let value: String
    var valueColor: Color = Theme.ink
    var hover: HoverSeries?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(Typo.body).foregroundStyle(Theme.text).lineLimit(1)
            Spacer(minLength: 8)
            AnimatedValue(text: value, color: valueColor)
        }
        .hoverHistory(hover)
    }
}

/// A value that rolls its digits when it changes — used for every number in the dropdowns.
struct AnimatedValue: View {
    let text: String
    var color: Color = Theme.ink
    var font: Font = Typo.value

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.3), value: text)
    }
}

/// One entry in a `StatStrip`.
struct Stat {
    let label: String
    let value: String
    var hover: HoverSeries?
}

/// Row of small label-over-value pairs directly beneath a trace.
struct StatStrip: View {
    let items: [Stat]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.label).font(Typo.caption).foregroundStyle(Theme.label)
                    AnimatedValue(text: item.value)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .hoverHistory(item.hover)
            }
        }
    }
}

/// Thin horizontal bar in the module hue.
struct Meter: View {
    let fraction: Double
    let hue: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5).fill(Theme.fill)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(hue)
                    .frame(width: max(3, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 3)
        .animation(.easeOut(duration: 0.35), value: fraction)
    }
}

/// Label, meter and value on one line.
struct MeterRow: View {
    let label: String
    let fraction: Double
    let value: String
    let hue: Color
    var hover: HoverSeries?
    var valueWidth: CGFloat = 66
    var labelWidth: CGFloat = 96

    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(Typo.body).foregroundStyle(Theme.text).lineLimit(1).frame(width: labelWidth, alignment: .leading)
            Meter(fraction: fraction, hue: hue)
            AnimatedValue(text: value).frame(width: valueWidth, alignment: .trailing)
        }
        .hoverHistory(hover)
    }
}

// MARK: - History charts

/// Opacity for a column by age: the newest sample is full strength, older ones fade.
private func ageFade(_ i: Int, _ n: Int) -> Double { n > 1 ? 0.28 + 0.72 * Double(i) / Double(n - 1) : 1 }

private func column(_ ctx: GraphicsContext, x: CGFloat, width: CGFloat, from y0: CGFloat, to y1: CGFloat, color: Color) {
    let rect = CGRect(x: x, y: min(y0, y1), width: width, height: max(abs(y1 - y0), 0))
    guard rect.height > 0.2 else { return }
    ctx.fill(Path(roundedRect: rect, cornerRadius: min(width / 2, rect.height / 2)), with: .color(color))
}

/// A tape of slim columns, oldest on the left. `nil` columns (no data, e.g. the Mac was asleep) show only
/// a resting nub. `lower` is stacked beneath `values` in a softer tint.
struct BarHistory: View {
    let values: [Double?]
    var lower: [Double?]?
    var minValue: Double = 0
    var maxValue: Double?
    /// Zoom the vertical range around the recorded values, so slow trends (battery drain) are visible.
    var autoRange = false
    let hue: Color

    var body: some View {
        Canvas { ctx, size in
            let n = values.count
            guard n > 0 else { return }
            var minValue = minValue
            var maxValue = maxValue
            if autoRange {
                let recorded = values.compactMap { $0 }.filter { $0 > 0 }
                if let lo = recorded.min(), let hi = recorded.max() {
                    let pad = max(0.03, (hi - lo) * 0.5)
                    minValue = max(0, lo - pad)
                    maxValue = hi + pad * 0.4
                }
            }
            let totals = (0..<n).compactMap { i -> Double? in
                guard let v = values[i] else { return nil }
                return v + (lower?[i] ?? 0)
            }
            let peak = maxValue ?? max((totals.max() ?? 0) * 1.15, minValue + 0.0001)
            let pitch = size.width / CGFloat(n)
            let width = max(1.5, pitch * 0.6)
            func y(_ v: Double) -> CGFloat {
                size.height * (1 - CGFloat(min(max((v - minValue) / (peak - minValue), 0), 1)))
            }
            for i in 0..<n {
                let x = CGFloat(i) * pitch + (pitch - width) / 2
                let fade = ageFade(i, n)
                column(ctx, x: x, width: width, from: size.height, to: size.height - 2, color: Theme.fill)
                guard let top = values[i] else { continue }
                let base = lower?[i] ?? 0
                if lower != nil {
                    column(ctx, x: x, width: width, from: size.height, to: y(minValue + base), color: hue.opacity(0.4 * fade))
                }
                column(ctx, x: x, width: width, from: lower != nil ? y(minValue + base) : size.height,
                       to: y((lower != nil ? minValue + base : 0) + top), color: hue.opacity(fade))
            }
        }
    }
}

/// Columns mirrored around a centre gap: `top` rises in full hue, `bottom` falls in a softer tint.
struct MirrorBars: View {
    let top: [Double?]
    let bottom: [Double?]
    var minimumScale: Double = 10_000
    let hue: Color

    var body: some View {
        Canvas { ctx, size in
            let n = min(top.count, bottom.count)
            guard n > 0 else { return }
            let peak = max(top.compactMap { $0 }.max() ?? 0, bottom.compactMap { $0 }.max() ?? 0, minimumScale) * 1.1
            let pitch = size.width / CGFloat(n)
            let width = max(1.5, pitch * 0.6)
            let gap: CGFloat = 1.5
            let mid = size.height / 2
            let reach = mid - gap
            for i in 0..<n {
                let x = CGFloat(i) * pitch + (pitch - width) / 2
                let fade = ageFade(i, n)
                column(ctx, x: x, width: width, from: mid - gap, to: mid - gap - 1.5, color: Theme.fill)
                column(ctx, x: x, width: width, from: mid + gap, to: mid + gap + 1.5, color: Theme.fill)
                if let up = top[i] {
                    column(ctx, x: x, width: width, from: mid - gap, to: mid - gap - reach * CGFloat(min(up / peak, 1)),
                           color: hue.opacity(fade))
                }
                if let down = bottom[i] {
                    column(ctx, x: x, width: width, from: mid + gap, to: mid + gap + reach * CGFloat(min(down / peak, 1)),
                           color: hue.opacity(0.45 * fade))
                }
            }
        }
    }
}

/// The range switcher under every chart ("2m · 1h · 24h · 7d"), shared by all panels and hover cards.
struct RangePicker: View {
    let interval: Double
    @AppStorage("historyRange") private var rangeRaw = HistoryRange.recent.rawValue

    var body: some View {
        let selected = HistoryRange(rawValue: rangeRaw) ?? .recent
        HStack(spacing: 10) {
            ForEach(HistoryRange.allCases) { range in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { rangeRaw = range.rawValue }
                } label: {
                    Text(range.shortLabel(interval: interval))
                        .font(Typo.inter(11.5, range == selected ? .semibold : .regular))
                        .foregroundStyle(range == selected ? Theme.ink : Theme.label)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(range.caption(interval: interval))
            }
        }
    }
}

/// Row under a chart: the range switcher on the left, a summary (peak or legend) on the right.
struct ChartCaption: View {
    let interval: Double
    var peak: String?

    var body: some View {
        HStack {
            RangePicker(interval: interval)
            Spacer()
            if let peak {
                Text(peak).font(Typo.caption.monospacedDigit()).foregroundStyle(Theme.label)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.3), value: peak)
            }
        }
    }
}

/// Peak of the non-empty columns.
func columnPeak(_ values: [Double?]) -> Double? { values.compactMap { $0 }.max() }

// MARK: - Navigation & controls

/// Text navigation like oliur.com's header: grey links, the current one in ink with a hue dot beneath.
struct TabStrip<Tab: Hashable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    let title: (Tab) -> String
    var hue: (Tab) -> Color = { _ in Theme.ink }
    var spacing: CGFloat = 16
    @Namespace private var marker

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(tabs, id: \.self) { tab in
                let selected = tab == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = tab }
                } label: {
                    VStack(spacing: 5) {
                        Text(title(tab))
                            .font(Typo.link)
                            .foregroundStyle(selected ? Theme.ink : Theme.label)
                        ZStack {
                            Circle().fill(.clear).frame(width: 4, height: 4)
                            if selected {
                                Circle().fill(hue(tab)).frame(width: 4, height: 4)
                                    .matchedGeometryEffect(id: "marker", in: marker)
                            }
                        }
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Text link with the site's trailing arrow.
struct LinkButton: View {
    let title: String
    var arrow = true
    var prominent = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(arrow ? "\(title) ->" : title)
                .font(Typo.link)
                .foregroundStyle(prominent || hovering ? Theme.ink : Theme.label)
                .opacity(hovering && prominent ? 0.7 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Solid dark button (the site's "Subscribe" style).
struct SolidButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typo.link)
                .foregroundStyle(Theme.onControl)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.control))
        }
        .buttonStyle(.plain)
    }
}

/// Segmented choice built from the site's fill + solid styles.
struct ChoiceGroup<Value: Hashable>: View {
    let options: [(String, Value)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.1 == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = option.1 }
                } label: {
                    Text(option.0)
                        .font(Typo.link)
                        .foregroundStyle(selected ? Theme.onControl : Theme.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(selected ? Theme.control : Theme.fill))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Processes

enum ProcessNames {
    static func name(for entry: ProcessEntry) -> String {
        NSRunningApplication(processIdentifier: entry.pid)?.localizedName ?? entry.name
    }
}

struct ProcessRows: View {
    let entries: [ProcessEntry]
    let value: (ProcessEntry) -> String

    var body: some View {
        VStack(spacing: 7) {
            if entries.isEmpty {
                Text("Reading processes…").font(Typo.body).foregroundStyle(Theme.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(entries.prefix(5)) { entry in
                Row(label: ProcessNames.name(for: entry), value: value(entry))
            }
            .animation(.snappy(duration: 0.3), value: entries.prefix(5).map(\.pid))
        }
    }
}
