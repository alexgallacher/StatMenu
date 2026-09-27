// Draws the StatMenu app icon at 1024×1024: a dotted ring gauge on a dark tile. Usage: swift make_icon.swift out.png
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.3).cgColor)
ctx.addPath(squircle)
ctx.setFillColor(NSColor(srgbRed: 0x1C / 255, green: 0x1C / 255, blue: 0x1C / 255, alpha: 1).cgColor)
ctx.fillPath()
ctx.restoreGState()

let center = CGPoint(x: tile.midX, y: tile.midY)
let dots = 28, lit = 19
let radius: CGFloat = 250, dot: CGFloat = 46
for i in 0..<dots {
    let angle = Double.pi / 2 - Double(i) / Double(dots) * 2 * .pi
    let p = CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
    let color = i < lit ? NSColor(srgbRed: 0x5B / 255, green: 0x80 / 255, blue: 1, alpha: 1) : NSColor.white.withAlphaComponent(0.16)
    ctx.setFillColor(color.cgColor)
    ctx.fillEllipse(in: CGRect(x: p.x - dot / 2, y: p.y - dot / 2, width: dot, height: dot))
}
ctx.setFillColor(NSColor(srgbRed: 0xED / 255, green: 0xED / 255, blue: 0xED / 255, alpha: 1).cgColor)
ctx.fillEllipse(in: CGRect(x: center.x - 30, y: center.y - 30, width: 60, height: 60))

ctx.addPath(squircle)
ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.08).cgColor)
ctx.setLineWidth(3)
ctx.strokePath()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
