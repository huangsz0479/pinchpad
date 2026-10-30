"""Render production clothesline geometry and card chrome with synthetic apps.

Uses ImageRenderer only: no windows are opened, no desktop is captured, and no
running apps or accessibility elements are inspected. All subprocesses terminate.
Native live-desktop diffusion is not asserted by these offline images.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
output = root / '.build/clothesline/review'
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
model = (root / 'Sources/Model.swift').read_text()
source = '''import AppKit
import SwiftUI
enum TrayView { static let cornerRadius: CGFloat = 30 }
private struct FixtureTransparency: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var fixtureReduceTransparency: Bool {
        get { self[FixtureTransparency.self] }
        set { self[FixtureTransparency.self] = newValue }
    }
}
'''
source += block(model, 'enum TrayAppSize:') + '\n'
for marker in ['private struct TrayModuleSurface', 'private struct CellChrome', 'private struct TrayIconButtonStyle']:
    source += block(tray, marker).replace('\\.accessibilityReduceTransparency', '\\.fixtureReduceTransparency') + '\n'
source += (root / 'Sources/ClotheslineLayout.swift').read_text() + '\n'
source += (root / 'Sources/ClotheslinePreferences.swift').read_text() + '\n'
source += (root / 'Sources/ClotheslineDynamics.swift').read_text() + '\n'
source += (root / 'Sources/HempRope.swift').read_text() + '\n'
source += (root / 'Sources/ClotheslineFastenings.swift').read_text() + '\n'
source += (root / 'Sources/ClotheslineScene.swift').read_text() + '\n'
source += r'''
@main struct RenderProbe {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        let names = ["云盘", "音乐", "系统监控", "快捷工具", "备忘录", "An app with a very long name"]
        let symbols = ["cloud.fill", "music.note", "chart.bar.fill", "bolt.fill", "note.text", "terminal.fill"]
        let colors: [NSColor] = [.systemBlue, .systemBlue, .systemGreen, .systemOrange, .systemYellow, .systemPurple]
        func icon(_ index: Int) -> NSImage {
            let i = index % symbols.count
            return NSImage(size: NSSize(width: 80, height: 80), flipped: false) { rect in
                colors[i].setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 18, yRadius: 18).fill()
                let image = NSImage(systemSymbolName: symbols[i], accessibilityDescription: nil)!
                    .withSymbolConfiguration(.init(pointSize: 36, weight: .medium))!
                let symbol = image.copy() as! NSImage
                symbol.lockFocus()
                NSColor.white.setFill()
                NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
                symbol.unlockFocus()
                symbol.draw(in: CGRect(x: 19, y: 19, width: 42, height: 42))
                return true
            }
        }
        for (mode, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
            app.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            for (name, width, height, count) in [("desktop", 1440.0, 900.0, 4), ("narrow", 640, 480, 8),
                                               ("ultrawide", 2560, 1080, 12), ("empty", 1024, 768, 0)] {
                let items = (0..<count).map { ClotheslineLayout.Item(id: "\($0)", size: [.small, .medium, .large, .medium][$0 % 4]) }
                let layout = ClotheslineLayout(items: items, bounds: CGRect(x: 0, y: 28, width: width, height: height - 28))
                for elapsed in (name == "desktop" ? [0.0, 0.12, 0.3, 2.0, 4.0, 4.15, 4.4, 4.8, 5.2, 5.7, 9.0] : [4.0]) {
                    let simulation = ClotheslineDynamics(layout: layout, page: 0)
                    for frame in 0..<Int(elapsed * 120) {
                        let time = Double(frame) / 120
                        if name == "desktop", frame == 480 {
                            let pose = simulation.frame().poses[1]
                            simulation.beginDrag(id: pose.card.id, at: pose.center)
                        }
                        if name == "desktop", time >= 4 && time < 4.8 {
                            simulation.moveDrag(to: CGPoint(x: 500 + (time - 4) * 400, y: 180 + (time - 4) * 400))
                        }
                        if name == "desktop", frame == 576 { _ = simulation.endDrag() }
                        simulation.advance(by: 1 / 120)
                    }
                    let content = ZStack {
                        LinearGradient(colors: scheme == .light
                                       ? [Color(red: 0.62, green: 0.73, blue: 0.85), Color(red: 0.38, green: 0.54, blue: 0.7)]
                                       : [Color(red: 0.13, green: 0.21, blue: 0.31), Color(red: 0.06, green: 0.1, blue: 0.17)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        ClotheslineScene(layout: layout, page: 0, elapsed: elapsed, selectedID: elapsed >= 1 ? "1" : nil, liveFrame: simulation.frame()) { card in
                            let i = Int(card.id)!
                            CellChrome(icon: icon(i), name: names[i % names.count], size: card.item.size,
                                       hanging: true, action: {}) { EmptyView() }
                        }
                        if layout.pages.count > 1 {
                            ClotheslinePager(page: 0, count: layout.pages.count, turnPage: { _ in })
                                .position(x: width / 2, y: layout.pagerY)
                        }
                        if count == 0 { Text("暂无菜单栏应用").font(.system(size: 17, weight: .medium)) }
                    }
                    .frame(width: width, height: height)
                    .environment(\.colorScheme, scheme)
                    let renderer = ImageRenderer(content: content)
                    renderer.scale = 1
                    renderer.proposedSize = ProposedViewSize(width: width, height: height)
                    guard let image = renderer.cgImage else { fatalError("No image") }
                    precondition(image.width == Int(width) && image.height == Int(height))
                    let bitmap = NSBitmapImageRep(cgImage: image)
                    try bitmap.representation(using: .png, properties: [:])!.write(to:
                        URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("\(mode)-\(name)-\(Int(elapsed * 100)).png"))
                }
            }
        }
        precondition(NSApp.windows.allSatisfy { !$0.isVisible }, "Render probe opened a window")
        print("PASS: production scene and card chrome rendered in light/dark, narrow/ultrawide, empty and seven animation states and keyboard selection; no visible windows")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='pinchpad-clothesline-render-') as temp:
    temp = Path(temp)
    (temp / 'Probe.swift').write_text(source)
    binary = temp / 'probe'
    subprocess.run(['swiftc', '-O', '-swift-version', '5', '-parse-as-library', '-module-cache-path',
                    '/tmp/pinchpad-probe-module-cache', str(temp / 'Probe.swift'), '-o', str(binary)],
                   check=True, timeout=90)
    subprocess.run([str(binary), str(output)], check=True, timeout=45)
