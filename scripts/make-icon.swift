// Renders the Puck Pulse app icon: swift scripts/make-icon.swift watch/PuckPulse/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit
let size = 1024.0
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
// Background: deep ice-blue gradient.
NSGradient(colors: [NSColor(red: 0.05, green: 0.22, blue: 0.55, alpha: 1), NSColor(red: 0.01, green: 0.05, blue: 0.16, alpha: 1)])!
    .draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -70)
// Puck: side band and top face.
let cx = size / 2, top = 470.0, rx = 300.0, ry = 105.0, depth = 120.0
let band = NSBezierPath(ovalIn: NSRect(x: cx - rx, y: top - depth - ry, width: rx * 2, height: ry * 2))
band.append(NSBezierPath(rect: NSRect(x: cx - rx, y: top - depth, width: rx * 2, height: depth)))
NSColor(white: 0.06, alpha: 1).setFill(); band.fill()
let topFace = NSBezierPath(ovalIn: NSRect(x: cx - rx, y: top - ry, width: rx * 2, height: ry * 2))
NSGradient(colors: [NSColor(white: 0.28, alpha: 1), NSColor(white: 0.12, alpha: 1)])!.draw(in: topFace, angle: -90)
// Pulse line across the puck.
let pulse = NSBezierPath()
let pts: [(Double, Double)] = [(130, 600), (360, 600), (420, 690), (480, 420), (560, 820), (630, 560), (680, 600), (894, 600)]
pulse.move(to: NSPoint(x: pts[0].0, y: pts[0].1))
for p in pts.dropFirst() { pulse.line(to: NSPoint(x: p.0, y: p.1)) }
pulse.lineWidth = 52; pulse.lineCapStyle = .round; pulse.lineJoinStyle = .round
let shadow = NSShadow()
shadow.shadowColor = NSColor(red: 1, green: 0.2, blue: 0.25, alpha: 0.9)
shadow.shadowBlurRadius = 60
shadow.set()
NSColor(red: 1, green: 0.32, blue: 0.35, alpha: 1).setStroke(); pulse.stroke()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
