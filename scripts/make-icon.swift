// Renders Resources/AppIcon.icns (a dark rounded tile with a green waveform)
// and Resources/AppIcon-preview.png for the README.
// Run: swift scripts/make-icon.swift
import AppKit

let size: CGFloat = 1024
let canvas = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    // macOS icons leave a transparent margin around the tile.
    let tile = rect.insetBy(dx: size * 0.1, dy: size * 0.1)
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.2237, yRadius: tile.width * 0.2237)
    NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.19, alpha: 1),
               ending: NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.07, alpha: 1))!
        .draw(in: path, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .medium)
    guard let symbol = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { return false }
    let tinted = NSImage(size: symbol.size, flipped: false) { symbolRect in
        symbol.draw(in: symbolRect)
        NSColor(calibratedRed: 0.11, green: 0.84, blue: 0.38, alpha: 1).set()
        symbolRect.fill(using: .sourceAtop)
        return true
    }
    let origin = NSPoint(x: tile.midX - tinted.size.width / 2, y: tile.midY - tinted.size.height / 2)
    tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
    return true
}

let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        canvas.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}

let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
task.launch()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")

let preview = URL(fileURLWithPath: "Resources/AppIcon-preview.png")
try? FileManager.default.removeItem(at: preview)
try! FileManager.default.copyItem(at: iconset.appendingPathComponent("icon_512x512.png"), to: preview)
print("Wrote Resources/AppIcon-preview.png")
