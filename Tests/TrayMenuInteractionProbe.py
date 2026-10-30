"""Replay tray context-menu tracking through production notification handlers.

Uses Foundation notifications with in-memory menus/windows/events. It never
opens a menu or window, queries accessibility, or posts native input events.
Run: python3 Tests/TrayMenuInteractionProbe.py
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


app = (root / 'Sources/AppMain.swift').read_text()
tracking = '\n'.join(block(app, marker) for marker in (
    'private func installTrayMenuObservers()',
    '@objc private func trayMenuDidBeginTracking(',
    '@objc private func trayMenuDidEndTracking(',
))
shown = block(app, 'private var trayShown =')
# Keep the real tray-routing branch; full-launcher handling is a different path.
tray_input = block(app, 'private func handleInput(').split(
    '        guard let panel, AppModel.shared.isOpen')[0] + '        return event\n    }'
outside = block(app, 'private func closeTrayIfClickedOutside()')
status_hit = block(app, 'private func isStatusItemClick()')

source = r'''import Foundation
import CoreGraphics

final class NSMenu: NSObject {
    static let didBeginTrackingNotification = Notification.Name("FixtureMenuDidBeginTracking")
    static let didEndTrackingNotification = Notification.Name("FixtureMenuDidEndTracking")
}
class Window: NSObject {
    var frame = NSRect(x: 0, y: 0, width: 360, height: 600)
    var isKeyWindow = false
    func convertToScreen(_ rect: NSRect) -> NSRect { rect }
}
final class TrayPanel: Window {}
final class Button {
    var window: Window?
    var bounds = NSRect(x: 0, y: 875, width: 24, height: 25)
    func convert(_ rect: NSRect, to: Any?) -> NSRect { rect }
}
final class StatusItem { var button: Button? }
enum EventType { case leftMouseDown, rightMouseDown, keyDown, mouseMoved }
final class NSEvent {
    static var mouseLocation = NSPoint(x: 900, y: 900)
    var type: EventType
    var keyCode: UInt16
    var window: Window?
    init(_ type: EventType, window: Window? = nil, keyCode: UInt16 = 0) {
        self.type = type; self.window = window; self.keyCode = keyCode
    }
}
final class AppDelegate: NSObject {
''' + shown + r'''
    private var trayTrackingMenus: Set<ObjectIdentifier> = []
    var trayPanel: TrayPanel? = TrayPanel()
    var statusItem: StatusItem?
    var statusItemDownAt = Date.distantPast
    var lastStatusItemRect: NSRect?
    var dismissCount = 0
    var sizeSelections = 0
    func dismissTray() { trayShown = false; dismissCount += 1 }
''' + tracking + '\n' + tray_input + '\n' + outside + '\n' + status_hit + r'''
    func start() { installTrayMenuObservers() }
    func stop() { NotificationCenter.default.removeObserver(self) }
    func show() { trayShown = true }
    var shown: Bool { trayShown }
    var menuCount: Int { trayTrackingMenus.count }
    func route(_ event: NSEvent) -> NSEvent? { handleInput(event) }
    func clickOutside() { closeTrayIfClickedOutside() }
    func selectSize(after event: NSEvent) {
        if route(event) != nil && trayShown { sizeSelections += 1 }
    }
}

@main struct Probe {
    static func main() {
        let delegate = AppDelegate()
        delegate.start()
        defer { delegate.stop() }
        let menu = NSMenu()
        let submenu = NSMenu()
        let menuWindow = Window()
        func begin(_ menu: NSMenu) {
            NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        }
        func end(_ menu: NSMenu) {
            NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu)
        }

        begin(menu)
        precondition(delegate.menuCount == 0, "A menu opened while the tray is hidden must not be tracked")
        delegate.show()
        begin(menu)
        begin(menu)
        precondition(delegate.menuCount == 1, "Duplicate begin notifications must not leave tracking stuck")
        begin(submenu)
        precondition(delegate.menuCount == 2)
        let click = NSEvent(.leftMouseDown, window: menuWindow)
        delegate.selectSize(after: click)
        precondition(delegate.shown && delegate.dismissCount == 0 && delegate.sizeSelections == 1,
                     "Choosing an app size closes the tray before the menu action can run")
        let escape = NSEvent(.keyDown, window: delegate.trayPanel, keyCode: 53)
        delegate.trayPanel?.isKeyWindow = true
        precondition(delegate.route(escape) === escape && delegate.shown,
                     "Escape must close the submenu before it can dismiss the tray")
        delegate.clickOutside()
        precondition(delegate.shown, "Global outside-click routing interrupted menu tracking")
        end(submenu)
        precondition(delegate.menuCount == 1)
        let secondClick = NSEvent(.rightMouseDown, window: menuWindow)
        precondition(delegate.route(secondClick) === secondClick && delegate.shown,
                     "Ending a submenu must not remove the root menu's input protection")
        end(menu)
        end(menu)
        precondition(delegate.menuCount == 0)
        delegate.clickOutside()
        precondition(!delegate.shown && delegate.dismissCount == 1,
                     "Outside dismissal did not resume after menu tracking ended")

        delegate.show()
        begin(menu)
        delegate.dismissTray()
        precondition(delegate.menuCount == 0, "Closing the tray must clear pending menu identities")
        end(menu)
        delegate.show()
        precondition(delegate.route(escape) == nil && !delegate.shown,
                     "Escape stopped dismissing the tray after a tracked menu closed")
        delegate.show()
        let otherWindowClick = NSEvent(.leftMouseDown, window: Window())
        _ = delegate.route(otherWindowClick)
        precondition(!delegate.shown, "Ordinary same-process outside clicks must still dismiss")
        print("PASS: root/submenu size selection and Escape reach the menu without dismissing the tray")
        print("PASS: duplicate notifications, hidden menus, close/reopen and tracking teardown remain balanced")
        print("PASS: local and global outside-click dismissal resume after menu tracking ends")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='pinchpad-tray-menu-') as temp:
    temp = Path(temp)
    (temp / 'Probe.swift').write_text(source)
    binary = temp / 'probe'
    subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library', '-module-cache-path',
                    '/tmp/pinchpad-probe-module-cache', str(temp / 'Probe.swift'), '-o', str(binary)],
                   check=True, timeout=60)
    subprocess.run([str(binary)], check=True, timeout=15)
