import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let store: SystemStore
    @State private var tab: Tab = .general

    enum Tab: String, CaseIterable, Hashable {
        case general = "General", menuBar = "Menu bar", about = "About"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TabStrip(tabs: Tab.allCases, selection: $tab, title: \.rawValue)
                .padding(.horizontal, 28)
                .padding(.top, 18)
            ScrollView {
                Group {
                    switch tab {
                    case .general: GeneralSettings(settings: settings)
                    case .menuBar: MenuBarSettings(settings: settings, store: store)
                    case .about: AboutSettings(store: store)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.never)
        }
        .frame(width: 460, height: 540)
        .background(Theme.canvas)
        .toggleStyle(.switch)
        .tint(Theme.control)
    }
}

/// A settings section: small grey label, then list-style rows.
private struct SettingsSection<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(label).font(Typo.section).foregroundStyle(Theme.label)
            content
        }
        .padding(.bottom, 30)
    }
}

/// Title and description on the left (like the site's list items), control on the right.
private struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Typo.inter(13.5, .medium)).foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail).font(Typo.inter(12.5)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
    }
}

private struct GeneralSettings: View {
    @Bindable var settings: AppSettings
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var needsApproval = LoginItem.requiresApproval

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(label: "Startup") {
                SettingRow(title: "Launch at login", detail: "Start StatMenu when you log in to your Mac.") {
                    Toggle("", isOn: $launchAtLogin).labelsHidden().controlSize(.small)
                }
                if needsApproval {
                    SettingRow(title: "Approval needed", detail: "macOS is waiting for you to allow StatMenu in Login Items.") {
                        SolidButton(title: "Open Login Items") { LoginItem.openSystemSettings() }
                    }
                }
            }
            SettingsSection(label: "Readings") {
                SettingRow(title: "Refresh", detail: "How often readings update.") {
                    ChoiceGroup(options: [("1s", 1.0), ("2s", 2.0), ("3s", 3.0), ("5s", 5.0)], selection: $settings.updateInterval)
                }
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

private struct MenuBarSettings: View {
    @Bindable var settings: AppSettings
    let store: SystemStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(label: "Layout") {
                SettingRow(title: "Menu bar items",
                           detail: settings.combined
                               ? "One item takes the least room beside the notch. Its dropdown has a tab per module."
                               : "Hold ⌘ and drag items in the menu bar to rearrange them.") {
                    ChoiceGroup(options: [("Combined", true), ("Separate", false)], selection: $settings.combined)
                }
                SettingRow(title: "Labels", detail: "Show a small name above each reading.") {
                    Toggle("", isOn: $settings.showLabels).labelsHidden().controlSize(.small)
                }
                SettingRow(title: "Graphs", detail: "Add a small history line beside CPU and GPU.") {
                    Toggle("", isOn: $settings.showGraphs).labelsHidden().controlSize(.small)
                }
            }
            SettingsSection(label: "Modules") {
                ForEach(Module.allCases) { module in
                    SettingRow(title: module.title, detail: module.detail) {
                        Toggle("", isOn: Binding(get: { settings.isEnabled(module) }, set: { settings.setEnabled(module, $0) }))
                            .labelsHidden().controlSize(.small)
                    }
                    .overlay(alignment: .leading) {
                        Circle().fill(module.hue).frame(width: 6, height: 6).offset(x: -14, y: -9)
                    }
                }
            }
        }
    }
}

private struct AboutSettings: View {
    let store: SystemStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
            Text("StatMenu -- a quiet system monitor for your menu bar.")
                .font(Typo.inter(20)).foregroundStyle(Theme.ink)
            Text("CPU, GPU, memory, disks, network and temperatures at a glance, with the detail one click away.")
                .font(Typo.inter(13.5)).foregroundStyle(Theme.text)
            VStack(alignment: .leading, spacing: 7) {
                Row(label: "Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                Row(label: "Mac", value: "\(store.chipName) · \(Fmt.bytes(store.memory.total))")
                Row(label: "Uptime", value: Fmt.uptime(since: store.bootDate))
            }
            .padding(.top, 14)
        }
    }
}
