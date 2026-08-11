#!/usr/bin/swift
// Generates Sources/mdview/Resources/AppIcon.icns: a flat white "M"
// markdown glyph with a small magnifying-glass accent (the "viewer" part
// of mdview), centered on a green-to-blue gradient square — styled after
// Apple's own app icons (Mail, Messages): one simple white glyph on a
// saturated gradient field, no border, no extra layers.
import AppKit

let rootDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // Scripts
    .deletingLastPathComponent() // package root

let iconsetDir = rootDir.appendingPathComponent("Scripts/.AppIcon.iconset")
let outputIcns = rootDir.appendingPathComponent("Sources/mdview/Resources/AppIcon.icns")

let sizes: [(name: String, size: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024)
]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    // macOS does not auto-round hand-built .icns files, so the squircle
    // shape has to be baked in — same rounded silhouette Mail/Messages use,
    // just without a stroked border around it.
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = rect.width * 0.2237 // Apple's continuous-corner ratio
    let bgPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    let colors = [
        NSColor(calibratedRed: 0.22, green: 0.80, blue: 0.55, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.12, green: 0.55, blue: 0.78, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.16, green: 0.38, blue: 0.90, alpha: 1).cgColor
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1])!

    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )
    ctx.restoreGState()

    // Centered white "M", the way Mail centers its envelope.
    let contentHeight = rect.height * 0.52
    let font = NSFont.systemFont(ofSize: contentHeight, weight: .heavy)
    let mString = NSAttributedString(string: "M", attributes: [.font: font, .foregroundColor: NSColor.white])
    let mSize = mString.size()
    let mOrigin = CGPoint(x: rect.midX - mSize.width / 2, y: rect.midY - mSize.height * 0.44)
    mString.draw(at: mOrigin)

    // Small magnifying-glass accent, bottom-right, same flat white as the
    // "M" — a single-tone glyph rather than a separate badge layer.
    let glassScale = rect.width * 0.15
    let lensRadius = glassScale * 0.62
    let lineWidth = max(glassScale * 0.30, 1)
    let lensCenter = CGPoint(x: rect.maxX - rect.width * 0.30, y: rect.minY + rect.height * 0.27)

    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(lineWidth)
    ctx.strokeEllipse(in: CGRect(
        x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius,
        width: lensRadius * 2, height: lensRadius * 2
    ))

    ctx.setLineCap(.round)
    let handleStart = CGPoint(
        x: lensCenter.x + lensRadius * 0.72,
        y: lensCenter.y - lensRadius * 0.72
    )
    let handleEnd = CGPoint(
        x: handleStart.x + glassScale * 0.55,
        y: handleStart.y - glassScale * 0.55
    )
    ctx.move(to: handleStart)
    ctx.addLine(to: handleEnd)
    ctx.strokePath()

    return image
}

try? FileManager.default.removeItem(at: iconsetDir)
try! FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

for entry in sizes {
    let image = drawIcon(size: CGFloat(entry.size))
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("Failed to render \(entry.name)\n".data(using: .utf8)!)
        exit(1)
    }
    let url = iconsetDir.appendingPathComponent("\(entry.name).png")
    try! png.write(to: url)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", outputIcns.path]
try! process.run()
process.waitUntilExit()

try? FileManager.default.removeItem(at: iconsetDir)

if process.terminationStatus == 0 {
    print("OK: wrote \(outputIcns.path)")
} else {
    print("iconutil failed with status \(process.terminationStatus)")
    exit(1)
}
