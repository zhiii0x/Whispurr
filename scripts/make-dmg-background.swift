#!/usr/bin/env swift
// Renders the Whispurr DMG install-window background: a refined, text-free design
// — a soft gradient, two gentle light "plinths" exactly under the app and the
// Applications alias, and a slim arrow between them. No text, no emoji.
// Output: a 2x PNG (1200×800) for a 600×400 install window.
// Usage: swift scripts/make-dmg-background.swift [out.png]
import AppKit

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "dist/dmg/.background/background.png"

let scale: CGFloat = 2
let w: CGFloat = 600, h: CGFloat = 400
let pxW = Int(w * scale), pxH = Int(h * scale)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
let topBG = rgb(0.961, 0.953, 0.976)   // #f5f3f9
let botBG = rgb(0.906, 0.914, 0.949)   // #e7e9f2
let arrow = rgb(0.40, 0.44, 0.58)      // muted slate

// Icon centres (shared with make-dmg.sh). Finder y is from the top; the window
// is square-ish so CG y == Finder y here (h/2).
let leftC  = NSPoint(x: 165, y: 200)
let rightC = NSPoint(x: 435, y: 200)

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: CGFloat(pxW), height: CGFloat(pxH))

let g = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = g
g.cgContext.scaleBy(x: scale, y: scale)    // draw in 600×400 points; only 2x

// gradient backdrop
NSGradient(colors: [topBG, botBG])?.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -90)

// faint centred glow for depth
if let glow = NSGradient(colors: [rgb(1, 1, 1, 0.5), rgb(1, 1, 1, 0)]) {
    glow.draw(fromCenter: NSPoint(x: w / 2, y: h / 2 + 20), radius: 0,
              toCenter: NSPoint(x: w / 2, y: h / 2 + 20), radius: 320, options: [])
}

// soft light plinth under an icon (layered translucent circles → blur-free soft edge)
func plinth(_ c: NSPoint) {
    var r: CGFloat = 82
    while r >= 56 {
        let a = 0.05 + (82 - r) / 26 * 0.30        // 0.05 → ~0.35
        rgb(1, 1, 1, a).setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)).fill()
        r -= 3.5
    }
    // whisper-thin contact ring
    rgb(0.40, 0.44, 0.58, 0.10).setStroke()
    let ring = NSBezierPath(ovalIn: NSRect(x: c.x - 62, y: c.y - 62, width: 124, height: 124))
    ring.lineWidth = 1
    ring.stroke()
}
plinth(leftC)
plinth(rightC)

// slim arrow between the plinths
let ay = leftC.y
let ax0: CGFloat = leftC.x + 86
let ax1: CGFloat = rightC.x - 92
arrow.withAlphaComponent(0.5).setStroke()
let shaft = NSBezierPath()
shaft.move(to: NSPoint(x: ax0, y: ay))
shaft.line(to: NSPoint(x: ax1, y: ay))
shaft.lineWidth = 2
shaft.lineCapStyle = .round
shaft.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: ax1 - 9, y: ay + 7))
head.line(to: NSPoint(x: ax1 + 1, y: ay))
head.line(to: NSPoint(x: ax1 - 9, y: ay - 7))
head.lineWidth = 2
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.stroke()

NSGraphicsContext.restoreGraphicsState()

let url = URL(fileURLWithPath: outPath)
try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to encode PNG\n".utf8)); exit(1)
}
try! png.write(to: url)
print("dmg background → \(outPath) (\(pxW)×\(pxH))")
