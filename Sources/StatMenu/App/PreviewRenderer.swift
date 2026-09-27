import AppKit
import SwiftUI

/// `StatMenu --render-previews <dir>` writes PNGs of every dropdown and menu bar item. Used for visual QA.
@MainActor
enum PreviewRenderer {
    static func run(outputDirectory: String) {
        let store = SystemStore()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "StatMenu.previews")!)
        let sampler = Sampler()
        for _ in 0..<25 {
            store.apply(sampler.sampleNow())
            Thread.sleep(forTimeInterval: 0.4)
        }
        let dir = URL(fileURLWithPath: outputDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for scheme in [ColorScheme.dark, .light] {
            let suffix = scheme == .dark ? "dark" : "light"
            for module in Module.allCases {
                let view = DropdownView(content: .single(module), store: store, settings: settings)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, scheme)
                write(view, to: dir.appendingPathComponent("dropdown-\(module.rawValue)-\(suffix).png"))
            }
            let bar = HStack(spacing: 6) {
                MenuBarItemView(content: .combined, store: store, settings: settings)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.93))
            .environment(\.colorScheme, scheme)
            write(bar, to: dir.appendingPathComponent("menubar-\(suffix).png"))
        }
        let settingsView = SettingsView(settings: settings, store: store)
            .background(Color(nsColor: .windowBackgroundColor))
        write(settingsView, to: dir.appendingPathComponent("settings.png"))
    }

    private static func write<V: View>(_ view: V, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            print("failed to render \(url.lastPathComponent)")
            return
        }
        try? data.write(to: url)
        print("wrote \(url.path)")
    }
}
