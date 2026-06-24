#!/usr/bin/env swift
// Renders README marketing assets from the real cat frames: a logo, a cat-states
// strip, and a HUD mock (matching the in-app FloatingHUD styling).
// Output: assets/logo.png, assets/states.png, assets/hud.png
import AppKit

let frames = "Sources/WhispurrApp/Resources/CatFrames"
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
let lavTop = rgb(0.961, 0.953, 0.976)   // #f5f3f9
let lavBot = rgb(0.906, 0.914, 0.949)   // #e7e9f2
let plumTop = rgb(0.357, 0.290, 0.420)  // #5b4a6b  (HUD)
let plumBot = rgb(0.278, 0.227, 0.341)  // #473a57
let accent = rgb(0.231, 0.510, 0.965)   // #3b82f6
let ink = rgb(0.278, 0.227, 0.341)

func img(_ name: String) -> NSImage? { NSImage(contentsOfFile: "\(frames)/\(name).png") }

func render(_ w: CGFloat, _ h: CGFloat, scale: CGFloat = 2, to path: String, draw: () -> Void) {
    let pxW = Int(w * scale), pxH = Int(h * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: CGFloat(pxW), height: CGFloat(pxH))
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = g
    g.cgContext.scaleBy(x: scale, y: scale)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try? FileManager.default.createDirectory(atPath: "assets", withIntermediateDirectories: true)
    if let d = rep.representation(using: .png, properties: [:]) {
        try? d.write(to: URL(fileURLWithPath: path)); print("→ \(path) (\(pxW)×\(pxH))")
    }
}

func text(_ s: String, font: NSFont, color: NSColor, centerX: CGFloat, y: CGFloat) {
    let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
    let sz = str.size()
    str.draw(at: NSPoint(x: centerX - sz.width / 2, y: y))
}
func drawCat(_ image: NSImage, centerX: CGFloat, centerY: CGFloat, height: CGFloat) {
    NSGraphicsContext.current?.imageInterpolation = .none   // crisp pixel art
    let w = height * image.size.width / image.size.height
    image.draw(in: NSRect(x: centerX - w / 2, y: centerY - height / 2, width: w, height: height),
               from: .zero, operation: .sourceOver, fraction: 1)
}

// ---------- LOGO ----------
render(512, 512, to: "assets/logo.png") {
    let rect = NSRect(x: 46, y: 46, width: 420, height: 420)
    let card = NSBezierPath(roundedRect: rect, xRadius: 96, yRadius: 96)
    // soft drop shadow on a solid fill
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.20)
    sh.shadowBlurRadius = 26; sh.shadowOffset = NSSize(width: 0, height: -8); sh.set()
    lavTop.setFill(); card.fill()
    NSGraphicsContext.restoreGraphicsState()
    // gradient face inside the rounded clip
    NSGraphicsContext.saveGraphicsState()
    card.addClip()
    NSGradient(colors: [lavTop, lavBot])?.draw(in: rect, angle: -60)
    NSGraphicsContext.restoreGraphicsState()
    rgb(1, 1, 1, 0.6).setStroke(); card.lineWidth = 1.5; card.stroke()
    if let cat = img("idle") { drawCat(cat, centerX: 256, centerY: 250, height: 300) }
}

// ---------- CAT STATES ----------
render(780, 300, to: "assets/states.png") {
    NSGradient(colors: [lavTop, lavBot])?.draw(in: NSRect(x: 0, y: 0, width: 780, height: 300), angle: -90)
    let cols: [(String, String, CGFloat)] = [
        ("idle", "Idle", 130), ("listening", "Listening", 390), ("processing", "Cleaning up", 650),
    ]
    for (frame, label, cx) in cols {
        if let cat = img(frame) { drawCat(cat, centerX: cx, centerY: 175, height: 168) }
        text(label, font: .systemFont(ofSize: 19, weight: .semibold), color: ink, centerX: cx, y: 52)
    }
    text("hold fn → speak → release", font: .systemFont(ofSize: 14, weight: .medium),
         color: ink.withAlphaComponent(0.55), centerX: 390, y: 20)
}

// ---------- HUD MOCK ----------
render(384, 96, to: "assets/hud.png") {
    let rect = NSRect(x: 12, y: 12, width: 360, height: 72)
    let card = NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18)
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.32)
    sh.shadowBlurRadius = 16; sh.shadowOffset = NSSize(width: 0, height: -5); sh.set()
    plumTop.setFill(); card.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState(); card.addClip()
    NSGradient(colors: [plumTop, plumBot])?.draw(in: rect, angle: -45)
    NSGraphicsContext.restoreGraphicsState()
    rgb(1, 1, 1, 0.15).setStroke(); card.lineWidth = 1; card.stroke()
    // cat head (use the listening head-crop)
    if let cat = img("menubar-listening") { drawCat(cat, centerX: 44, centerY: 48, height: 34) }
    // equalizer bars
    let heights: [CGFloat] = [10, 22, 15, 26, 13]
    for (i, hgt) in heights.enumerated() {
        let x = 72 + CGFloat(i) * 7
        let bar = NSBezierPath(roundedRect: NSRect(x: x, y: 48 - hgt / 2, width: 4, height: hgt),
                               xRadius: 2, yRadius: 2)
        accent.setFill(); bar.fill()
    }
    // live partial text (shows zh+en code-switching)
    let s = NSAttributedString(string: "幫我 push 這個 commit",
        attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white])
    s.draw(at: NSPoint(x: 118, y: 41))
}

print("done")
