import AppKit
import SwiftUI

/// Design tokens, after oliur.com: a flat neutral canvas, Inter, tight radii, whitespace instead of rules.
/// Colour is reserved for data: each module owns one hue (`Module.hue`).
enum Theme {
    static let canvas = dynamic(0xFAFAFA, 0x161616)
    static let ink = dynamic(0x262626, 0xEDEDED)
    static let text = dynamic(0x666666, 0xA3A3A3)
    static let label = dynamic(0x737373, 0x8A8A8A)
    static let fill = dynamic(0xE5E5E5, 0x2A2A2A)
    static let stroke = dynamic(0x000000, 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.10)
    static let control = dynamic(0x262626, 0xEDEDED)
    static let onControl = dynamic(0xFFFFFF, 0x161616)
    static let warn = Color(nsColor: .systemOrange)
    static let critical = Color(nsColor: .systemRed)
    static let radius: CGFloat = 3

    static func dynamic(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }

    /// Text colour for a value: neutral unless it needs attention.
    static func heat(_ celsius: Double?) -> Color {
        guard let c = celsius else { return ink }
        if c >= 95 { return critical }
        if c >= 80 { return warn }
        return ink
    }

    static func level(_ fraction: Double) -> Color {
        if fraction >= 0.95 { return critical }
        if fraction >= 0.85 { return warn }
        return ink
    }

    static func pressure(_ level: Int) -> Color {
        switch level {
        case 4...: critical
        case 2...: warn
        default: ink
        }
    }
}

enum Typo {
    static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Inter", size: size).weight(weight)
    }

    static let readout = inter(40, .regular).monospacedDigit()
    static let readoutUnit = inter(15, .medium)
    static let title = inter(14, .semibold)
    static let section = inter(11.5, .semibold)
    static let body = inter(12.5)
    static let value = inter(12.5, .medium).monospacedDigit()
    static let caption = inter(11.5)
    static let link = inter(12, .semibold)

    /// Registers the bundled Inter so the app doesn't depend on it being installed.
    static func registerFonts() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") else { return }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }
}
