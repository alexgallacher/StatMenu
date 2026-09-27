import CoreWLAN
import Foundation

/// Wi-Fi link details for the primary interface. macOS only returns the network name (SSID)
/// to apps the user has granted Location access.
final class WiFiMonitor {
    private let client = CWWiFiClient.shared()

    func sample(primaryInterface: String?) -> WiFiInfo? {
        guard let iface = client.interface(), let name = iface.interfaceName, name == primaryInterface,
              iface.powerOn() else { return nil }
        var info = WiFiInfo(ssid: iface.ssid(), rssi: iface.rssiValue(), noise: iface.noiseMeasurement(),
                            transmitRate: iface.transmitRate())
        if let channel = iface.wlanChannel() {
            info.channel = channel.channelNumber
            info.bandGHz = switch channel.channelBand {
            case .band2GHz: "2.4 GHz"
            case .band5GHz: "5 GHz"
            case .band6GHz: "6 GHz"
            default: nil
            }
            info.widthMHz = switch channel.channelWidth {
            case .width20MHz: 20
            case .width40MHz: 40
            case .width80MHz: 80
            case .width160MHz: 160
            default: nil
            }
        }
        info.standard = switch iface.activePHYMode() {
        case .mode11a: "802.11a"
        case .mode11b: "802.11b"
        case .mode11g: "802.11g"
        case .mode11n: "Wi-Fi 4 (802.11n)"
        case .mode11ac: "Wi-Fi 5 (802.11ac)"
        case .mode11ax: "Wi-Fi 6 (802.11ax)"
        default: nil
        }
        info.security = switch iface.security() {
        case .none: "None"
        case .WEP, .dynamicWEP: "WEP"
        case .wpaPersonal, .wpaPersonalMixed: "WPA Personal"
        case .wpa2Personal, .personal: "WPA2 Personal"
        case .wpa3Personal: "WPA3 Personal"
        case .wpa3Transition: "WPA2/WPA3 Personal"
        case .wpaEnterprise, .wpaEnterpriseMixed: "WPA Enterprise"
        case .wpa2Enterprise, .enterprise: "WPA2 Enterprise"
        case .wpa3Enterprise: "WPA3 Enterprise"
        default: nil
        }
        return info
    }
}
