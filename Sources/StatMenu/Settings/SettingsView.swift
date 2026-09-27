import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let store: SystemStore
    @State private var page: Page = .general

    enum Page: String, CaseIterable, Identifiable {
        case general = "General", menuBar = "Menu bar", modules = "Modules", about = "About"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .menuBar: "menubar.rectangle"
            case .modules: "square.grid.2x2"
            case .about: "info.circle"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(page: $page)
            Rectangle().fill(Theme.stroke).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text(page.rawValue)
                        .font(Typo.inter(24, .semibold))
                        .tracking(-0.4)
                        .foregroundStyle(Theme.ink)
                    switch page {
                    case .general: GeneralPage(settings: settings)
                    case .menuBar: MenuBarPage(settings: settings)
                    case .modules: ModulesPage(settings: settings)
                    case .about: AboutPage(store: store)
                    }
                }
                .padding(.horizontal, 36)
                .padding(.top, 44)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .background(Theme.canvas)
        }
        .frame(minWidth: 760, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        .toggleStyle(.switch)
        .tint(Theme.control)
        .ignoresSafeArea()
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @Binding var page: SettingsView.Page

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 28, height: 28)
                Text("StatMenu").font(Typo.inter(15, .semibold)).foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 10)
            .padding(.top, 48)
            .padding(.bottom, 18)

            ForEach(SettingsView.Page.allCases) { item in
                SidebarItem(page: item, selected: page == item) { page = item }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(width: 200)
        .frame(maxHeight: .infinity)
        .background(Theme.canvas)
    }
}

private struct SidebarItem: View {
    let page: SettingsView.Page
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: page.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(page.rawValue).font(Typo.inter(13, selected ? .semibold : .medium))
                Spacer()
            }
            .foregroundStyle(selected ? Theme.ink : Theme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? Theme.fill : (hovering ? Theme.fill.opacity(0.5) : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Building blocks

/// A titled group of rows in a rounded card, separated by hairlines.
private struct SettingsCard<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(Typo.section).foregroundStyle(Theme.label).padding(.leading, 2)
            }
            VStack(spacing: 0) { content }
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
            if let footer {
                Text(footer).font(Typo.caption).foregroundStyle(Theme.label).padding(.leading, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Hairline between rows inside a card.
private struct CardDivider: View {
    var body: some View { Rectangle().fill(Theme.stroke).frame(height: 1).padding(.leading, 16) }
}

/// Title and description on the left, control on the right.
private struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    var hue: Color?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            if let hue {
                Circle().fill(hue).frame(width: 8, height: 8)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Typo.inter(13.5, .medium)).foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail).font(Typo.inter(12)).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            control
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

// MARK: - Pages

private struct GeneralPage: View {
    @Bindable var settings: AppSettings
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var needsApproval = LoginItem.requiresApproval

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            SettingsCard(title: "Startup") {
                SettingRow(title: "Launch at login", detail: "Start StatMenu when you log in to your Mac.") {
                    Toggle("", isOn: $launchAtLogin).labelsHidden()
                }
                if needsApproval {
                    CardDivider()
                    SettingRow(title: "Approval needed", detail: "macOS is waiting for you to allow StatMenu in Login Items.") {
                        SolidButton(title: "Open Login Items") { LoginItem.openSystemSettings() }
                    }
                }
            }
            SettingsCard(title: "Readings") {
                SettingRow(title: "Refresh", detail: "How often readings update. Faster uses slightly more energy.") {
                    ChoiceGroup(options: [("1s", 1.0), ("2s", 2.0), ("3s", 3.0), ("5s", 5.0)], selection: $settings.updateInterval)
                }
                CardDivider()
                SettingRow(title: "Temperature", detail: "Unit for every temperature reading.") {
                    ChoiceGroup(options: [("°C", false), ("°F", true)], selection: $settings.useFahrenheit)
                }
            }
        }
        .onChange(of: launchAtLogin) { _, newValue in
            guard newValue != LoginItem.isEnabled else { return }
            LoginItem.setEnabled(newValue)
            launchAtLogin = LoginItem.isEnabled
            needsApproval = LoginItem.requiresApproval
        }
        .onAppear {
            launchAtLogin = LoginItem.isEnabled
            needsApproval = LoginItem.requiresApproval
        }
    }
}

private struct MenuBarPage: View {
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            SettingsCard(title: "Layout",
                         footer: settings.combined
                            ? "One item takes the least room beside the notch. Its dropdown has a tab for each module."
                            : "Hold ⌘ and drag items in the menu bar to rearrange them.") {
                SettingRow(title: "Menu bar items", detail: "Show everything in one item, or one item per module.") {
                    ChoiceGroup(options: [("Combined", true), ("Separate", false)], selection: $settings.combined)
                }
            }
            SettingsCard(title: "Appearance") {
                SettingRow(title: "Labels", detail: "Show a small name above each reading.") {
                    Toggle("", isOn: $settings.showLabels).labelsHidden()
                }
                CardDivider()
                SettingRow(title: "Graphs", detail: "Add a small history line beside CPU and GPU.") {
                    Toggle("", isOn: $settings.showGraphs).labelsHidden()
                }
            }
        }
    }
}

private struct ModulesPage: View {
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsCard(footer: "Turned-off modules are hidden from the menu bar and the dropdown tabs.") {
            ForEach(Module.allCases) { module in
                if module != Module.allCases.first { CardDivider() }
                SettingRow(title: module.title, detail: module.detail, hue: module.hue) {
                    Toggle("", isOn: Binding(get: { settings.isEnabled(module) }, set: { settings.setEnabled(module, $0) }))
                        .labelsHidden()
                }
            }
        }
    }
}

private struct AboutPage: View {
    let store: SystemStore

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("A quiet system monitor for your menu bar.")
                        .font(Typo.inter(16, .medium)).foregroundStyle(Theme.ink)
                    Text("CPU, GPU, memory, disks, network, sensors and power at a glance, with the detail one click away.")
                        .font(Typo.inter(13)).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            UpdatesCard(updater: AppActions.shared.updater)
            SettingsCard(title: "This Mac") {
                SettingRow(title: "StatMenu version") { AnimatedValue(text: appVersion) }
                CardDivider()
                SettingRow(title: "macOS") { AnimatedValue(text: ProcessInfo.processInfo.operatingSystemVersionString) }
                CardDivider()
                SettingRow(title: "Chip") { AnimatedValue(text: store.chipName) }
                CardDivider()
                SettingRow(title: "Memory") { AnimatedValue(text: Fmt.bytes(store.memory.total)) }
                CardDivider()
                SettingRow(title: "Uptime") { AnimatedValue(text: Fmt.uptime(since: store.bootDate)) }
            }
            LinkButton(title: "View on GitHub") {
                NSWorkspace.shared.open(URL(string: "https://github.com/alexgallacher/StatMenu")!)
            }
        }
    }

    /// "1.0 (1)" from the app bundle's version and build number.
    private var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}

private struct UpdatesCard: View {
    @Bindable var updater: Updater

    var body: some View {
        SettingsCard(title: "Updates", footer: "Updates come from GitHub Releases and are checked against the publisher's signature before installing.") {
            SettingRow(title: status, detail: detail) {
                switch updater.state {
                case .available(let release):
                    SolidButton(title: "Install \(release.version)") { updater.install(release) }
                case .checking, .installing:
                    ProgressView().controlSize(.small)
                default:
                    SolidButton(title: "Check for updates") { updater.check() }
                }
            }
            CardDivider()
            SettingRow(title: "Check automatically", detail: "Look for a new version once a day.") {
                Toggle("", isOn: $updater.automaticallyChecks).labelsHidden()
            }
            CardDivider()
            SettingRow(title: "Install automatically", detail: "Download and install new versions without asking.") {
                Toggle("", isOn: $updater.automaticallyInstalls).labelsHidden()
            }
        }
    }

    private var status: String {
        switch updater.state {
        case .checking: "Checking for updates…"
        case .installing: "Installing update…"
        case .available(let r): "StatMenu \(r.version) is available"
        case .upToDate: "StatMenu is up to date"
        case .failed: "Couldn't check for updates"
        case .idle: "Version \(updater.currentVersion)"
        }
    }

    private var detail: String? {
        switch updater.state {
        case .failed(let message): message
        case .available: "You have \(updater.currentVersion)."
        default: updater.lastChecked.map { "Last checked \($0.formatted(.relative(presentation: .named)))." }
        }
    }
}
