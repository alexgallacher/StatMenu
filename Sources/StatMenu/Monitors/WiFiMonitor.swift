import CoreWLAN
import Foundation

/// Wi-Fi link details for the primary interface. macOS only returns the network name (SSID)
/// to apps the user has granted Location access.
///
/// Every CoreWLAN getter is an XPC round-trip to the Wi-Fi daemon, and `security()` is especially costly
/// (it looks up the last joined network). Nothing here is shown in the menu bar, so while every dropdown is
/// closed only the link metrics are refreshed, every fifth call, to keep the hover history going.
final class WiFiMonitor {
    private let client = CWWiFiClient.shared()
    private var cached: WiFiInfo?
    private var cachedInterface: String?
    private var countdown = 0
    /// Security and PHY mode only change on (re)association, which also changes the channel or SSID.
    private var detailsKey: (ssid: String?, channel: Int?)?

    /// `detailed` (a dropdown is open) refreshes every call; otherwise every fifth call, link metrics only.
    func sample(primaryInterface: String?, detailed: Bool = false) -> WiFiInfo? {
        guard detailed || countdown <= 0 || primaryInterface != cachedInterface else {
            countdown -= 1
            return cached
        }
        countdown = 4
        cachedInterface = primaryInterface
        guard let iface = client.interface(), let name = iface.interfaceName, name == primaryInterface,
              iface.powerOn() else {
            cached = nil
            detailsKey = nil
            return nil
        }
        var info = cached ?? WiFiInfo(ssid: nil, rssi: 0, noise: 0, transmitRate: 0)
        info.rssi = iface.rssiValue()
        info.noise = iface.noiseMeasurement()
        info.transmitRate = iface.transmitRate()
        guard detailed || cached == nil else {
            cached = info
            return info
        }

        info.ssid = iface.ssid()
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
        } else {
            info.channel = nil
            info.bandGHz = nil
            info.widthMHz = nil
        }
        if let key = detailsKey, key.ssid == info.ssid, key.channel == info.channel, cached != nil {
            cached = info
            return info
        }
        detailsKey = (info.ssid, info.channel)
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
        cached = info
        return info
    }
}
