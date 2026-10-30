"""Render the real settings views with in-memory fixtures, without opening windows.

No desktop capture, accessibility inspection, input events, device hooks, or user
library reads. Checks natural page height, absence of scrolling containers, and
pagination through removal/empty states. PNGs are written to .build/settings-review.
Run: python3 Tests/SettingsLayoutProbe.py
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
output = root / '.build/settings-review'
output.mkdir(parents=True, exist_ok=True)
harness = r'''import AppKit
import SwiftUI

@MainActor final class AppModel: ObservableObject {
    @Published var settings = Preferences()
    @Published var notice: String?
    @Published var apps: [AppItem] = []
    @Published var isScanning = false
    var hotKeyLabel = "⌃⌥⇧⌘F12"
    var terminalHotKeyLabel = "⌃⌥T"
    var terminalAppLabel = "Terminal"
    var runningApps: [RunningApp] = []
    var pinnedApps: [AppItem] { Array(apps.prefix(7)) }
    func chooseTerminalDirectory() {}
    func chooseTerminalApp() {}
    func reorganizeNow() {}
    func addSource() {}
    func rescan() {}
    func importSystemLayout() {}
    func removeSource(_ id: UUID) { settings.sources.removeAll { $0.id == id } }
    func unhide(_ id: String) { if let index = apps.firstIndex(where: { $0.id == id }) { apps[index].hidden = false } }
    func setGrid(columns: Int, rows: Int) { settings.columns = columns; settings.rows = rows }
    func icon(for app: AppItem) -> NSImage { NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)! }
    func isRunning(_ app: AppItem) -> Bool { false }
    func isPinned(_ app: AppItem) -> Bool { pinnedApps.contains(app) }
    func togglePin(_ app: AppItem) {}
    func traySize(for app: AppItem) -> TrayAppSize { settings.traySize(bundleID: app.bundleID, path: app.path) }
    func traySize(for app: RunningApp) -> TrayAppSize { settings.traySize(bundleID: app.bundleID, path: app.path) }
    func setTraySize(_ size: TrayAppSize, for app: AppItem) { settings.setTraySize(size, bundleID: app.bundleID, path: app.path) }
    func setTraySize(_ size: TrayAppSize, for app: RunningApp) { settings.setTraySize(size, bundleID: app.bundleID, path: app.path) }
    func launch(_ app: AppItem) {}
    func reveal(_ app: AppItem) {}
    func open() {}
    func catalogApp(bundleID: String) -> AppItem? { nil }
}
struct RunningApp: Identifiable {
    let id: String
    var name: String { id }
    var icon: NSImage? { NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) }
    var bundleID: String? { "fixture.\(id)" }
    var path: String { "/fixture/\(id).app" }
    var isFrontmost: Bool { false }
    func open() {}
    func activate() {}
    func terminate() {}
    func pressMenuBarItem() -> Bool { false }
}
enum SettingsOpener { static func open() {} }
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    var recordCardKey: ((UInt16) -> Void)?
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 { 0 }
    static func title(keyCode: UInt32, modifiers: UInt32) -> String { "F4" }
}

@main struct SettingsLayoutProbe {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.applicationIconImage = NSImage(contentsOfFile: CommandLine.arguments[2])
        let model = AppModel()
        model.settings.pinchThreeSensitivity = .low
        model.settings.pinchFourSensitivity = .veryHigh
        model.settings.terminalDirectory = "/Users/example/Projects/A rather long project name/Workspace/Development"
        model.settings.sources += (1...19).map {
            AppSource(id: UUID(), path: "/Volumes/External Drive/Applications/Extra app collection \($0)", enabled: true, custom: true)
        }
        model.apps = (1...19).map {
            AppItem(id: "\($0)", path: "/fixture/\($0).app", bundleID: nil,
                    name: $0 == 1 ? "An application with a very long display name" : "示例应用 \($0)",
                    customName: nil, hidden: true, addedAt: Date(), lastOpenedAt: nil, sourcePath: "/fixture")
        }
        model.runningApps = [RunningApp(id: "快捷工具"), RunningApp(id: "示例应用"), RunningApp(id: "菜单栏助手")]
        for count in [0, 1, 4, 5, 6, 10, 11, 100] {
            for size in [4, 5] {
                var covered: [Int] = []
                let first = SettingsPagination(count: count, pageSize: size, requestedPage: 0)
                for page in 0..<first.pageCount {
                    covered += SettingsPagination(count: count, pageSize: size, requestedPage: page).range
                }
                precondition(covered == Array(0..<count), "Pagination skipped or duplicated an item")
                let afterRemoval = SettingsPagination(count: max(0, count - 1), pageSize: size, requestedPage: 99)
                precondition(afterRemoval.range.upperBound <= max(0, count - 1), "Removal leaves an invalid last page")
            }
        }
        let pages: [(SettingsTab, AnyView)] = [
            (.general, AnyView(GeneralSettingsPage(model: model))),
            (.gestures, AnyView(GestureSettingsPage(model: model))),
            (.shortcuts, AnyView(ShortcutSettingsPage(model: model))),
            (.terminal, AnyView(TerminalSettingsPage(model: model))),
            (.appearance, AnyView(AppearanceSettingsPage(model: model))),
            (.layout, AnyView(LayoutSettingsPage(model: model, showReorganize: .constant(false)))),
            (.sources, AnyView(SourceSettingsPage(model: model))),
            (.hidden, AnyView(HiddenAppsSettingsPage(model: model))),
            (.about, AnyView(AboutSettingsPage()))
        ]
        for scheme in [ColorScheme.light, .dark] {
            app.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            let mode = scheme == .light ? "light" : "dark"
            for (tab, page) in pages {
                let natural = NSHostingView(rootView: page.fixedSize(horizontal: false, vertical: true).frame(width: 551))
                let height = natural.fittingSize.height
                print("\(mode) \(tab.rawValue) natural height: \(height)")
                precondition(height <= 424, "Settings page exceeds its content area: \(tab.rawValue) \(height)")
                let view = SettingsView(model: model, selectedTab: tab).environment(\.colorScheme, scheme)
                let host = NSHostingView(rootView: view)
                host.frame = NSRect(origin: .zero, size: SettingsView.windowSize)
                host.layoutSubtreeIfNeeded()
                precondition(!hasScrollView(host), "Settings introduced a scrolling container")
                try save(host, name: "\(mode)-\(tab.rawValue)")
            }
            // Busy synthetic backdrop: only our own fixture pixels are rendered.
            let tray = TrayView(model: model, onClose: {}, onLaunch: {})
                .frame(width: TrayView.contentWidth, height: TrayView.preferredHeight(menuCount: model.runningApps.count, pinnedCount: model.pinnedApps.count))
                .background {
                    Canvas { context, size in
                        for y in stride(from: 0, to: Int(size.height), by: 16) {
                            for x in stride(from: 0, to: Int(size.width), by: 16) {
                                context.fill(Path(CGRect(x: x, y: y, width: 16, height: 16)),
                                             with: .color((x + y).isMultiple(of: 32) ? .orange : .blue))
                            }
                        }
                    }
                }
                .environment(\.colorScheme, scheme)
            let trayHost = NSHostingView(rootView: tray)
            trayHost.frame = NSRect(x: 0, y: 0, width: TrayView.contentWidth,
                                    height: TrayView.preferredHeight(menuCount: model.runningApps.count, pinnedCount: model.pinnedApps.count))
            trayHost.layoutSubtreeIfNeeded()
            try save(trayHost, name: "\(mode)-tray")
        }
        model.apps = []
        let empty = NSHostingView(rootView: HiddenAppsSettingsPage(model: model).frame(width: 551))
        precondition(empty.fittingSize.height <= 424, "Empty hidden-app state overflows")
        print("PASS: nine settings pages in both appearances, no scroll containers, paginated lists and empty state")
    }
    @MainActor static func hasScrollView(_ view: NSView) -> Bool {
        view is NSScrollView || view.subviews.contains(where: hasScrollView)
    }
    @MainActor static func save(_ view: NSView, name: String) throws {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("No bitmap") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = bitmap.representation(using: .png, properties: [:])!
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name + ".png"))
    }
}
'''
with tempfile.TemporaryDirectory(prefix='pinchpad-settings-') as tmp:
    tmp = Path(tmp)
    # Expose initial tab only in the fixture build; production state stays private.
    settings = (root / 'Sources/SettingsView.swift').read_text().replace(
        '@State private var selectedTab:', '@State var selectedTab:')
    (tmp / 'SettingsView.swift').write_text(settings)
    (tmp / 'Probe.swift').write_text(harness)
    sources = ['Model', 'PinchClassifier', 'ClotheslinePreferences', 'ClotheslineLayout', 'CardKeyEditor', 'SettingsPagination', 'SettingsControls',
               'GestureSettingsView', 'PanelSettingsView', 'ApplicationSettingsView', 'TrayGridLayout', 'TrayView']
    binary = tmp / 'probe'
    subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library', '-module-cache-path',
                    '/tmp/pinchpad-probe-module-cache',
                    *[str(root / f'Sources/{name}.swift') for name in sources],
                    str(tmp / 'SettingsView.swift'), str(tmp / 'Probe.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(output), str(root / 'AppIcon.icns')], check=True)
