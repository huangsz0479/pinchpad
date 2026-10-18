import AppKit
import CoreGraphics

// Usage: swift generate-icon.swift <output.iconset> <menubar-out-dir>
// Renders the Pinchpad app icon and the menu bar template glyph.
//
// App icon: a deep-blue squircle plate holding a 3x3 grid of frosted tiles.
// Tile sizes shrink toward the corners so the grid reads as being "pinched"
// toward the center; the center tile is a warm accent (the one you launch).
//
// Menu bar: the same pinched 3x3 grid as a black template image (alpha only),
// so macOS tints it for light/dark menu bars automatically.

let args = CommandLine.arguments
guard args.count >= 3 else { fatalError("usage: swift generate-icon.swift <out.iconset> <menubar-dir>") }
let outDir = args[1]
let menuDir = args[2]
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
try FileManager.default.createDirectory(atPath: menuDir, withIntermediateDirectories: true)

let space = CGColorSpaceCreateDeviceRGB()

// Continuous-corner "squircle" approximated with a superellipse |x|^n + |y|^n = 1.
func squircle(_ rect: CGRect, _ n: CGFloat = 4.5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let p = 2.0 / n
    let steps = 420
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * pow(abs(c), p) * (c >= 0 ? 1 : -1)
        let y = cy + b * pow(abs(s), p) * (s >= 0 ? 1 : -1)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
        else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func bitmap(_ px: Int) -> (NSBitmapImageRep, CGContext) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    return (rep, ctx)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

// Scale for tile at grid position (r, c): 1.0 at the center, smaller toward corners.
func pinchScale(_ r: Int, _ c: Int, edge: CGFloat, corner: CGFloat) -> CGFloat {
    let d = abs(r - 1) + abs(c - 1)
    switch d {
    case 0: return 1.0
    case 1: return edge
    default: return corner
    }
}

// Tile rects for a 3x3 pinched grid centered at `center`, with pitch `pitch`
// (distance between tile centers) and full tile side `side`.
func tileRects(center: CGPoint, pitch: CGFloat, side: CGFloat,
               edge: CGFloat, corner: CGFloat) -> [(rect: CGRect, isCenter: Bool)] {
    var out: [(CGRect, Bool)] = []
    for r in 0..<3 {
        for c in 0..<3 {
            let k = side * pinchScale(r, c, edge: edge, corner: corner)
            let cx = center.x + CGFloat(c - 1) * pitch
            let cy = center.y + CGFloat(r - 1) * pitch
            out.append((CGRect(x: cx - k / 2, y: cy - k / 2, width: k, height: k), r == 1 && c == 1))
        }
    }
    return out
}

func renderAppIcon(_ px: Int) -> NSBitmapImageRep {
    let s = CGFloat(px)
    let (rep, ctx) = bitmap(px)

    let inset = s * 0.098 // ~100pt margin on a 1024 canvas, per macOS icon grid
    let plate = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let platePath = squircle(plate)

    // Soft drop shadow under the plate.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.018,
                  color: CGColor(red: 0.05, green: 0.10, blue: 0.30, alpha: 0.45))
    ctx.addPath(platePath)
    ctx.setFillColor(CGColor(red: 0.12, green: 0.20, blue: 0.55, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Plate body: deep blue, brighter toward the top.
    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()
    ctx.drawLinearGradient(gradient([
        CGColor(red: 0.42, green: 0.62, blue: 1.00, alpha: 1),
        CGColor(red: 0.20, green: 0.36, blue: 0.92, alpha: 1),
        CGColor(red: 0.10, green: 0.16, blue: 0.52, alpha: 1),
    ], [0, 0.55, 1]),
    start: CGPoint(x: plate.midX, y: plate.maxY),
    end: CGPoint(x: plate.midX, y: plate.minY), options: [])

    // Radial glow behind the grid so the tiles sit in a pool of light.
    ctx.drawRadialGradient(gradient([
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
    ], [0, 1]),
    startCenter: CGPoint(x: plate.midX, y: plate.midY + plate.height * 0.08), startRadius: 0,
    endCenter: CGPoint(x: plate.midX, y: plate.midY + plate.height * 0.08), endRadius: plate.width * 0.55,
    options: [])

    // Top sheen.
    ctx.drawLinearGradient(gradient([
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.20),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
    ], [0, 1]),
    start: CGPoint(x: plate.midX, y: plate.maxY),
    end: CGPoint(x: plate.midX, y: plate.maxY - plate.height * 0.45), options: [])

    // Inner rim light.
    ctx.addPath(platePath)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.22))
    ctx.setLineWidth(max(s * 0.006, 0.75))
    ctx.strokePath()
    ctx.restoreGState()

    // Pinched 3x3 grid.
    let pitch = plate.width * 0.265
    let side = plate.width * 0.215
    let tiles = tileRects(center: CGPoint(x: plate.midX, y: plate.midY),
                          pitch: pitch, side: side, edge: 0.86, corner: 0.74)

    let frostSheen = gradient([
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.35),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
    ], [0, 1])
    let accent = gradient([
        CGColor(red: 1.00, green: 0.78, blue: 0.36, alpha: 1),
        CGColor(red: 1.00, green: 0.55, blue: 0.26, alpha: 1),
        CGColor(red: 0.98, green: 0.40, blue: 0.30, alpha: 1),
    ], [0, 0.55, 1])

    // Draw corners/edges first, center last so its glow sits on top.
    for t in tiles.sorted(by: { !$0.isCenter && $1.isCenter }) {
        let path = squircle(t.rect, 4.2)
        if t.isCenter {
            // Warm glow around the accent tile.
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: s * 0.035,
                          color: CGColor(red: 1.0, green: 0.55, blue: 0.25, alpha: 0.55))
            ctx.addPath(path)
            ctx.setFillColor(CGColor(red: 1.0, green: 0.6, blue: 0.3, alpha: 1))
            ctx.fillPath()
            ctx.restoreGState()

            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.drawLinearGradient(accent,
                                   start: CGPoint(x: t.rect.midX, y: t.rect.maxY),
                                   end: CGPoint(x: t.rect.midX, y: t.rect.minY), options: [])
            ctx.drawLinearGradient(frostSheen,
                                   start: CGPoint(x: t.rect.midX, y: t.rect.maxY),
                                   end: CGPoint(x: t.rect.midX, y: t.rect.maxY - t.rect.height * 0.5), options: [])
            ctx.addPath(path)
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.35))
            ctx.setLineWidth(max(s * 0.004, 0.5))
            ctx.strokePath()
            ctx.restoreGState()
        } else {
            // Frosted glass tile with a soft shadow.
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.006), blur: s * 0.012,
                          color: CGColor(red: 0.05, green: 0.10, blue: 0.35, alpha: 0.35))
            ctx.addPath(path)
            ctx.setFillColor(CGColor(red: 0.93, green: 0.96, blue: 1.0, alpha: 0.92))
            ctx.fillPath()
            ctx.restoreGState()

            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.drawLinearGradient(frostSheen,
                                   start: CGPoint(x: t.rect.midX, y: t.rect.maxY),
                                   end: CGPoint(x: t.rect.midX, y: t.rect.maxY - t.rect.height * 0.6), options: [])
            ctx.addPath(path)
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.5))
            ctx.setLineWidth(max(s * 0.003, 0.5))
            ctx.strokePath()
            ctx.restoreGState()
        }
    }
    return rep
}

// Menu bar template: 18pt canvas. Black fill + alpha only.
func renderMenuBarIcon(scale: Int) -> NSBitmapImageRep {
    let pt: CGFloat = 18
    let px = Int(pt) * scale
    let (rep, ctx) = bitmap(px)
    let k = CGFloat(scale)
    // Grid occupies 16pt: pitch 5.5pt, full tile 4.6pt; corner tiles 3.5pt.
    let tiles = tileRects(center: CGPoint(x: pt / 2 * k, y: pt / 2 * k),
                          pitch: 5.5 * k, side: 4.8 * k, edge: 0.86, corner: 0.74)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    let mid = pt / 2 * k
    for t in tiles {
        // Snap to the pixel grid at 1x so edges stay crisp, mirroring about the
        // center so left/right and top/bottom tiles stay symmetric.
        var r = t.rect
        if scale == 1 {
            func snap(_ lo: CGFloat, _ hi: CGFloat) -> (CGFloat, CGFloat) {
                if hi <= mid { return (lo.rounded(.down), hi.rounded(.down)) }
                if lo >= mid { return (lo.rounded(.up), hi.rounded(.up)) }
                let half = ((hi - lo) / 2).rounded()
                return (mid - half, mid + half)
            }
            let (x0, x1) = snap(r.minX, r.maxX)
            let (y0, y1) = snap(r.minY, r.maxY)
            r = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }
        let radius = r.width * 0.28
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
    }
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to path: String) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("failed to encode \(path)")
    }
    try data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

let specs: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for spec in specs {
    try writePNG(renderAppIcon(spec.px), to: "\(outDir)/\(spec.name).png")
}
try writePNG(renderMenuBarIcon(scale: 1), to: "\(menuDir)/MenuBarIcon.png")
try writePNG(renderMenuBarIcon(scale: 2), to: "\(menuDir)/MenuBarIcon@2x.png")
