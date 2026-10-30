import AppKit

// Usage: swift generate-icon.swift <output.iconset> <menubar-output-directory>
// Renders the D1 origami app icon and its matching 18pt template glyph.
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

// The selected D1 design is preserved as its original three path contours.
// All rendered assets and editable SVGs below use this single source of geometry.
struct Fold {
    let id: String
    let hex: UInt32
    let data: String
    var path: CGPath { contour(data) }
}

// D1 uses absolute move, line and cubic commands (including repeated coordinates).
func contour(_ data: String) -> CGPath {
    let expression = try! NSRegularExpression(pattern: #"[MLC]|-?(?:[0-9]*\.)?[0-9]+"#)
    let tokens = expression.matches(in: data, range: NSRange(data.startIndex..., in: data))
        .map { String(data[Range($0.range, in: data)!]) }
    let path = CGMutablePath()
    var index = 0
    var command = ""
    func number() -> CGFloat {
        defer { index += 1 }
        return CGFloat(Double(tokens[index])!)
    }
    func point() -> CGPoint { CGPoint(x: number(), y: number()) }
    while index < tokens.count {
        if ["M", "L", "C"].contains(tokens[index]) {
            command = tokens[index]
            index += 1
        }
        switch command {
        case "M": path.move(to: point()); command = "L"
        case "L": path.addLine(to: point())
        case "C":
            let first = point(), second = point(), end = point()
            path.addCurve(to: end, control1: first, control2: second)
        default: fatalError("Unsupported D1 contour command")
        }
    }
    path.closeSubpath()
    return path
}

let folds = [
    Fold(id: "fold-top", hex: 0xfda26c, data: "M 503.500 196.661 C 499.345 197.551, 493 200.200, 493 201.044 C 493 201.527, 499.188 208.144, 506.750 215.747 C 514.313 223.351, 555.445 265.106, 598.157 308.536 C 640.868 351.966, 685.418 397.004, 697.157 408.620 C 708.895 420.236, 733.775 445.211, 752.445 464.120 C 771.114 483.029, 814.523 526.734, 848.910 561.242 C 895.135 607.631, 911.639 623.610, 912.231 622.551 C 912.672 621.763, 912.913 543.579, 912.765 448.809 L 912.497 276.500 910.202 268.626 C 905.517 252.550, 897.332 238.294, 886.120 226.679 C 870.763 210.768, 852.875 201.092, 832.119 197.465 C 824.976 196.216, 800.237 196.017, 664.619 196.116 C 577.104 196.180, 504.600 196.425, 503.500 196.661"),
    Fold(id: "fold-left", hex: 0xf1684b, data: "M 462.286 203.451 C 456.283 205.327, 449.672 209.415, 443.148 215.287 C 440.042 218.082, 419.201 237.839, 396.836 259.190 C 351.126 302.828, 349.277 305.044, 343.158 323.500 C 341.640 328.076, 341.500 342.737, 341.500 496.500 L 341.500 664.500 343.794 673 C 346.631 683.513, 354.340 699.606, 360.338 707.535 C 362.820 710.816, 367.107 715.707, 369.866 718.404 L 374.882 723.308 461.604 637.317 L 548.326 551.327 548.413 485.413 L 548.500 419.500 550.837 415 C 554.260 408.410, 558.701 404.256, 564.736 401.998 C 569.806 400.101, 572.543 400, 619.121 400 C 647.663 400, 668.027 399.625, 667.833 399.103 C 667.559 398.365, 562.300 290.928, 493.570 221.234 C 473.846 201.233, 472.262 200.333, 462.286 203.451"),
    Fold(id: "fold-bottom", hex: 0xe0563d, data: "M 706 486.318 C 706 543.652, 706.101 542.858, 697.685 551.502 C 689.066 560.355, 690.950 560.148, 623.361 559.654 C 591.538 559.422, 564.286 559.067, 562.803 558.866 C 560.425 558.543, 555.991 562.579, 525.297 593 C 435.465 682.034, 386 731.366, 386 731.923 C 386 732.925, 396.039 738.594, 402.921 741.478 C 406.452 742.958, 412.752 745.143, 416.921 746.333 L 424.500 748.496 613.500 748.782 C 748.343 748.986, 804.406 748.751, 809.153 747.960 C 817.180 746.623, 826.455 742.392, 833.382 736.908 C 836.197 734.679, 852.362 719.725, 869.305 703.677 C 888.459 685.535, 901.598 672.287, 904.046 668.649 C 908.232 662.428, 911.049 654.613, 910.924 649.568 C 910.882 647.881, 910.320 645.058, 909.674 643.296 C 908.911 641.213, 886.632 618.123, 845.992 577.296 C 811.613 542.758, 766.293 497.063, 745.281 475.750 C 724.270 454.438, 706.836 437, 706.539 437 C 706.243 437, 706 459.193, 706 486.318"),
]
let foldPaths = folds.map { $0.path }
let markBounds = foldPaths.reduce(CGRect.null) { $0.union($1.boundingBoxOfPath) }
let appPlate = CGRect(x: 100, y: 100, width: 824, height: 824)
let appMark = CGRect(x: 232, y: 232, width: 560, height: 560)
let menuMark = CGRect(x: 1, y: 1, width: 16, height: 16)

func color(_ hex: UInt32) -> CGColor {
    // Explicit sRGB preserves the selected SVG colors through AppKit export.
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [
        CGFloat((hex >> 16) & 255) / 255,
        CGFloat((hex >> 8) & 255) / 255,
        CGFloat(hex & 255) / 255, 1])!
}

func drawMark(_ ctx: CGContext, in rect: CGRect, monochrome: Bool = false) {
    let scale = min(rect.width / markBounds.width, rect.height / markBounds.height)
    ctx.saveGState()
    ctx.translateBy(x: rect.midX, y: rect.midY)
    // Source SVG coordinates increase downward; Core Graphics increases upward.
    ctx.scaleBy(x: scale, y: -scale)
    ctx.translateBy(x: -markBounds.midX, y: -markBounds.midY)
    for (fold, path) in zip(folds, foldPaths) {
        ctx.setFillColor(monochrome ? CGColor(gray: 0, alpha: 1) : color(fold.hex))
        ctx.addPath(path)
        ctx.fillPath(using: .evenOdd)
    }
    ctx.restoreGState()
}

func menuIcon(scale: Int) -> NSBitmapImageRep {
    let rep = bitmap(width: 18 * scale, height: 18 * scale)
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    // Separate faces retain the original transparent fold seams at menu bar size.
    drawMark(ctx, in: menuMark, monochrome: true)
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
    ctx.addPath(squircle(appPlate))
    ctx.setFillColor(color(0xfefdfb))
    ctx.fillPath()
    drawMark(ctx, in: appMark)
    return rep
}

func svgMark(in rect: CGRect, monochrome: Bool = false) -> String {
    let scale = min(rect.width / markBounds.width, rect.height / markBounds.height)
    let x = rect.midX - markBounds.midX * scale
    let y = rect.midY - markBounds.midY * scale
    let paths = folds.map { fold in
        let fill = monochrome ? "#000000" : String(format: "#%06x", fold.hex)
        return "<path id=\"\(fold.id)\" fill=\"\(fill)\" fill-rule=\"evenodd\" d=\"\(fold.data) Z\"/>"
    }.joined(separator: "\n")
    return "<g transform=\"translate(\(x) \(y)) scale(\(scale))\">\n\(paths)\n</g>"
}

func svgPlate() -> String {
    let points = (0...480).map { step -> String in
        let angle = CGFloat(step) / 480 * 2 * .pi
        let c = cos(angle), s = sin(angle)
        let x = appPlate.midX + appPlate.width / 2 * pow(abs(c), 2 / 4.5) * (c >= 0 ? 1 : -1)
        let y = appPlate.midY + appPlate.height / 2 * pow(abs(s), 2 / 4.5) * (s >= 0 ? 1 : -1)
        return "\(step == 0 ? "M" : "L") \(x) \(y)"
    }.joined(separator: " ")
    return "<path fill=\"#fefdfb\" d=\"\(points) Z\"/>"
}

let appSVG = """
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024" role="img" aria-label="Pinchpad application icon">
\(svgPlate())
\(svgMark(in: appMark))
</svg>
"""
let menuSVG = """
<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18" role="img" aria-label="Pinchpad menu bar template">
\(svgMark(in: menuMark, monochrome: true))
</svg>
"""
try appSVG.write(to: menuDirectory.appendingPathComponent("AppIcon.svg"), atomically: true, encoding: .utf8)
try menuSVG.write(to: menuDirectory.appendingPathComponent("MenuBarIcon.svg"), atomically: true, encoding: .utf8)

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

print("Exported \(icnsURL.path), 10 icon sizes, editable SVGs, and 1x/2x menu bar templates")
