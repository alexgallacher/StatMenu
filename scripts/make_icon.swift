// Draws the StatMenu app icon at 1024×1024. Usage: swift make_icon.swift out.png
//
// The mark sits on a 24-unit grid: three rounded bars (a menu, and a small bar chart) where the middle
// bar ends early in a single dot, the live reading. See docs/brand for the standalone mark and wordmark.
import AppKit

let size: CGFloat = 1024
let bars: [(x0: CGFloat, cy: CGFloat, x1: CGFloat)] = [(3, 6, 21), (3, 12, 12.5), (3, 18, 16)]
let barHeight: CGFloat = 4
let dot = (cx: CGFloat(17.5), cy: CGFloat(12), r: CGFloat(2))
let ink = NSColor(srgbRed: 246 / 255, green: 246 / 255, blue: 247 / 255, alpha: 1)
let signal = NSColor(srgbRed: 47 / 255, green: 91 / 255, blue: 255 / 255, alpha: 1)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
// Work top-down like the grid.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

// macOS icon grid: an 824-pt tile inside the 1024 canvas.
let tile = CGRect(x: size * 0.098, y: size * 0.098, width: size * 0.804, height: size * 0.804)
let squircle = CGPath(roundedRect: tile, cornerWidth: size * 0.18, cornerHeight: size * 0.18, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.04, color: NSColor.black.withAlphaComponent(0.45).cgColor)
ctx.addPath(squircle)
ctx.setFillColor(NSColor.black.cgColor)
ctx.fillPath()
ctx.restoreGState()

// Graphite tile with a gentle top-to-bottom tone.
ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let tone = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
    NSColor(srgbRed: 42 / 255, green: 42 / 255, blue: 46 / 255, alpha: 1).cgColor,
    NSColor(srgbRed: 18 / 255, green: 18 / 255, blue: 20 / 255, alpha: 1).cgColor,
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(tone, start: CGPoint(x: 0, y: tile.minY), end: CGPoint(x: 0, y: tile.maxY), options: [])
ctx.restoreGState()

ctx.addPath(squircle)
ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
ctx.setLineWidth(size * 0.003)
ctx.strokePath()

// The mark, optically centred (the dot adds weight on the right, so shift slightly left).
let scale = tile.width * 0.62 / 24
let origin = CGPoint(x: tile.minX + (tile.width - 24 * scale) / 2 - scale * 0.3, y: tile.minY + (tile.height - 24 * scale) / 2)
ctx.setFillColor(ink.cgColor)
for bar in bars {
    let rect = CGRect(x: origin.x + bar.x0 * scale, y: origin.y + (bar.cy - barHeight / 2) * scale,
                      width: (bar.x1 - bar.x0) * scale, height: barHeight * scale)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil))
    ctx.fillPath()
}
ctx.setFillColor(signal.cgColor)
ctx.fillEllipse(in: CGRect(x: origin.x + (dot.cx - dot.r) * scale, y: origin.y + (dot.cy - dot.r) * scale,
                           width: dot.r * 2 * scale, height: dot.r * 2 * scale))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
