import AppKit
import CoreLocation
import Observation

/// macOS only reveals the Wi-Fi network name to apps with Location access. StatMenu asks only when the
/// user chooses to, and never reads the location itself.
@Observable
final class LocationAccess: NSObject, CLLocationManagerDelegate {
    static let shared = LocationAccess()
    @ObservationIgnored private let manager = CLLocationManager()
    private(set) var status: CLAuthorizationStatus

    override private init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var isGranted: Bool { status == .authorizedAlways || status == .authorized }
    var isDenied: Bool { status == .denied || status == .restricted }

    func request() {
        if isDenied {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
        } else {
            NSApp.activate()
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
    }
}
