import AppKit
import SwiftUI

/// Root of a dropdown. A single module shows its panel; the combined item adds a tab strip.
struct DropdownView: View {
    let content: ItemContent
    let store: SystemStore
    let settings: AppSettings

    private var modules: [Module] {
        switch content {
        case .combined: settings.enabledModules
        case .single(let m): [m]
        }
    }
    @AppStorage("selectedTab") private var selectedRaw = Module.cpu.rawValue

    private var selected: Module {
        if let m = Module(rawValue: selectedRaw), modules.contains(m) { return m }
        return modules.first ?? .cpu
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if modules.count > 1 {
                let binding = Binding(get: { selected }, set: { selectedRaw = $0.rawValue })
                ViewThatFits(in: .horizontal) {
                    TabStrip(tabs: modules, selection: binding, title: \.tabTitle, hue: \.hue, spacing: 16)
                    TabStrip(tabs: modules, selection: binding, title: \.tabTitle, hue: \.hue, spacing: 11)
                    ScrollView(.horizontal) {
                        TabStrip(tabs: modules, selection: binding, title: \.tabTitle, hue: \.hue, spacing: 11)
                    }
                    .scrollIndicators(.never)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }
            ModulePanel(module: selected, store: store, settings: settings)
                .padding(.horizontal, 20)
                .padding(.top, modules.count > 1 ? 14 : 20)
                .padding(.bottom, 22)
            DropdownFooter()
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Theme.fill.opacity(0.45))
        }
        .frame(width: 340)
        .background(Theme.canvas)
        .environment(store)
        .environment(settings)
    }
}

extension Module {
    var tabTitle: String {
        switch self {
        case .memory: "Memory"
        case .network: "Network"
        case .sensors: "Temp"
        case .disk: "Disk"
        case .battery: "Power"
        default: title
        }
    }
}

struct DropdownFooter: View {
    var body: some View {
        HStack(spacing: 16) {
            LinkButton(title: "Activity Monitor") { AppActions.shared.openActivityMonitor() }
            Spacer()
            LinkButton(title: "Settings", arrow: false, prominent: false) { AppActions.shared.openSettings() }
            LinkButton(title: "Quit", arrow: false, prominent: false) { AppActions.shared.quit() }
        }
    }
}

/// Global actions reachable from any SwiftUI view.
@MainActor
final class AppActions {
    static let shared = AppActions()
    var openSettingsHandler: () -> Void = {}

    func openSettings() { openSettingsHandler() }

    func quit() { NSApp.terminate(nil) }

    func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
