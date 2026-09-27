import SwiftUI

enum Module: String, CaseIterable, Identifiable, Codable {
    case cpu, gpu, memory, disk, network, sensors, battery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .disk: "Disks"
        case .network: "Network"
        case .sensors: "Sensors"
        case .battery: "Power"
        }
    }

    var shortLabel: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "MEM"
        case .disk: "DISK"
        case .network: "NET"
        case .sensors: "CPU"
        case .battery: "PWR"
        }
    }

    var detail: String {
        switch self {
        case .cpu: "Usage history, per-core load and top processes"
        case .gpu: "Graphics utilization and memory"
        case .memory: "Pressure, composition, swap and top processes"
        case .disk: "Volume capacity and read/write activity"
        case .network: "Upload and download speeds, interface details"
        case .sensors: "Temperatures and fan speeds"
        case .battery: "Battery, charging and where system power goes"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "cube.transparent"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "network"
        case .sensors: "thermometer.medium"
        case .battery: "bolt"
        }
    }


    /// The one hue this module's data marks use everywhere (menu bar dot, trace, meters).
    var hue: Color {
        switch self {
        case .cpu: Theme.dynamic(0x0F4BF1, 0x5B80FF)
        case .gpu: Theme.dynamic(0x7C4DFF, 0xA38BFF)
        case .memory: Theme.dynamic(0x0E9F6E, 0x34C38F)
        case .disk: Theme.dynamic(0xD97706, 0xF5A524)
        case .network: Theme.dynamic(0x0891B2, 0x22C3E6)
        case .sensors: Theme.dynamic(0xE5484D, 0xFF6B6F)
        case .battery: Theme.dynamic(0x16A34A, 0x4ADE80)
        }
    }

    var processSort: ProcessSort? {
        switch self {
        case .cpu: .cpu
        case .memory: .memory
        default: nil
        }
    }
}

