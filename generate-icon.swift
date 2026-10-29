import AppKit

// Usage: swift generate-icon.swift <output.iconset> <menubar-output-directory>
// Renders the native matte app icon and its matching 18pt template glyph.
// The ICNS file is written beside the iconset, using the same base name.
let args = CommandLine.arguments
guard args.count == 3 else {
    fatalError("usage: swift generate-icon.swift <output.iconset> <menubar-output-directory>")
}
let iconset = URL(fileURLWithPath: args[1], isDirectory: true)
let menuDirectory = URL(fileURLWithPath: args[2], isDirectory: true)
let icnsURL = iconset.deletingPathExtension().appendingPathExtension("icns")
let files = FileManager.default
try files.createDirectory(at: iconset, withIntermediateDirectories: true)
try files.createDirectory(at: menuDirectory, withIntermediateDirectories: true)

func bitmap(width: Int, height: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                     isPlanar: false, colorSpaceName: .deviceRGB,
                     bytesPerRow: 0, bitsPerPixel: 0)!
}

func save(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encoding failed: \(url.path)")
    }
    try data.write(to: url)
}

func tile() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 4, y: 1))
    p.addLine(to: CGPoint(x: 6.5, y: 1))
    p.addQuadCurve(to: CGPoint(x: 8, y: 2.5), control: CGPoint(x: 8, y: 1))
    p.addLine(to: CGPoint(x: 8, y: 4.6))
    p.addQuadCurve(to: CGPoint(x: 7.35, y: 6.15), control: CGPoint(x: 8, y: 5.5))
    p.addLine(to: CGPoint(x: 6.15, y: 7.35))
    p.addQuadCurve(to: CGPoint(x: 4.6, y: 8), control: CGPoint(x: 5.5, y: 8))
    p.addLine(to: CGPoint(x: 2.5, y: 8))
    p.addQuadCurve(to: CGPoint(x: 1, y: 6.5), control: CGPoint(x: 1, y: 8))
    p.addLine(to: CGPoint(x: 1, y: 4))
    p.addQuadCurve(to: CGPoint(x: 4, y: 1), control: CGPoint(x: 1, y: 1))
    p.closeSubpath()
    return p
}

func drawMark(_ ctx: CGContext, color: CGColor) {
    ctx.setFillColor(color)
    for quarter in 0..<4 {
        ctx.saveGState()
        ctx.translateBy(x: 9, y: 9)
        ctx.rotate(by: CGFloat(quarter) * .pi / 2)
        ctx.translateBy(x: -9, y: -9)
        ctx.addPath(tile())
        ctx.fillPath()
        ctx.restoreGState()
    }
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 8.55, y: 7.45))
    p.addQuadCurve(to: CGPoint(x: 9.45, y: 7.45), control: CGPoint(x: 9, y: 7))
    p.addLine(to: CGPoint(x: 10.55, y: 8.55))
    p.addQuadCurve(to: CGPoint(x: 10.55, y: 9.45), control: CGPoint(x: 11, y: 9))
    p.addLine(to: CGPoint(x: 9.45, y: 10.55))
    p.addQuadCurve(to: CGPoint(x: 8.55, y: 10.55), control: CGPoint(x: 9, y: 11))
    p.addLine(to: CGPoint(x: 7.45, y: 9.45))
    p.addQuadCurve(to: CGPoint(x: 7.45, y: 8.55), control: CGPoint(x: 7, y: 9))
    p.closeSubpath()
    ctx.addPath(p)
    ctx.fillPath()
}

func menuIcon(scale: Int) -> NSBitmapImageRep {
    let rep = bitmap(width: 18 * scale, height: 18 * scale)
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    drawMark(ctx, color: CGColor(gray: 0, alpha: 1))
    // Set logical size after drawing so AppKit does not scale the context twice.
    rep.size = NSSize(width: 18, height: 18)
    return rep
}

func squircle(_ rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    for step in 0...480 {
        let angle = CGFloat(step) / 480 * 2 * .pi
        let c = cos(angle), s = sin(angle)
        let point = CGPoint(
            x: rect.midX + rect.width / 2 * pow(abs(c), 2 / 4.5) * (c >= 0 ? 1 : -1),
            y: rect.midY + rect.height / 2 * pow(abs(s), 2 / 4.5) * (s >= 0 ? 1 : -1))
        if step == 0 { path.move(to: point) }
        else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

func appIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = bitmap(width: pixels, height: pixels)
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = squircle(plate)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 13,
                  color: CGColor(red: 0.19, green: 0.25, blue: 0.35, alpha: 0.18))
    ctx.setFillColor(CGColor(red: 0.93, green: 0.95, blue: 0.98, alpha: 1))
    ctx.addPath(path)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let colors = [CGColor(red: 0.975, green: 0.982, blue: 0.995, alpha: 1),
                  CGColor(red: 0.912, green: 0.941, blue: 0.980, alpha: 1)]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: colors as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 512, y: plate.maxY),
                           end: CGPoint(x: 512, y: plate.minY), options: [])
    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.8))
    ctx.setLineWidth(2)
    ctx.strokePath()
    ctx.restoreGState()

    // The exact menu bar silhouette, enlarged without changing its geometry.
    // Its visible 16-unit width occupies 63% of the plate.
    let scale = plate.width * 0.63 / 16
    ctx.saveGState()
    ctx.translateBy(x: 512 - 9 * scale, y: 512 - 9 * scale)
    ctx.scaleBy(x: scale, y: scale)
    drawMark(ctx, color: CGColor(red: 0.247, green: 0.439, blue: 0.710, alpha: 1))
    ctx.restoreGState()
    return rep
}
let specs = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
             ("128x128", 128), ("128x128@2x", 256), ("256x256", 256),
             ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
for (name, pixels) in specs {
    try save(appIcon(pixels: pixels), to: iconset.appendingPathComponent("icon_\(name).png"))
}
try save(appIcon(pixels: 1024), to: menuDirectory.appendingPathComponent("AppIcon-master.png"))
try save(menuIcon(scale: 1), to: menuDirectory.appendingPathComponent("MenuBarIcon.png"))
try save(menuIcon(scale: 2), to: menuDirectory.appendingPathComponent("MenuBarIcon@2x.png"))

// Package the PNG representations directly in the macOS ICNS container.
// This avoids depending on an iconutil conversion service during asset export.
func bigEndian(_ value: Int) -> Data {
    var integer = UInt32(value).bigEndian
    return withUnsafeBytes(of: &integer) { Data($0) }
}
let types = ["icp4", "ic11", "icp5", "ic12", "ic07", "ic13", "ic08", "ic14", "ic09", "ic10"]
var elements = Data()
for ((name, _), type) in zip(specs, types) {
    let png = try Data(contentsOf: iconset.appendingPathComponent("icon_\(name).png"))
    elements.append(Data(type.utf8))
    elements.append(bigEndian(png.count + 8))
    elements.append(png)
}
var icns = Data("icns".utf8)
icns.append(bigEndian(elements.count + 8))
icns.append(elements)
try icns.write(to: icnsURL)

print("Exported \(icnsURL.path), 10 icon sizes, and 1x/2x menu bar templates")
