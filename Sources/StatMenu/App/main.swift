import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    Typo.registerFonts()
    let arguments = CommandLine.arguments
    if let index = arguments.firstIndex(of: "--render-previews"), index + 1 < arguments.count {
        PreviewRenderer.run(outputDirectory: arguments[index + 1])
        exit(0)
    }
    // Only one copy may run: a second launch would add a duplicate set of menu bar items.
    let lockDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("StatMenu", isDirectory: true)
    try? FileManager.default.createDirectory(at: lockDir, withIntermediateDirectories: true)
    let lockFD = open(lockDir.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, 0o644)
    if lockFD < 0 || flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
        exit(0)
    }
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
