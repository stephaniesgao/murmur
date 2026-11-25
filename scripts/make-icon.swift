// Draws Murmur's app icon (the blob mascot on a soft lavender tile) and writes Resources/AppIcon.icns.
// Run from the project folder: swift scripts/make-icon.swift
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func drawIcon(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    let cg = context.cgContext
    let s = CGFloat(size) / 1024
    cg.scaleBy(x: s, y: s)

    // macOS-style tile: 824×824 rounded square centred in 1024, with a soft drop shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x2D2545, 0.28))
    cg.addPath(tilePath); cg.setFillColor(color(0xF4EDFF)); cg.fillPath()
    cg.restoreGState()
    cg.saveGState(); cg.addPath(tilePath); cg.clip()
    let background = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0xFFF6EC), color(0xEFE4FF)] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Little sound ripples behind the mascot.
    cg.setLineCap(.round)
    for (index, radius) in [300.0, 360.0].enumerated() {
        cg.setStrokeColor(color(0xB9A4FF, 0.35 - CGFloat(index) * 0.13)); cg.setLineWidth(18)
        cg.addArc(center: CGPoint(x: 512, y: 470), radius: radius, startAngle: .pi * 0.15, endAngle: -.pi * 0.15, clockwise: true); cg.strokePath()
        cg.addArc(center: CGPoint(x: 512, y: 470), radius: radius, startAngle: .pi * 0.85, endAngle: .pi * 1.15, clockwise: false); cg.strokePath()
    }
    cg.restoreGState()

    // The blob: a gently wobbly circle with a peach → lilac gradient.
    let center = CGPoint(x: 512, y: 470), radius: CGFloat = 245
    let blob = CGMutablePath()
    for step in 0...180 {
        let angle = Double(step) / 180 * 2 * .pi
        let wobble = 1 + 0.035 * sin(3 * angle + 0.6) + 0.025 * sin(5 * angle - 0.4)
        let point = CGPoint(x: center.x + CGFloat(cos(angle) * wobble) * radius, y: center.y + CGFloat(sin(angle) * wobble) * radius)
        if step == 0 { blob.move(to: point) } else { blob.addLine(to: point) }
    }
    blob.closeSubpath()
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x8B6CF6, 0.30))
    cg.addPath(blob); cg.setFillColor(color(0xFFC2A1)); cg.fillPath()
    cg.restoreGState()
    cg.saveGState(); cg.addPath(blob); cg.clip()
    let body = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0xFFC2A1), color(0xC4B2FF)] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(body, start: CGPoint(x: 300, y: 700), end: CGPoint(x: 720, y: 240), options: [])
    // Soft highlight.
    cg.setFillColor(color(0xFFFFFF, 0.28)); cg.fillEllipse(in: CGRect(x: 360, y: 560, width: 170, height: 90))
    cg.restoreGState()
    cg.addPath(blob); cg.setStrokeColor(color(0xFFFFFF, 0.45)); cg.setLineWidth(6); cg.strokePath()

    // Face: eyes, rosy cheeks and a small smile.
    let ink = color(0x2D2545)
    cg.setFillColor(ink)
    for x in [440.0, 584.0] { cg.addPath(CGPath(roundedRect: CGRect(x: x - 19, y: 470, width: 38, height: 66), cornerWidth: 19, cornerHeight: 19, transform: nil)); cg.fillPath() }
    cg.setFillColor(color(0xFF7390, 0.32))
    for x in [385.0, 639.0] { cg.fillEllipse(in: CGRect(x: x - 38, y: 418, width: 76, height: 44)) }
    cg.setStrokeColor(ink); cg.setLineWidth(17); cg.setLineCap(.round)
    cg.move(to: CGPoint(x: 476, y: 425)); cg.addQuadCurve(to: CGPoint(x: 548, y: 425), control: CGPoint(x: 512, y: 385)); cg.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try drawIcon(size: base * scale).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
try drawIcon(size: 1024).representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("build/AppIcon-preview.png"))
let resources = root.appendingPathComponent("Resources")
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try task.run(); task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
