// Renders an SVG logo to a square PNG, trimmed to its visible pixels: svg2png <in.svg> <out.png> <size>
import AppKit

func bitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}

func draw(into rep: NSBitmapImageRep, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    body()
    NSGraphicsContext.restoreGraphicsState()
}

let args = CommandLine.arguments
guard args.count == 4, let size = Int(args[3]),
      let svg = NSImage(contentsOf: URL(fileURLWithPath: args[1])) else {
    FileHandle.standardError.write("usage: svg2png in.svg out.png size\n".data(using: .utf8)!)
    exit(1)
}

// Render large, then find the box around non-transparent pixels.
let big = 1024
let scale = Double(big) / max(svg.size.width, svg.size.height)
let full = bitmap(Int(svg.size.width * scale), Int(svg.size.height * scale))
draw(into: full) { svg.draw(in: NSRect(x: 0, y: 0, width: full.pixelsWide, height: full.pixelsHigh)) }
var minX = full.pixelsWide, minY = full.pixelsHigh, maxX = 0, maxY = 0
for y in 0..<full.pixelsHigh {
    for x in 0..<full.pixelsWide where (full.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.02 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    }
}
guard maxX > minX, maxY > minY else { exit(2) }

// colorAt uses a top-left origin; drawing uses bottom-left.
let crop = NSRect(x: minX, y: full.pixelsHigh - maxY - 1, width: maxX - minX + 1, height: maxY - minY + 1)
let out = bitmap(size, size)
let fit = Double(size) / max(crop.width, crop.height)
let w = crop.width * fit, h = crop.height * fit
draw(into: out) {
    full.draw(in: NSRect(x: (Double(size) - w) / 2, y: (Double(size) - h) / 2, width: w, height: h),
              from: crop, operation: .copy, fraction: 1, respectFlipped: false, hints: nil)
}
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
