#!/usr/bin/env swift
//
// Renders the Lockin app icon — a flat blue rounded-square with a white clock — into a macOS
// .iconset directory. Deterministic and dependency-free (CoreGraphics only), so the icon can be
// regenerated from source. Invoke via scripts/make_icon.sh, which then runs `iconutil`.
//
// Usage: swift scripts/make_icon.swift <output.iconset dir>

import AppKit
import Foundation

// Brand blue matches Palette.idleColor (#0091FF).
let brandBlue = (r: 0.0 / 255.0, g: 145.0 / 255.0, b: 255.0 / 255.0)

func renderPNG(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let bytesPerRow = pixels * 4
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("Could not create bitmap context") }

    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)

    // Rounded-square background (macOS "squircle" proportions), leaving a small margin.
    let margin = size * 0.08
    let rect = CGRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
    let radius = rect.width * 0.2237
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(CGColor(red: brandBlue.r, green: brandBlue.g, blue: brandBlue.b, alpha: 1))
    ctx.fillPath()

    // White clock, centered.
    let center = CGPoint(x: size / 2, y: size / 2)
    let clockR = rect.width * 0.30
    let lineW = max(1, size * 0.05)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineCap(.round)
    ctx.setLineWidth(lineW)

    // Face.
    ctx.addEllipse(in: CGRect(x: center.x - clockR, y: center.y - clockR, width: 2 * clockR, height: 2 * clockR))
    ctx.strokePath()

    // Hour hand (straight up, short).
    ctx.move(to: center)
    ctx.addLine(to: CGPoint(x: center.x, y: center.y + clockR * 0.5))
    ctx.strokePath()

    // Minute hand (toward ~1–2 o'clock, longer).
    let angle = CGFloat.pi / 2 - CGFloat.pi / 3
    ctx.move(to: center)
    ctx.addLine(to: CGPoint(x: center.x + cos(angle) * clockR * 0.72, y: center.y + sin(angle) * clockR * 0.72))
    ctx.strokePath()

    // Center pin.
    let dotR = lineW * 0.9
    ctx.addEllipse(in: CGRect(x: center.x - dotR, y: center.y - dotR, width: 2 * dotR, height: 2 * dotR))
    ctx.fillPath()

    guard let cgImage = ctx.makeImage() else { fatalError("Could not render image") }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encode failed") }
    return data
}

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("Usage: make_icon.swift <output.iconset dir>\n".data(using: .utf8)!)
    exit(1)
}

let outDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// (filename, pixel size) per Apple's .iconset convention.
let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, px) in variants {
    let data = renderPNG(pixels: px)
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    try data.write(to: url)
    print("  wrote \(name) (\(px)px)")
}
