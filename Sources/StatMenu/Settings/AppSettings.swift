import Foundation
import Observation

@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onChange: (() -> Void)?

    var enabledModules: [Module] {
        didSet { defaults.set(enabledModules.map(\.rawValue), forKey: Keys.modules); onChange?() }
    }
    var updateInterval: Double {
        didSet { defaults.set(updateInterval, forKey: Keys.interval); onChange?() }
    }
    var useFahrenheit: Bool {
        didSet { defaults.set(useFahrenheit, forKey: Keys.fahrenheit); onChange?() }
    }
    var showGraphs: Bool {
        didSet { defaults.set(showGraphs, forKey: Keys.graphs); onChange?() }
    }
    var showLabels: Bool {
        didSet { defaults.set(showLabels, forKey: Keys.labels); onChange?() }
    }
    /// Network interface to measure (BSD name); nil follows the system's primary interface.
    var networkInterface: String? {
        didSet { defaults.set(networkInterface, forKey: Keys.interface); onChange?() }
    }
    /// Disk to measure (BSD name); nil means every physical disk.
    var diskSelection: String? {
        didSet { defaults.set(diskSelection, forKey: Keys.disk); onChange?() }
    }
    /// One status item holding every enabled module, instead of one item per module.
    var combined: Bool {
        didSet { defaults.set(combined, forKey: Keys.combined); onChange?() }
    }

    private enum Keys {
        static let modules = "enabledModules"
        static let interval = "updateInterval"
        static let fahrenheit = "useFahrenheit"
        static let graphs = "showGraphs"
        static let labels = "showLabels"
        static let combined = "combinedItem"
        static let interface = "networkInterface"
        static let disk = "diskSelection"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.stringArray(forKey: Keys.modules) {
            enabledModules = raw.compactMap(Module.init(rawValue:))
        } else {
            enabledModules = [.cpu, .gpu, .memory, .disk, .network, .sensors, .battery]
        }
        let interval = defaults.double(forKey: Keys.interval)
        updateInterval = interval > 0 ? interval : 2
        useFahrenheit = defaults.object(forKey: Keys.fahrenheit) as? Bool ?? (Locale.current.measurementSystem == .us)
        showGraphs = defaults.object(forKey: Keys.graphs) as? Bool ?? false
        showLabels = defaults.object(forKey: Keys.labels) as? Bool ?? true
        combined = defaults.object(forKey: Keys.combined) as? Bool ?? true
        networkInterface = defaults.string(forKey: Keys.interface)
        diskSelection = defaults.string(forKey: Keys.disk)
    }

    func isEnabled(_ module: Module) -> Bool { enabledModules.contains(module) }

    func setEnabled(_ module: Module, _ enabled: Bool) {
        if enabled, !isEnabled(module) {
            enabledModules = Module.allCases.filter { $0 == module || enabledModules.contains($0) }
        } else if !enabled {
            enabledModules.removeAll { $0 == module }
        }
    }
}
