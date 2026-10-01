#!/usr/bin/env swift
// Renders Baseline's app icon: a 1024x1024 opaque PNG with a deep navy background, a soft
// translucent teal band (the "baseline" range) and one smooth teal line that reads as a calm HRV
// trend rising slightly from left to right. No text, generous margins, no alpha channel.
//
//   swift Baseline/scripts/render-icon.swift [output.png]
//
// Without an argument it overwrites Baseline/Resources/Assets.xcassets/BaselineIcon.appiconset/
// icon-1024.png next to this script. CoreGraphics and ImageIO only; no third-party code.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let s = CGFloat(size)

// MARK: - Palette

func rgb(_ hex: UInt32) -> (CGFloat, CGFloat, CGFloat) {
    (CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255)
}
func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    let (r, g, b) = rgb(hex)
    return CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, alpha])!
}

let navyTop: UInt32 = 0x0B1020     // the brief's deep navy
let navyBottom: UInt32 = 0x101A36  // a touch lighter at the bottom: subtle vertical gradient
let teal: UInt32 = 0x40E0D0

// MARK: - Output path

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let defaultOutput = scriptURL
    .deletingLastPathComponent()                // scripts/
    .deletingLastPathComponent()                // Baseline/
    .appendingPathComponent("Resources/Assets.xcassets/BaselineIcon.appiconset/icon-1024.png")
let output = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : defaultOutput

// MARK: - Canvas (RGB, no alpha)

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: colorSpace,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fputs("render-icon: could not create the bitmap context\n", stderr)
    exit(1)
}
ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)
ctx.interpolationQuality = .high

// Background: vertical gradient, top navy to a slightly lighter navy at the bottom.
// CoreGraphics' origin is bottom-left, so "top" is y = s.
let gradient = CGGradient(colorsSpace: colorSpace,
                          colors: [color(navyTop), color(navyBottom)] as CFArray,
                          locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

// MARK: - Geometry

/// Points in unit space with y measured from the TOP (design coordinates), converted to the
/// canvas's bottom-left origin.
func p(_ x: CGFloat, _ yFromTop: CGFloat) -> CGPoint { CGPoint(x: x * s, y: (1 - yFromTop) * s) }

/// The baseline range: a gentle rise from left to right, drawn as a wide stroke with round caps.
let bandStart = p(0.15, 0.615)
let bandEnd = p(0.85, 0.455)

/// The HRV trend: calm waves around the band's centre, ending a little above where it started.
let trend: [CGPoint] = [
    p(0.165, 0.605),
    p(0.275, 0.622),
    p(0.385, 0.568),
    p(0.495, 0.578),
    p(0.605, 0.516),
    p(0.715, 0.522),
    p(0.835, 0.458),
]

/// Catmull-Rom spline through `points`, emitted as cubic Béziers so the line is smooth everywhere.
func smoothPath(through points: [CGPoint]) -> CGMutablePath {
    let path = CGMutablePath()
    guard points.count > 1 else { return path }
    path.move(to: points[0])
    for i in 0..<(points.count - 1) {
        let p0 = i == 0 ? points[0] : points[i - 1]
        let p1 = points[i]
        let p2 = points[i + 1]
        let p3 = i + 2 < points.count ? points[i + 2] : points[i + 1]
        let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
        let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
        path.addCurve(to: p2, control1: c1, control2: c2)
    }
    return path
}

func stroke(_ path: CGPath, width: CGFloat, color: CGColor) {
    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(width)
    ctx.setStrokeColor(color)
    ctx.addPath(path)
    ctx.strokePath()
    ctx.restoreGState()
}

// MARK: - Band

let bandPath = CGMutablePath()
bandPath.move(to: bandStart)
bandPath.addLine(to: bandEnd)
// Three concentric passes with falling alpha: soft edges, no hard rectangle.
stroke(bandPath, width: 0.230 * s, color: color(teal, alpha: 0.050))
stroke(bandPath, width: 0.190 * s, color: color(teal, alpha: 0.060))
stroke(bandPath, width: 0.150 * s, color: color(teal, alpha: 0.075))

// MARK: - Trend line

let trendPath = smoothPath(through: trend)
// A glow that brightens toward the line (no dark ring), then the line itself.
stroke(trendPath, width: 0.072 * s, color: color(teal, alpha: 0.08))
stroke(trendPath, width: 0.054 * s, color: color(teal, alpha: 0.18))
stroke(trendPath, width: 0.042 * s, color: color(teal, alpha: 0.45))
stroke(trendPath, width: 0.034 * s, color: color(teal))

// MARK: - Write

guard let image = ctx.makeImage() else {
    fputs("render-icon: could not rasterise the icon\n", stderr)
    exit(1)
}
guard let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fputs("render-icon: could not open \(output.path) for writing\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    fputs("render-icon: could not write \(output.path)\n", stderr)
    exit(1)
}
print("render-icon: wrote \(output.path) (\(image.width)x\(image.height), alpha: \(image.alphaInfo == .none || image.alphaInfo == .noneSkipLast || image.alphaInfo == .noneSkipFirst ? "none" : "yes"))")
