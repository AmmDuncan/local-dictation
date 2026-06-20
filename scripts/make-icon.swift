#!/usr/bin/env swift
// Renders the "Signal" app icon (white waveform on an emerald→teal squircle)
// into a macOS .iconset directory. Usage: swift make-icon.swift <output.iconset>
import AppKit

func drawIcon(pixels: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(pixels), pixelsHigh: Int(pixels),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)

    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    let pad = pixels * 0.10
    let inner = pixels - pad * 2
    let rect = CGRect(x: pad, y: pad, width: inner, height: inner)
    let radius = inner * 0.2237
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // subtle drop shadow within the transparent margin
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -pixels * 0.012), blur: pixels * 0.03,
                 color: NSColor(white: 0, alpha: 0.26).cgColor)
    cg.addPath(squircle)
    cg.setFillColor(NSColor.black.cgColor)
    cg.fillPath()
    cg.restoreGState()

    // emerald→teal gradient, clipped to the squircle
    cg.saveGState()
    cg.addPath(squircle)
    cg.clip()
    let colors = [
        NSColor(srgbRed: 0.184, green: 0.839, blue: 0.639, alpha: 1).cgColor, // #2fd6a3
        NSColor(srgbRed: 0.055, green: 0.616, blue: 0.471, alpha: 1).cgColor, // #0e9d78
        NSColor(srgbRed: 0.039, green: 0.490, blue: 0.388, alpha: 1).cgColor  // #0a7d63
    ]
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: colors as CFArray, locations: [0, 0.55, 1])!
    cg.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.maxY),
                          end: CGPoint(x: rect.maxX, y: rect.minY), options: [])

    // soft top highlight for depth
    cg.setBlendMode(.softLight)
    let highlight = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [NSColor(white: 1, alpha: 0.55).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray,
        locations: [0, 0.45])!
    cg.drawLinearGradient(highlight, start: CGPoint(x: rect.midX, y: rect.maxY),
                          end: CGPoint(x: rect.midX, y: rect.midY), options: [])
    cg.setBlendMode(.normal)
    cg.restoreGState()

    // white waveform bars
    let heights: [CGFloat] = [0.40, 0.68, 1.0, 0.80, 0.50]
    let barW = inner * 0.075
    let gap = inner * 0.063
    let totalW = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
    let startX = rect.midX - totalW / 2
    let maxH = inner * 0.46
    cg.setFillColor(NSColor.white.cgColor)
    for (i, ratio) in heights.enumerated() {
        let h = maxH * ratio
        let x = startX + CGFloat(i) * (barW + gap)
        let bar = CGRect(x: x, y: rect.midY - h / 2, width: barW, height: h)
        cg.addPath(CGPath(roundedRect: bar, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil))
        cg.fillPath()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ pixels: CGFloat, _ path: String) {
    let rep = drawIcon(pixels: pixels)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write("usage: make-icon.swift <output.iconset>\n".data(using: .utf8)!)
    exit(1)
}
let outDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// (filename, pixel size) per Apple's iconset spec
let entries: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, size) in entries {
    writePNG(size, "\(outDir)/\(name)")
}
print("Wrote \(entries.count) PNGs to \(outDir)")
