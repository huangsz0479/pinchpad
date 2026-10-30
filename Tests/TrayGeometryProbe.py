"""Exercise production tray placement against in-memory display fixtures.

No desktop/window queries, input, application startup, or screenshots.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]

def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth, cursor = 1, opening + 1
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    return source[start:cursor]

view = (root / 'Sources/TrayView.swift').read_text()
app = (root / 'Sources/AppMain.swift').read_text()
model = (root / 'Sources/Model.swift').read_text()
grid = (root / 'Sources/TrayGridLayout.swift').read_text()
constants = '\n'.join(line for line in view.splitlines() if any(
    line.strip().startswith(prefix) for prefix in (
        'static let contentWidth:', 'private static let columns',
        'private static let cardSpacing:', 'static let cellHeight:', 'private static let edgePadding:')))
source = r'''import Foundation
import CoreGraphics
''' + block(model, 'enum TrayAppSize:') + '\n' + block(grid, 'struct TrayGridMetrics') + r'''
struct Insets { var top: CGFloat = 0 }
final class NSScreen {
    static var screens: [NSScreen] = []
    static var main: NSScreen? { screens.first }
    var frame: NSRect
    var visibleFrame: NSRect
    var safeAreaInsets = Insets()
    init(_ frame: NSRect, visible: NSRect) { self.frame = frame; visibleFrame = visible }
}
enum NSEvent { static var mouseLocation = NSPoint.zero }
final class NSStatusBar {
    static let system = NSStatusBar()
    let thickness: CGFloat = 25
}
final class Window {
    var screen: NSScreen?
    func convertToScreen(_ rect: NSRect) -> NSRect { rect }
}
final class Button {
    var window: Window?
    var bounds = NSRect(x: 0, y: 875, width: 24, height: 25)
    func convert(_ rect: NSRect, to: Any?) -> NSRect { rect }
}
final class StatusItem { var button: Button? }
final class TrayPanel {
    var frame = NSRect.zero
    var isVisible = false
    var screen: NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) }
    }
    func setFrame(_ frame: NSRect, display: Bool) { self.frame = frame }
    func animator() -> TrayPanel { self }
    func invalidateShadow() {}
}
final class NSWorkspace {
    static let shared = NSWorkspace()
    var accessibilityDisplayShouldReduceMotion = false
}
enum TimingName { case easeInEaseOut }
struct CAMediaTimingFunction { init(name: TimingName) {} }
final class NSAnimationContext {
    static var calls = 0
    var duration: TimeInterval = 0
    var timingFunction: CAMediaTimingFunction?
    static func runAnimationGroup(_ body: (NSAnimationContext) -> Void) {
        calls += 1
        body(NSAnimationContext())
    }
}
final class AppModel {
    static let shared = AppModel()
    var runningApps = [1, 2, 3]
    var pinnedApps = Array(1...7)
    var sizes: [Int: TrayAppSize] = [:]
    func traySize(for app: Int) -> TrayAppSize { sizes[app] ?? .medium }
}
enum TrayView {
''' + constants + '\n' + block(view, 'static func preferredHeight(menuCount:') + '\n' + block(view, 'static func preferredHeight(menuSizes:') + r'''
}
final class AppDelegate {
    var trayPanel: TrayPanel? = TrayPanel()
    var statusItem: StatusItem?
    var lastStatusItemRect: NSRect?
    var trayAdding = false
    var trayTrackingMenus: Set<ObjectIdentifier> = []
    var trayShown = false
    var statusItemDownAt = Date.distantPast
    var dismissCount = 0
    func dismissTray() { trayShown = false; dismissCount += 1 }
''' + block(app, 'private func updateTrayHeight(') + '\n' + block(app, 'private func layoutTray(') + '\n' + block(app, 'private func isStatusItemClick()') + '\n' + block(app, 'private func closeTrayIfClickedOutside()') + r'''
    func clickOutside() { closeTrayIfClickedOutside() }
    func preferredHeightChanged(_ height: CGFloat, adding: Bool = false) { updateTrayHeight(height, adding: adding) }
    func layout(animated: Bool = false) {
        layoutTray(animated: animated)
    }
}

@main struct Probe {
    static func main() {
        let primary = NSScreen(NSRect(x: 0, y: 0, width: 1440, height: 900),
                               visible: NSRect(x: 0, y: 0, width: 1440, height: 875))
        let secondary = NSScreen(NSRect(x: 1440, y: 0, width: 1920, height: 1080),
                                 visible: NSRect(x: 1440, y: 40, width: 1920, height: 1015))
        NSScreen.screens = [primary, secondary]
        NSEvent.mouseLocation = NSPoint(x: 300, y: 400)
        let delegate = AppDelegate()
        delegate.layout()
        let initial = delegate.trayPanel!.frame
        precondition(initial.maxX == primary.visibleFrame.maxX - 12
                     && initial.maxY == primary.visibleFrame.maxY - 8
                     && initial.width == TrayView.contentWidth
                     && initial.height == TrayView.preferredHeight(menuCount: 3, pinnedCount: 7),
                     "Hidden menu-bar icon must anchor the application controls in the active display's upper-right corner")
        precondition(delegate.lastStatusItemRect == nil)
        NSEvent.mouseLocation = NSPoint(x: 1800, y: 500)
        delegate.layout()
        precondition(delegate.trayPanel!.frame.maxX == secondary.visibleFrame.maxX - 12,
                     "Pinch fallback ignored the display under the pointer")
        precondition(delegate.trayPanel!.frame.maxY == secondary.visibleFrame.maxY - 8)
        delegate.trayPanel!.isVisible = true
        delegate.trayShown = true
        NSEvent.mouseLocation = NSPoint(x: 300, y: 400)
        delegate.preferredHeightChanged(500)
        precondition(delegate.trayPanel!.frame.maxX == secondary.visibleFrame.maxX - 12,
                     "Asynchronous menu refresh must not move an open panel to the pointer's new display")
        delegate.trayShown = false
        delegate.trayPanel!.isVisible = false
        let appModel = AppModel.shared
        appModel.runningApps = []
        appModel.pinnedApps = []
        delegate.preferredHeightChanged(420, adding: true)
        delegate.layout()
        precondition(delegate.trayPanel!.frame.height == 420,
                     "Retained add mode must keep its preferred height after closing/reopening")
        delegate.layout()
        precondition(delegate.trayPanel!.frame.height == 420,
                     "Screen changes must retain add mode's preferred height")
        delegate.preferredHeightChanged(420, adding: false)
        // Opening height must use the saved per-app sizes, even before SwiftUI
        // has delivered a height change. The panel always expands downwards.
        appModel.runningApps = []
        appModel.pinnedApps = [1, 2, 3, 4]
        var sizeHeights: [CGFloat] = []
        for size in TrayAppSize.allCases {
            appModel.sizes = Dictionary(uniqueKeysWithValues: appModel.pinnedApps.map { ($0, size) })
            delegate.layout()
            let expected = TrayView.preferredHeight(menuSizes: [], pinnedSizes: Array(repeating: size, count: 4))
            precondition(delegate.trayPanel!.frame.height == expected,
                         "Opening ignored persisted individual app sizes")
            precondition(delegate.trayPanel!.frame.maxY == primary.visibleFrame.maxY - 8,
                         "Resizing app controls moved the menu-bar anchor")
            sizeHeights.append(expected)
        }
        precondition(sizeHeights[0] < sizeHeights[1] && sizeHeights[1] < sizeHeights[2],
                     "Small, medium and large selections must change panel geometry")

        // A previously reported SwiftUI height belongs to its old width. It
        // must never seed the initial frame on another display or overwrite it
        // when an asynchronous old-width measurement arrives after the move.
        let wideHeight = delegate.trayPanel!.frame.height
        delegate.preferredHeightChanged(wideHeight)
        let narrow = NSScreen(NSRect(x: 1440, y: 0, width: 320, height: 900),
                              visible: NSRect(x: 1440, y: 0, width: 320, height: 875))
        NSScreen.screens = [primary, narrow]
        NSEvent.mouseLocation = NSPoint(x: 1500, y: 400)
        delegate.layout()
        let narrowExpected = TrayView.preferredHeight(menuSizes: [], pinnedSizes: Array(repeating: .large, count: 4), width: 296)
        precondition(delegate.trayPanel!.frame.width == 296 && delegate.trayPanel!.frame.height == narrowExpected,
                     "Reopening on a narrower display reused a height from the previous display")
        precondition(narrowExpected != wideHeight, "Fixture must expose width-dependent heights")
        delegate.trayShown = true
        delegate.trayPanel!.isVisible = true
        delegate.preferredHeightChanged(wideHeight)
        precondition(delegate.trayPanel!.frame.height == narrowExpected,
                     "A delayed old-width height callback poisoned current display geometry")
        delegate.trayShown = false
        delegate.trayPanel!.isVisible = false
        appModel.pinnedApps = []
        delegate.preferredHeightChanged(wideHeight, adding: true)
        delegate.layout()
        precondition(delegate.trayPanel!.frame.height == 420,
                     "Adding mode must keep its minimum height across width changes")
        delegate.preferredHeightChanged(420, adding: false)
        delegate.layout()
        precondition(delegate.trayPanel!.frame.height == TrayView.preferredHeight(menuSizes: [], pinnedSizes: [], width: 296),
                     "Leaving adding mode retained its minimum-height floor")
        NSScreen.screens = [primary, secondary]
        NSEvent.mouseLocation = NSPoint(x: 300, y: 400)
        appModel.runningApps = [1, 2, 3]
        appModel.pinnedApps = Array(1...7)
        appModel.sizes = [:]
        let button = Button()
        button.window = Window()
        button.window!.screen = primary
        let status = StatusItem()
        status.button = button
        delegate.statusItem = status
        delegate.layout()
        precondition(delegate.trayPanel!.frame.minX == 12, "Menu-bar anchor must clamp to the usable display edge")
        precondition(delegate.lastStatusItemRect == button.bounds)
        let top = delegate.trayPanel!.frame.maxY
        appModel.sizes = Dictionary(uniqueKeysWithValues: appModel.pinnedApps.map { ($0, TrayAppSize.small) })
        delegate.layout(animated: true)
        let smallExpected = TrayView.preferredHeight(menuSizes: Array(repeating: .small, count: 3),
                                                    pinnedSizes: Array(repeating: .small, count: 7))
        precondition(delegate.trayPanel!.frame.maxY == top && delegate.trayPanel!.frame.height == smallExpected,
                     "App-list updates must resize down from the same top anchor")
        let animationCount = NSAnimationContext.calls
        precondition(animationCount >= 1)
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion = true
        appModel.sizes = [:]
        delegate.layout(animated: true)
        precondition(NSAnimationContext.calls == animationCount, "Reduce Motion must bypass resizing animations")
        let tiny = NSScreen(NSRect(x: 0, y: 0, width: 320, height: 240),
                            visible: NSRect(x: 0, y: 0, width: 320, height: 215))
        NSScreen.screens = [tiny]
        delegate.statusItem = nil
        NSEvent.mouseLocation = NSPoint(x: 160, y: 100)
        delegate.layout()
        let small = delegate.trayPanel!.frame
        precondition(small.minX >= 12 && small.maxX <= 308 && small.minY >= 12 && small.maxY <= 207,
                     "Small display must keep every organizer edge inside the usable bounds")
        NSScreen.screens = [primary]
        let clicks = AppDelegate()
        clicks.trayPanel!.frame = NSRect(x: 1000, y: 400, width: 380, height: 450)
        clicks.trayShown = true
        NSEvent.mouseLocation = NSPoint(x: 100, y: 100)
        clicks.clickOutside()
        guard clicks.dismissCount == 1 else {
            print("FAIL: hidden menu-bar icon classifies an outside click as a status-item click")
            exit(1)
        }
        clicks.trayShown = true
        clicks.statusItem = status
        NSEvent.mouseLocation = NSPoint(x: 12, y: 885)
        clicks.clickOutside()
        precondition(clicks.trayShown && clicks.dismissCount == 1,
                     "Clicking the real menu-bar item must remain protected")
        button.window = nil
        clicks.clickOutside()
        precondition(clicks.trayShown, "Temporary missing button window must use the cached icon hit area")
        NSEvent.mouseLocation = NSPoint(x: 100, y: 100)
        clicks.clickOutside()
        precondition(!clicks.trayShown && clicks.dismissCount == 2,
                     "Outside clicks must still close while a button window is rebuilt")
        clicks.trayShown = true
        clicks.lastStatusItemRect = nil
        clicks.clickOutside()
        precondition(clicks.trayShown, "A rebuilding status item without a cache must preserve the new popup")
        clicks.statusItem = nil
        NSEvent.mouseLocation = NSPoint(x: 1100, y: 500)
        clicks.clickOutside()
        precondition(clicks.trayShown, "Clicks inside the tray must not dismiss it when the icon is hidden")
        print("PASS: hidden-icon outside dismissal, real icon protection, temporary missing button window and inside clicks")
        print("PASS: persisted small/medium/large sizes drive initial height while preserving the top anchor")
        print("PASS: cross-display width changes and stale height callbacks recompute current geometry; adding retains only its 420pt floor")
        print("PASS: hidden icon, pointer display, menu anchor, retained add mode, stable display, top-anchored resize, Reduce Motion and small displays")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='pinchpad-tray-geometry-') as tmp:
    tmp = Path(tmp)
    file = tmp / 'Probe.swift'
    file.write_text(source)
    binary = tmp / 'probe'
    subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library', '-module-cache-path',
                    '/tmp/pinchpad-probe-module-cache', str(file), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=10)
