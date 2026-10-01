#!/usr/bin/env swift
// Renders App Store frames from Baseline's marketing screenshots: a 1320×2868 canvas (Apple's 6.9-inch
// class), BaselineTheme's navy gradient, a two-line caption at the top in SF Rounded (white 72pt headline,
// 44pt secondary) and the screenshot scaled to ~86% of the width with rounded corners, placed lower-centre.
//
//   swift Baseline/scripts/frame-shots.swift <in dir> <out dir>
//
// Every `NN-*.png` in <in dir> gets a frame `<out dir>/NN-*.png`; its caption comes from the table below,
// keyed on the two-digit prefix (a file with no entry still gets a frame, with no caption). CoreGraphics,
// CoreText and ImageIO only; AppKit is used solely to look up the system's rounded font (no third-party code).
//
// Sizes are in points at @2x: the canvas is 660×1434pt rendered to 1320×2868px, so 72pt is 144px, the
// 44pt corner radius is 88px. FRAME_SCALE=3 renders the same layout at 3x (for a 1980×4302 proof print).

import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Captions (edit here)

let captions: [String: (headline: String, secondary: String)] = [
    "01": ("Your morning,", "against your own baseline"),
    "02": ("Is your baseline moving?", "Months at a glance"),
    "03": ("Trends", "with your typical range"),
    "04": ("Sleep,", "stage by stage"),
    "05": ("Learn what moves", "your HRV"),
    "06": ("Effort and workouts,", "kept simple"),
]

// MARK: - Layout (points, @2x)

let canvasPoints = CGSize(width: 660, height: 1434)      // 1320×2868 px at 2x
let scale: CGFloat = {
    if let raw = ProcessInfo.processInfo.environment["FRAME_SCALE"], let v = Double(raw), v > 0 { return CGFloat(v) }
    return 2
}()
let headlineSize: CGFloat = 72
let secondarySize: CGFloat = 44
let captionTop: CGFloat = 96            // from the top edge to the headline's cap line
let captionGap: CGFloat = 14            // between headline and secondary line
let sideGutter: CGFloat = 36            // caption must fit inside the gutters (headline shrinks if not)
let shotWidthFraction: CGFloat = 0.86
let shotCornerRadius: CGFloat = 44
let shotTop: CGFloat = 300              // top edge of the screenshot; the bottom runs off the canvas
let shotShadowBlur: CGFloat = 40

// BaselineTheme.backgroundTop / .background (Baseline/Components/BaselineTheme.swift)
let navyTop = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0.070, 0.100, 0.190, 1])!
let navyBottom = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0.043, 0.063, 0.125, 1])!
let white = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1, 1, 1, 0.94])!
let whiteSecondary = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1, 1, 1, 0.62])!
let shadow = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0, 0, 0, 0.55])!
let hairline = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1, 1, 1, 0.10])!   // BaselineTheme.hairline

// MARK: - Arguments

let args = CommandLine.arguments
guard args.count == 3 else {
    fputs("usage: swift frame-shots.swift <in dir> <out dir>\n", stderr)
    exit(2)
}
let inDir = URL(fileURLWithPath: args[1], isDirectory: true)
let outDir = URL(fileURLWithPath: args[2], isDirectory: true)
let fm = FileManager.default

guard let entries = try? fm.contentsOfDirectory(at: inDir, includingPropertiesForKeys: nil) else {
    fputs("frame-shots: cannot read \(inDir.path)\n", stderr)
    exit(1)
}
let inputs = entries.filter { $0.pathExtension.lowercased() == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
guard !inputs.isEmpty else {
    fputs("frame-shots: no PNGs in \(inDir.path)\n", stderr)
    exit(1)
}
try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)

// MARK: - Fonts

/// SF Rounded at `size` and `weight`; the plain system font if the rounded design is unavailable.
func roundedFont(size: CGFloat, weight: NSFont.Weight) -> CTFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let rounded = base.fontDescriptor.withDesign(.rounded), let font = NSFont(descriptor: rounded, size: size) {
        return font as CTFont
    }
    return base as CTFont
}

/// A CTLine for `text`, shrunk below `size` only when it would overrun `maxWidth`.
func line(_ text: String, size: CGFloat, weight: NSFont.Weight, color: CGColor, maxWidth: CGFloat) -> (CTLine, CGFloat) {
    var pt = size
    while true {
        let font = roundedFont(size: pt, weight: weight)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .kern: -pt * 0.01,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        if width <= maxWidth || pt <= 20 { return (line, pt) }
        pt -= 2
    }
}

/// Draws `line` centred on `centerX` with its baseline at `baselineY` (CoreGraphics coordinates).
func draw(_ line: CTLine, in ctx: CGContext, centerX: CGFloat, baselineY: CGFloat) {
    let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    ctx.textPosition = CGPoint(x: centerX - width / 2, y: baselineY)
    CTLineDraw(line, ctx)
}

// MARK: - Loading

func loadPNG(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func writePNG(_ image: CGImage, to url: URL) -> Bool {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
}

// MARK: - Render

var failures = 0
for input in inputs {
    let name = input.lastPathComponent
    let key = String(name.prefix(2))
    let caption = captions[key]
    guard let shot = loadPNG(input) else {
        fputs("frame-shots: \(name): not a readable PNG, skipped\n", stderr)
        failures += 1
        continue
    }

    let pxWidth = Int(canvasPoints.width * scale), pxHeight = Int(canvasPoints.height * scale)
    guard let ctx = CGContext(data: nil, width: pxWidth, height: pxHeight, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        fputs("frame-shots: \(name): could not create the bitmap context\n", stderr)
        failures += 1
        continue
    }
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.setShouldSmoothFonts(true)
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: scale, y: scale)      // from here on: points, origin bottom-left
    let w = canvasPoints.width, h = canvasPoints.height

    // Background: BaselineBackground's top-to-bottom navy gradient.
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [navyTop, navyBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])

    // Caption.
    if let caption {
        let maxWidth = w - 2 * sideGutter
        let (head, headPt) = line(caption.headline, size: headlineSize, weight: .bold, color: white, maxWidth: maxWidth)
        let (sub, subPt) = line(caption.secondary, size: secondarySize, weight: .medium, color: whiteSecondary, maxWidth: maxWidth)
        // Cap height ≈ 0.70 of the point size for SF; the headline's cap line sits `captionTop` below the top edge.
        let headBaseline = h - captionTop - headPt * 0.70
        let subBaseline = headBaseline - captionGap - subPt * 1.0
        draw(head, in: ctx, centerX: w / 2, baselineY: headBaseline)
        draw(sub, in: ctx, centerX: w / 2, baselineY: subBaseline)
    }

    // Screenshot: 86% of the width, aspect kept, rounded corners, soft shadow, top edge at `shotTop`.
    let shotW = w * shotWidthFraction
    let shotH = shotW * CGFloat(shot.height) / CGFloat(shot.width)
    let shotRect = CGRect(x: (w - shotW) / 2, y: h - shotTop - shotH, width: shotW, height: shotH)
    let path = CGPath(roundedRect: shotRect, cornerWidth: shotCornerRadius, cornerHeight: shotCornerRadius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: shotShadowBlur, color: shadow)
    ctx.addPath(path)
    ctx.setFillColor(navyBottom)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.draw(shot, in: shotRect)
    ctx.restoreGState()

    // Hairline, like BaselineTheme.cardStroke, so the frame edge reads on the navy.
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setStrokeColor(hairline)
    ctx.setLineWidth(1)
    ctx.strokePath()
    ctx.restoreGState()

    guard let image = ctx.makeImage() else {
        fputs("frame-shots: \(name): could not rasterise\n", stderr)
        failures += 1
        continue
    }
    let out = outDir.appendingPathComponent(name)
    if writePNG(image, to: out) {
        let note = caption == nil ? " (no caption for prefix \"\(key)\")" : ""
        print("frame-shots: \(out.path) \(pxWidth)×\(pxHeight)\(note)")
    } else {
        fputs("frame-shots: \(name): could not write \(out.path)\n", stderr)
        failures += 1
    }
}
exit(failures == 0 ? 0 : 1)
