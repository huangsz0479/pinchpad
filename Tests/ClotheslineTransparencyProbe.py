"""Check the actual screen-sized root and window carrier, not just the rope layer.

Render an RGBA image and inspect alpha over empty desktop areas. Instantiate the
production panel offscreen to ensure there is no full-screen visual-effect view.
No window is shown and no desktop content or real applications are inspected.
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


controller = (root / 'Sources/ClotheslineController.swift').read_text()
source = '''import AppKit
import SwiftUI
struct RunningApp: Equatable { let id: String }
@MainActor final class AppModel {}
struct RunningCell: View {
    let app: RunningApp
    let model: AppModel
    var onClose: () -> Void
    var hanging = false
    var canOpen: () -> Bool
    var body: some View { Color.orange.clipShape(RoundedRectangle(cornerRadius: 24)) }
}
'''
source += block((root / 'Sources/Model.swift').read_text(), 'enum TrayAppSize:') + '\n'
for name in ['ClotheslineLayout.swift', 'ClotheslinePreferences.swift', 'ClotheslineDynamics.swift', 'HempRope.swift', 'ClotheslineFastenings.swift', 'ClotheslineScene.swift']:
    source += (root / 'Sources' / name).read_text() + '\n'
source += '@MainActor\n' + block(controller, 'final class ClotheslinePresentation:') + '\n'
source += block(controller, 'private struct ClotheslineAppCard:') + '\n'
source += '@MainActor\n' + block(controller, 'private struct ClotheslineView:') + '\n'
source += block(controller, 'private final class ClotheslinePanel:') + '\n'
source += block((root / 'Sources/AppMain.swift').read_text(), 'final class PanelHost<') + '\n'
source += '''@MainActor final class Carrier {
    let model = AppModel()
    let presentation = ClotheslinePresentation()
    var panel: NSPanel?
    func dismissFromPointer() {}
    func dismiss(animated: Bool = true) {}
    func canHandlePointer() -> Bool { true }
    func turnPage(_ delta: Int) {}
    func window() -> NSPanel { ensurePanel() }
''' + block(controller, 'private func ensurePanel()') + '\n}\n'
source += r'''
@main struct Probe {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let carrier = Carrier()
        let window = carrier.window()
        defer { window.contentView = nil; window.close() }
        precondition(!window.isVisible && !window.isOpaque && window.backgroundColor.alphaComponent == 0,
                     "Screen-sized panel must be invisible at creation and have a clear native background")
        precondition(!(window.contentView is NSVisualEffectView), "Screen-sized blur carrier obscures the desktop")
        let items = (0..<4).map { ClotheslineLayout.Item(id: "\($0)", size: .medium) }
        let layout = ClotheslineLayout(items: items, bounds: CGRect(x: 0, y: 28, width: 1440, height: 872))
        carrier.presentation.content = .init(layout: layout,
            apps: Dictionary(uniqueKeysWithValues: items.map { ($0.id, RunningApp(id: $0.id)) }), page: 0)
        let simulation = ClotheslineDynamics(layout: layout, page: 0)
        simulation.settle()
        carrier.presentation.frame = simulation.frame()
        let view = ClotheslineView(presentation: carrier.presentation, model: carrier.model,
            close: {}, launch: {}, canOpen: { true }, turnPage: { _ in }).frame(width: 1440, height: 900)
        for scale in [CGFloat(1), CGFloat(2)] {
            let renderer = ImageRenderer(content: view)
            renderer.scale = scale
            renderer.proposedSize = ProposedViewSize(width: 1440, height: 900)
            guard let image = renderer.cgImage else { fatalError("No image") }
            let bitmap = NSBitmapImageRep(cgImage: image)
            var transparent = 0
            for y in stride(from: 600, to: 880, by: 20) {
                for x in stride(from: 10, to: 1430, by: 20) {
                    let alpha = bitmap.colorAt(x: Int(CGFloat(x) * scale), y: Int(CGFloat(y) * scale))!.alphaComponent
                    precondition(alpha < 0.001, "Empty desktop area contains dimming or an opaque background")
                    transparent += 1
                }
            }
            let card = simulation.frame().poses[0].center
            precondition(bitmap.colorAt(x: Int(card.x * scale), y: Int(card.y * scale))!.alphaComponent > 0.9,
                         "Transparency check passed by accidentally rendering an empty surface")
            try bitmap.representation(using: .png, properties: [:])!.write(to:
                URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("transparent-root-\(Int(scale))x.png"))
            print("PASS: \(transparent) empty desktop samples have zero alpha at \(Int(scale))x; visible card content retained")
        }
        precondition(NSApp.windows.allSatisfy { !$0.isVisible }, "Probe displayed a native window")
        print("PASS: production window uses a transparent host with no screen-sized blur; offscreen window is closed on exit")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='pinchpad-clothesline-alpha-') as temp:
    temp = Path(temp)
    (temp / 'Probe.swift').write_text(source)
    binary = temp / 'probe'
    subprocess.run(['swiftc', '-O', '-swift-version', '5', '-parse-as-library', '-module-cache-path',
                    '/tmp/pinchpad-probe-module-cache', str(temp / 'Probe.swift'), '-o', str(binary)],
                   check=True, timeout=90)
    subprocess.run([str(binary), str(output)], check=True, timeout=45)
