"""Measure icon centering through the actual hosted card and material branches.

Only this fixture's own NSHostingView is rendered. No native window is shown,
no desktop pixels are captured, and no user applications are inspected.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
output = root / '.build/clothesline/alignment'
output.mkdir(parents=True, exist_ok=True)


def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth, cursor = 1, opening + 1
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    return source[start:cursor]


tray = (root / 'Sources/TrayView.swift').read_text()
source = '''import AppKit
import SwiftUI
enum TrayView { static let cornerRadius: CGFloat = 30 }
private struct FixtureTransparency: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var fixtureReduceTransparency: Bool {
        get { self[FixtureTransparency.self] }
        set { self[FixtureTransparency.self] = newValue }
    }
}
'''
source += block((root / 'Sources/Model.swift').read_text(), 'enum TrayAppSize:') + '\n'
for marker in ['private struct TrayModuleSurface', 'private struct CellChrome', 'private struct TrayIconButtonStyle']:
    source += block(tray, marker).replace('\\.accessibilityReduceTransparency', '\\.fixtureReduceTransparency') + '\n'
for name in ['ClotheslineLayout.swift', 'HempRope.swift', 'ClotheslineFastenings.swift', 'ClotheslineScene.swift']:
    source += (root / 'Sources' / name).read_text() + '\n'
source += r'''
@main struct AlignmentProbe {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.appearance = NSAppearance(named: .aqua)
        let icon = NSImage(size: NSSize(width: 56, height: 56), flipped: false) { rect in
            NSColor.red.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
            return true
        }
        let layout = ClotheslineLayout(items: [.init(id: "fixture", size: .small)],
                                      bounds: CGRect(x: 0, y: 28, width: 640, height: 472))
        let cutout = HangingCardShape().path(in: CGRect(x: 0, y: 0, width: 64, height: 64)).cgPath
        for hole in layout.cards(on: 0)[0].holes {
            for direction in [CGPoint(x: 1, y: 0), CGPoint(x: -1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 0, y: -1)] {
                precondition(!cutout.contains(CGPoint(x: hole.x + 2 * direction.x, y: hole.y + 2 * direction.y), using: .evenOdd),
                             "Upper-corner hole is missing or smaller than its twin")
                precondition(cutout.contains(CGPoint(x: hole.x + 3 * direction.x, y: hole.y + 3 * direction.y), using: .evenOdd),
                             "Upper-corner hole is larger than its twin")
            }
        }
        var failures = 0
        for reduced in [false, true] {
            for elapsed in [0.3, 1.0, 8.0] {
                let pose = layout.poses(page: 0, elapsed: elapsed)[0]
                let view = ZStack {
                    Color(white: 0.9)
                    ClotheslineScene(layout: layout, page: 0, elapsed: elapsed) { _ in
                        CellChrome(icon: icon, name: "Fixture", hanging: true, action: {}) { EmptyView() }
                    }
                }
                .frame(width: 640, height: 500)
                .environment(\.fixtureReduceTransparency, reduced)
                .environment(\.colorScheme, .light)
                let host = NSHostingView(rootView: view)
                host.frame = CGRect(x: 0, y: 0, width: 640, height: 500)
                let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 640, height: 500),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                defer { window.contentView = nil; window.close() }
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No bitmap") }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let name = "\(reduced ? "opaque" : "native")-\(Int(elapsed * 100))"
                try bitmap.representation(using: .png, properties: [:])!.write(to:
                    URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name + ".png"))
                let scale = CGFloat(bitmap.pixelsWide) / 640
                var count: CGFloat = 0, xSum: CGFloat = 0, ySum: CGFloat = 0
                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide {
                        let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                        if color.redComponent > 0.7 && color.greenComponent < 0.25 && color.blueComponent < 0.25 {
                            count += 1; xSum += CGFloat(x) + 0.5; ySum += CGFloat(y) + 0.5
                        }
                    }
                }
                let observed = CGPoint(x: xSum / max(1, count) / scale, y: ySum / max(1, count) / scale)
                let error = hypot(observed.x - pose.center.x, observed.y - pose.center.y)
                let coverage = count / (scale * scale)
                print("\(name): center error \(String(format: "%.2f", error))pt; icon area \(Int(coverage))pt²")
                if error > 1.5 || coverage < 2400 { failures += 1 }
            }
        }
        precondition(NSApp.windows.allSatisfy { !$0.isVisible }, "Probe displayed a window")
        guard failures == 0 else {
            fputs("FAIL: icon is displaced from the card centre or clipped in \(failures) hosted renders\n", stderr)
            exit(1)
        }
        print("PASS: hosted icon stays centred and complete while swinging and settled, with native and reduced-transparency surfaces")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='pinchpad-clothesline-alignment-') as temp:
    temp = Path(temp)
    (temp / 'Probe.swift').write_text(source)
    binary = temp / 'probe'
    subprocess.run(['swiftc', '-O', '-swift-version', '5', '-parse-as-library', '-module-cache-path',
                    '/tmp/pinchpad-probe-module-cache', str(temp / 'Probe.swift'), '-o', str(binary)],
                   check=True, timeout=90)
    subprocess.run([str(binary), str(output)], check=True, timeout=30)
