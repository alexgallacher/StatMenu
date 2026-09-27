import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let store = SystemStore()
    private let sampler = Sampler()
    private var controllers: [ItemContent: StatusItemController] = [:]
    private var settingsWindow: NSWindow?
    private var appliedInterval: Double = 0
    private var saveTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppActions.shared.openSettingsHandler = { [weak self] in self?.showSettings() }
        AppActions.shared.updater.start()

        store.longTerm.load()
        store.dataUsage.load()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.store.longTerm.save()
                self?.store.dataUsage.save()
            }
        }
        saveTimer?.tolerance = 30

        sampler.onSnapshot = { [weak self] snapshot in
            guard let self else { return }
            self.store.apply(snapshot)
            self.controllers.values.forEach { $0.refresh() }
        }
        sampler.setNetworkInterface(settings.networkInterface)
        sampler.setDiskSelection(settings.diskSelection)
        restartSampler()

        syncStatusItems()
        settings.onChange = { [weak self] in self?.settingsChanged() }

        let firstRunKey = "didConfigureLaunchAtLogin"
        if !UserDefaults.standard.bool(forKey: firstRunKey) {
            UserDefaults.standard.set(true, forKey: firstRunKey)
            LoginItem.setEnabled(true)
        }

        // QA hook: `--open <module>` opens that module's dropdown shortly after launch.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--open"), i + 1 < args.count, let module = Module(rawValue: args[i + 1]) {
            UserDefaults.standard.set(module.rawValue, forKey: "selectedTab")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                (self?.controllers[.single(module)] ?? self?.controllers[.combined])?.open()
            }
            // `--switch <module>` then changes tab, to check the panel re-anchors correctly.
            if let j = args.firstIndex(of: "--switch"), j + 1 < args.count, let next = Module(rawValue: args[j + 1]) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    UserDefaults.standard.set(next.rawValue, forKey: "selectedTab")
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.longTerm.save(synchronously: true)
        store.dataUsage.save(synchronously: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func restartSampler() {
        appliedInterval = settings.updateInterval
        sampler.start(interval: settings.updateInterval)
    }

    private func settingsChanged() {
        if settings.updateInterval != appliedInterval { restartSampler() }
        sampler.setNetworkInterface(settings.networkInterface)
        sampler.setDiskSelection(settings.diskSelection)
        syncStatusItems()
        controllers.values.forEach { $0.refresh() }
    }

    /// Creates/removes status items to match settings. Separate items are created right-to-left so the
    /// default order in the menu bar matches `Module.allCases`.
    private func syncStatusItems() {
        let wanted: [ItemContent] = settings.enabledModules.isEmpty ? [] :
            (settings.combined ? [.combined] : Module.allCases.reversed().filter(settings.isEnabled).map { .single($0) })
        for (content, controller) in controllers where !wanted.contains(content) {
            controller.remove()
            controllers[content] = nil
        }
        for content in wanted where controllers[content] == nil {
            let controller = StatusItemController(content: content, store: store, settings: settings, sampler: sampler)
            controller.onOpen = { [weak self] opened in
                self?.controllers.values.filter { $0 !== opened }.forEach { $0.close() }
            }
            controllers[content] = controller
        }
    }

    private func showSettings() {
        controllers.values.forEach { $0.close() }
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: settings, store: store))
            let window = NSWindow(contentViewController: hosting)
            window.title = "StatMenu Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            hosting.sizingOptions = [.minSize]
            window.setContentSize(NSSize(width: 760, height: 560))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
