"""Verify production gesture bindings and entry-point exclusivity with recorders.
Never opens a native window, installs gesture hooks or reads the user's desktop.
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
model = (root / 'Sources/AppModel.swift').read_text()
source = r'''import Foundation
import AppKit
@MainActor final class AppModel {
    static let shared = AppModel()
    var isOpen = false
    var notice: String?
    func close(animated: Bool = true) { isOpen = false }
    func openFromPinch() { isOpen = true; AppDelegate.current?.dismissCompanionPanels() }
    func toggle() { isOpen.toggle() }
    func bind() { wireMonitors() }
''' + block(model, 'private func wireMonitors()') + r'''
}
@MainActor final class HangingSurface {
    var isShown = false
    var openings = 0
    func show() {
        precondition(!AppModel.shared.isOpen,
                     "Other surfaces must close before revealing clothesline")
        isShown = true; openings += 1
    }
    func dismiss(animated: Bool = true) { isShown = false }
}
@MainActor final class AppDelegate: NSObject {
    static var current: AppDelegate?
    let clothesline = HangingSurface()
    var menus = 0
    private func popTrayMenu() { menus += 1 }
    func click() { statusClicked(nil) }
''' + '\n'.join(block(app, marker) for marker in ['@objc private func statusClicked(', '@objc private func openSettingsFromTray()', 'func applicationShouldHandleReopen(', 'func openClotheslineFromPinch()', 'func dismissCompanionPanels()']) + r'''
}
@MainActor enum SettingsOpener {
    static var openings = 0
    static func open() {
        precondition(!AppModel.shared.isOpen && !AppDelegate.current!.clothesline.isShown)
        openings += 1
    }
}
@main struct Probe {
    @MainActor static func main() {
        let delegate = AppDelegate()
        AppDelegate.current = delegate
        let model = AppModel.shared
        model.bind()
        _ = delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false)
        precondition(SettingsOpener.openings == 1 && !delegate.clothesline.isShown)
        PinchMonitor.shared.onOpen?(3)
        precondition(delegate.clothesline.isShown && !model.isOpen)
        PinchMonitor.shared.onOpen?(3)
        precondition(delegate.clothesline.openings == 1)
        _ = delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: true)
        precondition(SettingsOpener.openings == 2 && !delegate.clothesline.isShown)
        PinchMonitor.shared.onOpen?(3)
        delegate.click()
        precondition(SettingsOpener.openings == 3 && !delegate.clothesline.isShown && delegate.menus == 0,
                     "Left menu-bar click still opens an intermediary panel")
        PinchMonitor.shared.onOpen?(4)
        precondition(model.isOpen && !delegate.clothesline.isShown)
        PinchMonitor.shared.onOpen?(3)
        precondition(!model.isOpen && delegate.clothesline.isShown)
        PinchMonitor.shared.onClose?(4)
        precondition(!model.isOpen && !delegate.clothesline.isShown)
        PinchMonitor.shared.onOpen?(3)
        PinchMonitor.shared.onClose?(3)
        precondition(!delegate.clothesline.isShown)
        print("PASS: actual gesture bindings route three fingers to clothesline, icon reopen to settings, four fingers to launcher")
        print("PASS: entry-point exclusivity, repeated pinch and either outward gesture dismissing all companion surfaces")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='pinchpad-clothesline-routing-') as temp:
    temp = Path(temp)
    (temp / 'Probe.swift').write_text(source)
    binary = temp / 'probe'
    subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library', '-module-cache-path',
                    '/tmp/pinchpad-probe-module-cache', str(root / 'Sources/Model.swift'), str(root / 'Sources/ClotheslinePreferences.swift'),
                    str(root / 'Sources/PinchClassifier.swift'), str(root / 'Sources/Services.swift'),
                    str(temp / 'Probe.swift'), '-lsqlite3', '-o', str(binary)], check=True, timeout=60)
    subprocess.run([str(binary)], check=True, timeout=10)
