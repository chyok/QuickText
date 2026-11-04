// Draws the app icon and writes Resources/AppIcon.icns and docs/images/icon.png.
//
//   swift scripts/make-icon.swift
//
// The icon is drawn in code (no SF Symbols, which may not be used in app icons).
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

func drawIcon(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        let unit = size / 1024

        // Rounded-square background with a diagonal gradient, inset like macOS app icons.
        let tile = NSRect(x: 100, y: 100, width: 824, height: 824).scaled(unit)
        let background = NSBezierPath(roundedRect: tile, xRadius: 185 * unit, yRadius: 185 * unit)
        NSGradient(colors: [
            NSColor(srgbRed: 0.36, green: 0.40, blue: 0.98, alpha: 1),
            NSColor(srgbRed: 0.55, green: 0.32, blue: 0.93, alpha: 1),
        ])!.draw(in: background, angle: -60)

        // Speech bubble with a tail at the bottom left.
        let bubble = NSBezierPath(roundedRect: NSRect(x: 230, y: 330, width: 564, height: 420).scaled(unit),
                                  xRadius: 110 * unit, yRadius: 110 * unit)
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 330, y: 360).scaled(unit))
        tail.line(to: NSPoint(x: 280, y: 245).scaled(unit))
        tail.line(to: NSPoint(x: 440, y: 340).scaled(unit))
        tail.close()
        NSColor.white.setFill()
        bubble.fill()
        tail.fill()

        // Two lines of "text".
        NSColor(srgbRed: 0.36, green: 0.40, blue: 0.98, alpha: 0.35).setFill()
        for (y, width) in [(612.0, 330.0), (522.0, 230.0)] {
            NSBezierPath(roundedRect: NSRect(x: 320, y: y, width: width, height: 44).scaled(unit),
                         xRadius: 22 * unit, yRadius: 22 * unit).fill()
        }

        // A check mark: the text has been fixed.
        let check = NSBezierPath()
        check.move(to: NSPoint(x: 572, y: 452).scaled(unit))
        check.line(to: NSPoint(x: 626, y: 398).scaled(unit))
        check.line(to: NSPoint(x: 724, y: 512).scaled(unit))
        check.lineWidth = 48 * unit
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        NSColor(srgbRed: 0.20, green: 0.78, blue: 0.45, alpha: 1).setStroke()
        check.stroke()
        return true
    }
}

func pngData(_ image: NSImage, pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

extension NSRect {
    func scaled(_ factor: CGFloat) -> NSRect {
        NSRect(x: minX * factor, y: minY * factor, width: width * factor, height: height * factor)
    }
}

extension NSPoint {
    func scaled(_ factor: CGFloat) -> NSPoint {
        NSPoint(x: x * factor, y: y * factor)
    }
}

let fileManager = FileManager.default
let iconset = fileManager.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: iconset) }

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try pngData(drawIcon(size: CGFloat(pixels)), pixels: pixels).write(to: iconset.appendingPathComponent(name))
    }
}

let icns = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", "--output", icns.path, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }

let images = root.appendingPathComponent("docs/images")
try fileManager.createDirectory(at: images, withIntermediateDirectories: true)
try pngData(drawIcon(size: 256), pixels: 256).write(to: images.appendingPathComponent("icon.png"))
print("Wrote \(icns.path) and docs/images/icon.png")
