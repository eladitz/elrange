// Draws the app icon: a screen split into a main pane and two side panes, on a dark slate tile.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func pane(_ rect: NSRect, _ top: UInt32, _ bottom: UInt32, s: CGFloat) {
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.025, yRadius: s * 0.025)
    NSGradient(colors: [color(top), color(bottom)])!.draw(in: path, angle: -90)
    // Title bar with three dots.
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    color(0xFFFFFF, 0.18).setFill()
    NSRect(x: rect.minX, y: rect.maxY - s * 0.045, width: rect.width, height: s * 0.045).fill()
    NSGraphicsContext.restoreGraphicsState()
    for (i, dot) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
        color(UInt32(dot)).setFill()
        let d = s * 0.018
        NSBezierPath(ovalIn: NSRect(x: rect.minX + s * 0.02 + CGFloat(i) * d * 1.6, y: rect.maxY - s * 0.032, width: d, height: d)).fill()
    }
}

func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)

    let tile = NSBezierPath(roundedRect: NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8), xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(colors: [color(0x2B3550), color(0x141A2B)])!.draw(in: tile, angle: -90)

    let gap = s * 0.025
    let area = NSRect(x: s * 0.19, y: s * 0.22, width: s * 0.62, height: s * 0.56)
    let main = NSRect(x: area.minX, y: area.minY, width: area.width * 0.58 - gap / 2, height: area.height)
    let sideX = main.maxX + gap, sideW = area.maxX - sideX
    pane(main, 0x5B8CFF, 0x2F5BE0, s: s)
    pane(NSRect(x: sideX, y: area.midY + gap / 2, width: sideW, height: area.height / 2 - gap / 2), 0x9AA8C7, 0x6E7DA0, s: s)
    pane(NSRect(x: sideX, y: area.minY, width: sideW, height: area.height / 2 - gap / 2), 0x9AA8C7, 0x6E7DA0, s: s)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! draw(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! draw(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
