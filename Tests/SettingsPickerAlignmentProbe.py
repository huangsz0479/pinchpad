"""Measure the actual rendered dropdown controls, without opening a window.

Uses only in-memory preferences and the production settings views. No desktop
capture, accessibility queries of other apps, event monitors, or app processes.
Run: python3 Tests/SettingsPickerAlignmentProbe.py
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
harness = r'''import AppKit
import SwiftUI

@MainActor final class AppModel: ObservableObject {
    @Published var settings = Preferences()
    func reorganizeNow() {}
    func setGrid(columns: Int, rows: Int) { settings.columns = columns; settings.rows = rows }
}
enum HotKeyCenter { static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 { 0 } }

@main struct SettingsPickerAlignmentProbe {
    @MainActor static func main() {
        let app = NSApplication.shared
        let model = AppModel()
        var failures: [String] = []
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            app.appearance = NSAppearance(named: appearance)
            for alternative in [false, true] {
                model.settings.browsing = alternative ? .scroll : .paged
                model.settings.showOn = alternative ? .main : .cursor
                model.settings.reorganize.sortBy = alternative ? .opened : .name
                let pages: [(String, AnyView, CGFloat)] = [
                    ("layout", AnyView(LayoutSettingsPage(model: model, showReorganize: .constant(false))), 551),
                    ("reorganize", AnyView(ReorganizeSheet(model: model, isPresented: .constant(true))), 420)
                ]
                for (name, page, width) in pages {
                    let host = NSHostingView(rootView: page.frame(width: width))
                    host.frame = NSRect(x: 0, y: 0, width: width, height: 424)
                    host.layoutSubtreeIfNeeded()
                    if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                    }
                    // Menu pickers render a focus-ring view on SwiftUI; the native
                    // adapter exposes NSPopUpButton. Inspect our own render tree.
                    func controls(_ view: NSView) -> [NSView] {
                        if view is NSPopUpButton || String(describing: type(of: view)).contains("FocusRingView") {
                            return view.bounds.height > 20 ? [view] : []
                        }
                        return view.subviews.flatMap(controls)
                    }
                    let rects = controls(host).prefix(3).map { $0.convert($0.bounds, to: host) }
                    print("\(name) \(appearance.rawValue) alternative=\(alternative): \(rects)")
                    if rects.count != 3 { failures.append("\(name): expected three dropdowns"); continue }
                    if rects.contains(where: { abs($0.width - 170) > 1 }) {
                        failures.append("\(name): actual dropdowns do not fill the shared 170-point control column")
                    }
                    if rects.contains(where: { abs($0.minX - rects[0].minX) > 1 || abs($0.maxX - rects[0].maxX) > 1 }) {
                        failures.append("\(name): dropdown leading/trailing edges are misaligned")
                    }
                    let buttons = controls(host).prefix(3).compactMap { $0 as? NSPopUpButton }
                    if buttons.count == 3 {
                        let indices = name == "layout" ? [7, 2, 2] : [2, 0, 1]
                        for (button, index) in zip(buttons, indices) {
                            button.selectItem(at: index)
                            guard let action = button.action else { fatalError("Dropdown has no selection action") }
                            app.sendAction(action, to: button.target, from: button)
                        }
                        if name == "layout" {
                            if model.settings.columns != 10 || model.settings.rows != 6 ||
                               model.settings.browsing != .window || model.settings.showOn != .active {
                                failures.append("Layout dropdown action did not update its bound setting")
                            }
                        } else if model.settings.reorganize.sortBy != .opened ||
                                  model.settings.reorganize.folders != .before ||
                                  model.settings.reorganize.appleApps != .after {
                            failures.append("Reorganize dropdown action did not update its bound setting")
                        }
                    }
                }
            }
        }
        if !failures.isEmpty {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
        print("PASS: layout and reorganize dropdowns align at 170 points in both appearances and update their bound settings")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='pinchpad-picker-') as tmp:
    tmp = Path(tmp)
    # Compile the real card/row support without unrelated settings destinations.
    helpers = (root / 'Sources/SettingsView.swift').read_text().split('struct SettingsCard', 1)[1]
    (tmp / 'SettingsSupport.swift').write_text('import SwiftUI\nstruct SettingsCard' + helpers)
    (tmp / 'Probe.swift').write_text(harness)
    binary = tmp / 'probe'
    subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library', '-module-cache-path',
                    '/tmp/pinchpad-probe-module-cache',
                    *[str(root / f'Sources/{name}.swift') for name in
                      ['Model', 'ClotheslinePreferences', 'PinchClassifier', 'SettingsControls', 'PanelSettingsView']],
                    str(tmp / 'SettingsSupport.swift'), str(tmp / 'Probe.swift'), '-o', str(binary)],
                   check=True, timeout=60)
    subprocess.run([str(binary)], check=True, timeout=20)
