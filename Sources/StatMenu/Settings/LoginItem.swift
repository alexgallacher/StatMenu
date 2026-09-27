import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService, falling back to a per-user LaunchAgent
/// when the system refuses to register an ad-hoc signed app.
enum LoginItem {
    private static let agentLabel = (Bundle.main.bundleIdentifier ?? "StatMenu") + ".launcher"
    private static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled || FileManager.default.fileExists(atPath: agentURL.path)
    }

    static var requiresApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            do {
                try SMAppService.mainApp.register()
                removeAgent()
            } catch {
                NSLog("StatMenu: SMAppService register failed (\(error)); installing LaunchAgent instead")
                installAgent()
            }
        } else {
            try? SMAppService.mainApp.unregister()
            removeAgent()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func installAgent() {
        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
        ]
        do {
            try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: agentURL)
        } catch {
            NSLog("StatMenu: failed to write LaunchAgent: \(error)")
        }
    }

    private static func removeAgent() {
        try? FileManager.default.removeItem(at: agentURL)
    }
}
