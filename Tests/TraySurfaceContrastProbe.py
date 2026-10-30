"""Check production control outlines on synthetic same-color/busy backgrounds.

Renders only an isolated SwiftUI modifier with ImageRenderer at 1x and 2x. No desktop
capture, live windows, accessibility queries, application discovery, or input.
Native Liquid Glass diffusion is not available in this offline renderer; the
actual always-on outlines and shadows are, so this tests their independent
ability to separate controls even when the glass fill matches the desktop.
Run: python3 Tests/TraySurfaceContrastProbe.py
"""
from pathlib import Path
import argparse
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--surface-source', type=Path, default=root / 'Sources/TrayView.swift')
parser.add_argument('--output', type=Path, default=root / '.build/tray-contrast-review')
args = parser.parse_args()
output = args.output
output.mkdir(parents=True, exist_ok=True)


def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth, cursor = 1, opening + 1
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    return source[start:cursor]


surface = block(args.surface_source.read_text(), 'private struct TrayModuleSurface')
source = r'''import AppKit
import SwiftUI

enum TrayView { static let cornerRadius: CGFloat = 30 }
''' + surface + r'''

struct Backdrop: View {
    let color: NSColor
    let checker: Bool
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(nsColor: color)))
            if checker {
                for y in stride(from: 0, to: Int(size.height), by: 12) {
                    for x in stride(from: 0, to: Int(size.width), by: 12) where (x + y).isMultiple(of: 24) {
                        context.fill(Path(CGRect(x: x, y: y, width: 12, height: 12)), with: .color(.white))
                    }
                }
            }
        }
    }
}

@main struct TraySurfaceContrastProbe {
    static let margin: CGFloat = 24
    @MainActor static func main() throws {
        let app = NSApplication.shared
        var failures: [String] = []
        var leastContrast = Double.infinity
        var minimumByScale: [Int: Double] = [1: .infinity, 2: .infinity]
        for pixelScale in [CGFloat(1), CGFloat(2)] {
            for scheme in [ColorScheme.light, .dark] {
                app.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
                let mode = scheme == .light ? "light" : "dark"
                var backgrounds: [(String, NSColor, Bool)] = [
                    ("white", .white, false), ("black", .black, false),
                    ("middle-gray", NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1), false),
                    ("near-white", NSColor(srgbRed: 0.9, green: 0.9, blue: 0.9, alpha: 1), false),
                    ("near-black", NSColor(srgbRed: 0.12, green: 0.12, blue: 0.12, alpha: 1), false),
                    ("same-surface", .windowBackgroundColor, false),
                    ("blue", NSColor(srgbRed: 0.23, green: 0.48, blue: 0.78, alpha: 1), false),
                    ("red", NSColor(srgbRed: 0.78, green: 0.24, blue: 0.22, alpha: 1), false),
                    ("green", NSColor(srgbRed: 0.24, green: 0.62, blue: 0.35, alpha: 1), false),
                    ("purple", NSColor(srgbRed: 0.58, green: 0.31, blue: 0.72, alpha: 1), false),
                    ("warm", NSColor(srgbRed: 0.69, green: 0.48, blue: 0.34, alpha: 1), false),
                    ("checker", NSColor(srgbRed: 0.25, green: 0.25, blue: 0.25, alpha: 1), true),
                ]
                for step in 1..<20 {
                    let level = CGFloat(step) / 20
                    backgrounds.append(("gray-\(step)", NSColor(srgbRed: level, green: level, blue: level, alpha: 1), false))
                }
                for (name, color, checker) in backgrounds {
                    for (control, controlWidth, controlHeight, capsule) in [
                        ("small", CGFloat(75), CGFloat(75), true),
                        ("medium", CGFloat(162), CGFloat(75), true),
                        ("large", CGFloat(162), CGFloat(162), false),
                    ] {
                        let width = controlWidth + margin * 2
                        let height = controlHeight + margin * 2
                        let background = Backdrop(color: color, checker: checker)
                        let plain = background.frame(width: width, height: height).environment(\.colorScheme, scheme)
                        let surface = Color.clear.frame(width: controlWidth, height: controlHeight)
                            .modifier(TrayModuleSurface(capsule: capsule))
                            .padding(margin)
                            .background(background)
                            .environment(\.colorScheme, scheme)
                        let baseline = render(plain, width: width, height: height, scale: pixelScale)
                        let bitmap = render(surface, width: width, height: height, scale: pixelScale)
                        try save(bitmap, name: "\(Int(pixelScale))x-\(mode)-\(name)-\(control)")
                        // Check independent locations along the horizontal top edge and
                        // vertical left edge, keeping corner anti-aliasing out of the test.
                        let sampleOrigins: [(CGFloat, CGFloat, Bool)] = [
                            (width / 2 - 8, margin, true), (width / 2, margin, true), (width / 2 + 8, margin, true),
                            (margin, height / 2, false),
                        ]
                        let scale = CGFloat(bitmap.pixelsWide) / width
                        if capsule {
                            // Unclipped outlines produced straight fragments beyond
                            // the curved silhouette in the host-cache rendering.
                            // These outside points may contain only a faint shadow.
                            for x in [margin + 0.5, margin + controlWidth - 0.5] {
                                for y in [height / 2 - 17, height / 2 + 17] {
                                    let px = Int(x * scale), py = Int(y * scale)
                                    let outside = contrast(bitmap.colorAt(x: px, y: py)!, baseline.colorAt(x: px, y: py)!)
                                    if outside > 1.8 {
                                        failures.append("\(Int(pixelScale))x/\(mode)/\(name)/\(control) has a straight outline fragment outside its curve")
                                    }
                                }
                            }
                        }
                        for (x, y, verticalScan) in sampleOrigins {
                            var strongest = 1.0
                            // Sample the outer dark and inner light edge. Either polarity
                            // may define the visible boundary on a given desktop color.
                            for step in 0..<max(1, Int(4 * scale)) {
                                let delta = CGFloat(step) / scale
                                let px = Int((x + (verticalScan ? 0 : delta)) * scale)
                                let py = Int((y + (verticalScan ? delta : 0)) * scale)
                                strongest = max(strongest, contrast(bitmap.colorAt(x: px, y: py)!, baseline.colorAt(x: px, y: py)!))
                            }
                            leastContrast = min(leastContrast, strongest)
                            minimumByScale[Int(pixelScale)] = min(minimumByScale[Int(pixelScale)]!, strongest)
                            if strongest < 3 {
                                failures.append("\(Int(pixelScale))x/\(mode)/\(name)/\(control) edge at (\(x),\(y)): \(String(format: "%.2f", strongest)):1")
                            }
                        }
                    }
                }
            }
        }
        if !failures.isEmpty {
            for failure in failures { fputs("FAIL: insufficient boundary contrast: \(failure)\n", stderr) }
            exit(1)
        }
        print("PASS: production outlines exceed 3:1 boundary contrast for all three sizes on light/dark, white/black/gray, matching-surface, color and checkerboard backgrounds")
        print("1x minimum: \(String(format: "%.2f", minimumByScale[1]!)):1; 2x minimum: \(String(format: "%.2f", minimumByScale[2]!)):1")
        print("Minimum measured boundary contrast: \(String(format: "%.2f", leastContrast)):1")
        print("NOTE: native desktop glass diffusion is not tested; the always-on contour is rendered from production code")
    }

    @MainActor static func render<V: View>(_ content: V, width: CGFloat, height: CGFloat, scale: CGFloat) -> NSBitmapImageRep {
        // Explicit rasterization covers both external 1x displays and Retina.
        // NSHostingView.cacheDisplay is still used by TrayLayoutProbe for the
        // full host; this independent path avoids its cached outline fragments.
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        renderer.scale = scale
        guard let image = renderer.cgImage else { fatalError("No bitmap") }
        return NSBitmapImageRep(cgImage: image)
    }
    static func luminance(_ color: NSColor) -> Double {
        let rgb = color.usingColorSpace(.sRGB)!
        func linear(_ v: CGFloat) -> Double {
            let c = Double(v)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
    }
    static func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
    static func save(_ bitmap: NSBitmapImageRep, name: String) throws {
        let data = bitmap.representation(using: .png, properties: [:])!
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name + ".png"))
    }
}
'''
# Permit the same boundary regression to run against the shipped pre-fix view.
# The old surface accepted a numeric radius instead of the explicit capsule flag.
if 'var capsule' not in surface:
    source = source.replace('TrayModuleSurface(capsule: capsule)',
                            'TrayModuleSurface(cornerRadius: capsule ? 1000 : 30)')
with tempfile.TemporaryDirectory(prefix='pinchpad-surface-contrast-') as tmp:
    tmp = Path(tmp)
    (tmp / 'Probe.swift').write_text(source)
    binary = tmp / 'probe'
    subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library', '-module-cache-path',
                    '/tmp/pinchpad-probe-module-cache', str(tmp / 'Probe.swift'), '-o', str(binary)],
                   check=True, timeout=60)
    subprocess.run([str(binary), str(output)], check=True, timeout=30)
