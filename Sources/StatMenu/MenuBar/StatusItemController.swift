import AppKit
import SwiftUI

/// Receives the dropdown's measured content size from SwiftUI.
private final class SizeReporter {
    var onChange: ((CGSize) -> Void)?
}

/// Borderless panel that can take key status (for Esc) without activating the app.
private final class DropdownPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(sender) }
}

@MainActor
final class StatusItemController: NSObject {
    let content: ItemContent
    private let statusItem: NSStatusItem
    private let store: SystemStore
    /// Persistent renderers update incrementally; recreating them rebuilds the view graph every tick.
    private var lightRenderer: ImageRenderer<AnyView>?
    private var darkRenderer: ImageRenderer<AnyView>?
    private var lastImageKey: Data?
    private let panel: DropdownPanel
    private let dropdownView: NSHostingView<AnyView>
    private let sizeReporter = SizeReporter()
    private var contentSize = CGSize(width: 340, height: 400)
    /// Builds the dropdown content. It is only attached while the panel is open, so a closed
    /// dropdown costs nothing when the store updates.
    private let makeDropdown: () -> AnyView
    private let sampler: Sampler
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var panelTop: CGFloat = 0
    var onOpen: ((StatusItemController) -> Void)?

    private let settings: AppSettings

    init(content: ItemContent, store: SystemStore, settings: AppSettings, sampler: Sampler) {
        self.content = content
        self.sampler = sampler
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        switch content {
        case .combined: statusItem.autosaveName = "StatMenu.combined"
        case .single(let m): statusItem.autosaveName = "StatMenu.\(m.rawValue)"
        }
        self.store = store

        // The content is measured at its natural height and pinned to the top, so the panel can
        // follow it exactly and the tab strip never shifts when a shorter tab is selected.
        let reporter = sizeReporter
        makeDropdown = { AnyView(DropdownView(content: content, store: store, settings: settings)
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { reporter.onChange?(geo.size) }
                    .onChange(of: geo.size) { _, size in reporter.onChange?(size) }
            })
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1)))
        }
        dropdownView = NSHostingView(rootView: AnyView(EmptyView()))
        dropdownView.sizingOptions = []
        panel = DropdownPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()

        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(toggle)
            if case .single(let m) = content { button.setAccessibilityTitle(m.title) } else { button.setAccessibilityTitle("StatMenu") }
        }
        configurePanel()
        refresh()
    }

    func remove() {
        close()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// Renders the menu bar content to an image. A static image is far cheaper for macOS to mirror into
    /// its menu bar copies than a live view. Light and dark renderings are chosen at draw time, because
    /// each copy (one per display) can have a different menu bar appearance.
    func refresh() {
        guard let button = statusItem.button else { return }
        let scale = button.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        func renderer(_ scheme: ColorScheme) -> ImageRenderer<AnyView> {
            let r = ImageRenderer(content: AnyView(MenuBarItemView(content: content, store: store, settings: settings)
                .environment(\.colorScheme, scheme)))
            r.scale = scale
            return r
        }
        if lightRenderer == nil || lightRenderer?.scale != scale {
            lightRenderer = renderer(.light)
            darkRenderer = renderer(.dark)
        }
        guard let light = lightRenderer?.cgImage, let dark = darkRenderer?.cgImage else { return }
        // Skip the update entirely when the pixels haven't changed (e.g. same readings as last tick).
        if let key = light.dataProvider?.data as Data?, let darkKey = dark.dataProvider?.data as Data? {
            let combined = key + darkKey
            if combined == lastImageKey { return }
            lastImageKey = combined
        }
        let size = NSSize(width: CGFloat(light.width) / scale, height: CGFloat(light.height) / scale)
        let image = NSImage(size: size, flipped: false) { rect in
            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            NSGraphicsContext.current?.cgContext.draw(isDark ? dark : light, in: rect)
            return true
        }
        button.image = image
        if statusItem.length != size.width { statusItem.length = size.width }
    }

    // MARK: Panel

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow

        // SwiftUI draws the solid canvas; the container only clips to the rounded shape.
        let effect = NSView()
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        dropdownView.autoresizingMask = [.width, .height]
        effect.addSubview(dropdownView)
        panel.contentView = effect

        sizeReporter.onChange = { [weak self] size in
            guard let self, size.height > 0 else { return }
            self.contentSize = size
            self.relayout()
        }
    }

    @objc private func toggle() {
        if panel.isVisible { close() } else { open() }
    }

    func open() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        onOpen?(self)
        dropdownView.rootView = makeDropdown()
        dropdownView.layoutSubtreeIfNeeded()
        let modules: [Module] = if case .single(let m) = content { [m] } else { settings.enabledModules }
        sampler.setProcessesWanted(modules.contains { [.cpu, .memory, .disk].contains($0) })

        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        var anchor = buttonRect.midX
        panelTop = buttonRect.minY - 4
        // An item hidden in the menu bar overflow has no on-screen button; open under the right edge instead.
        if let screen, !screen.frame.contains(buttonRect) || !buttonWindow.occlusionState.contains(.visible) {
            anchor = screen.visibleFrame.maxX - 170
            panelTop = screen.visibleFrame.maxY - 4
        }
        panel.setFrame(frame(for: contentSize, anchorX: anchor, screen: screen), display: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            panel.animator().alphaValue = 1
        }, completionHandler: { [weak panel] in
            MainActor.assumeIsolated { panel?.alphaValue = 1 }
        })
        button.highlight(true)
        installMonitors()
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        dropdownView.rootView = AnyView(EmptyView())
        statusItem.button?.highlight(false)
        removeMonitors()
        sampler.setProcessesWanted(false)
    }

    private var anchorX: CGFloat = 0

    private func frame(for size: NSSize, anchorX: CGFloat, screen: NSScreen?) -> NSRect {
        self.anchorX = anchorX
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? .zero
        var x = anchorX - size.width / 2
        x = min(max(x, visible.minX + 6), visible.maxX - size.width - 6)
        let height = min(size.height, panelTop - visible.minY - 6)
        return NSRect(x: x, y: panelTop - height, width: size.width, height: height)
    }

    private func relayout() {
        guard panel.isVisible else { return }
        let newFrame = frame(for: contentSize, anchorX: anchorX, screen: panel.screen)
        if newFrame != panel.frame {
            panel.setFrame(newFrame, display: true)
            panel.invalidateShadow()
        }
    }

    private func installMonitors() {
        removeMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.window !== self.panel && event.window !== self.statusItem.button?.window {
                    self.close()
                }
            }
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }
}
