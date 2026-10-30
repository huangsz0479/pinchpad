"""Render the production tray with synthetic apps, without opening a window.

Only our NSHostingView pixels are rendered. No desktop capture, AX access,
application discovery, input events, or persisted preferences are used.
The alpha check catches a shared backing sheet between independent controls.
These images verify layout, not native glass compositing over the real desktop.
Run: python3 Tests/TrayLayoutProbe.py
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
output = root / '.build/tray-review'
output.mkdir(parents=True, exist_ok=True)

source = r'''import AppKit
import SwiftUI

// System accessibility environment values are read-only. The isolated copy of
// TrayView reads these writable equivalents; production rendering branches are
// unchanged and no system preference is modified.
private struct FixtureTransparency: EnvironmentKey { static let defaultValue = false }
private struct FixtureContrast: EnvironmentKey { static let defaultValue = ColorSchemeContrast.standard }
extension EnvironmentValues {
    var fixtureReduceTransparency: Bool {
        get { self[FixtureTransparency.self] }
        set { self[FixtureTransparency.self] = newValue }
    }
    var fixtureContrast: ColorSchemeContrast {
        get { self[FixtureContrast.self] }
        set { self[FixtureContrast.self] = newValue }
    }
}

// This fixture never discovers installed applications or changes user data.
@MainActor final class AppModel: ObservableObject {
    @Published var settings = Preferences()
    @Published var apps: [AppItem] = []
    @Published var runningApps: [RunningApp] = []
    var pinCount = 7
    var pinnedApps: [AppItem] { Array(apps.prefix(pinCount)) }
    func icon(for app: AppItem) -> NSImage { fixtureIcon(Int(app.id) ?? 0) }
    func isRunning(_ app: AppItem) -> Bool { app.id == "1" }
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
    var icon: NSImage? { fixtureIcon(id.count) }
    var bundleID: String? { "fixture.\(id)" }
    var path: String { "/fixture/\(id).app" }
    var isFrontmost: Bool { false }
    func open() {}
    func activate() {}
    func terminate() {}
    func pressMenuBarItem() -> Bool { false }
}
enum SettingsOpener { static func open() {} }

func fixtureIcon(_ index: Int) -> NSImage {
    let colors: [NSColor] = [.systemBlue, .systemYellow, .systemRed, .systemPink,
                             .systemPurple, .darkGray, .systemGreen, .systemGray]
    let symbols = ["S", "N", "31", "♪", "P", ">_", "••", "⚙"]
    let i = abs(index) % colors.count
    return NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
        let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 14, yRadius: 14)
        NSGradient(starting: colors[i].blended(withFraction: 0.22, of: .white)!,
                   ending: colors[i])!.draw(in: shape, angle: -90)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 27, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let text = symbols[i] as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (64 - size.width) / 2, y: (64 - size.height) / 2),
                  withAttributes: attributes)
        return true
    }
}

@main struct TrayLayoutProbe {
    @MainActor static func main() throws {
        let application = NSApplication.shared
        let catalog = (1...100).map {
            AppItem(id: "\($0)", path: "/fixture/\($0).app", bundleID: nil,
                    name: ["Safari", "备忘录", "日历", "音乐", "照片", "终端", "信息", "系统设置",
                           "An application with a very long name"][($0 - 1) % 9],
                    customName: nil, hidden: false, addedAt: Date(), lastOpenedAt: nil, sourcePath: "/fixture")
        }
        let normal = AppModel()
        normal.apps = Array(catalog.prefix(32))
        normal.runningApps = [RunningApp(id: "快捷工具"), RunningApp(id: "云盘"), RunningApp(id: "菜单栏助手")]
        let mixed = AppModel()
        mixed.apps = normal.apps
        mixed.runningApps = normal.runningApps
        for (index, item) in mixed.pinnedApps.enumerated() {
            mixed.setTraySize([TrayAppSize.small, .medium, .large][index % 3], for: item)
        }
        for (index, item) in mixed.runningApps.enumerated() {
            mixed.setTraySize([TrayAppSize.large, .small, .medium][index % 3], for: item)
        }
        let empty = AppModel()
        let long = AppModel()
        long.apps = catalog
        long.pinCount = 100
        long.runningApps = (1...100).map { RunningApp(id: "菜单栏应用 \($0)") }
        let usualHeight = TrayView.preferredHeight(menuCount: 3, pinnedCount: 7)

        // Render the same production view without any backdrop. Accessibility
        // disables glass diffusion, so a shared sheet cannot hide behind a
        // compositor limitation: alpha between the controls must stay clear.
        for scheme in [ColorScheme.light, .dark] {
            application.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            let mode = scheme == .light ? "light" : "dark"
            try assertSizeLabels(scheme: scheme, mode: mode)
            let alphaView = TrayView(model: normal, onClose: {}, onLaunch: {})
                .environment(\.colorScheme, scheme)
                .environment(\.fixtureReduceTransparency, true)
                .frame(width: TrayView.contentWidth, height: usualHeight)
            let bitmap = try render(alphaView, height: usualHeight, name: "\(mode)-reduced-transparency")
            try assertIndependentSurfaces(bitmap, size: NSSize(width: TrayView.contentWidth, height: usualHeight))

            for (name, model, adding) in [("organizer", normal, false), ("mixed", mixed, false), ("add", normal, true),
                                           ("empty", empty, false), ("long-list", long, false)] {
                let height = max(adding ? 420 : 0, TrayView.preferredHeight(
                    menuSizes: model.runningApps.map { model.traySize(for: $0) },
                    pinnedSizes: model.pinnedApps.map { model.traySize(for: $0) }))
                let tray = TrayView(model: model, onClose: {}, onLaunch: {}, adding: adding)
                    .environment(\.colorScheme, scheme)
                    .frame(width: TrayView.contentWidth, height: height)
                _ = try render(tray, height: height, name: "\(mode)-\(name)")
                _ = try render(tray.environment(\.fixtureReduceTransparency, true),
                               height: height, name: "\(mode)-\(name)-reduced-transparency")
            }
            let accessible = TrayView(model: normal, onClose: {}, onLaunch: {})
                .environment(\.colorScheme, scheme)
                .environment(\.fixtureContrast, .increased)
                .frame(width: TrayView.contentWidth, height: usualHeight)
            _ = try render(accessible, height: usualHeight, name: "\(mode)-increased-contrast")
        }

        let smallHeight = TrayView.preferredHeight(menuSizes: [], pinnedSizes: Array(repeating: .small, count: 4))
        let mediumHeight = TrayView.preferredHeight(menuSizes: [], pinnedSizes: Array(repeating: .medium, count: 4))
        let largeHeight = TrayView.preferredHeight(menuSizes: [], pinnedSizes: Array(repeating: .large, count: 4))
        precondition(smallHeight < mediumHeight && mediumHeight < largeHeight,
                     "Panel height does not follow the actual per-app sizes")
        print("PASS: small controls hide names; medium and large visibly display them; mixed sizes update panel height")
        precondition(TrayView.contentWidth <= 400, "Organizer is no longer compact")
        precondition(usualHeight >= 400 && usualHeight <= 600, "Normal tray has an invalid height")
        precondition(TrayView.preferredHeight(menuCount: 0, pinnedCount: 0) <= 240,
                     "Empty tray leaves excessive empty space")
        precondition(TrayView.preferredHeight(menuCount: 100, pinnedCount: 100) <= 600,
                     "Long app lists no longer have a bounded scroll region")
        print("PASS: independent control surfaces retain transparent outer edges and inter-control gaps")
        print("PASS: light/dark, mixed-size, add/search, empty, long-list, reduced-transparency and increased-contrast layouts render")
        print("PASS: bounded heights: empty \(TrayView.preferredHeight(menuCount: 0, pinnedCount: 0)) / normal \(usualHeight) / maximum 600 pt")
        print("NOTE: offline rendering validates layout; real-desktop glass compositing is not exercised")
    }

    @MainActor static func render<V: View>(_ view: V, width requestedWidth: CGFloat? = nil, height: CGFloat, name: String) throws -> NSBitmapImageRep {
        let width = requestedWidth ?? TrayView.contentWidth
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        precondition(host.fittingSize.width <= width + 1, "Tray overflows its width: \(name)")
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No bitmap") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = bitmap.representation(using: .png, properties: [:])!
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("\(name).png"))
        return bitmap
    }

    @MainActor static func assertSizeLabels(scheme: ColorScheme, mode: String) throws {
        for size in TrayAppSize.allCases {
            let frame = TrayGridMetrics(sizes: [size], width: TrayView.contentWidth - 24).frames[0]
            func cell(_ name: String) -> some View {
                CellChrome(icon: fixtureIcon(3), name: name, size: size, action: {}) { EmptyView() }
                    .frame(width: frame.width, height: frame.height)
                    .environment(\.colorScheme, scheme)
                    .environment(\.fixtureReduceTransparency, true)
            }
            let a = try render(cell("Alpha"), width: frame.width, height: frame.height, name: "\(mode)-cell-\(size.rawValue)")
            let b = try render(cell("Wide application name"), width: frame.width, height: frame.height, name: "\(mode)-cell-\(size.rawValue)-renamed")
            var different = 0
            precondition(a.pixelsWide == b.pixelsWide && a.pixelsHigh == b.pixelsHigh)
            for y in 0..<a.pixelsHigh {
                for x in 0..<a.pixelsWide {
                    let p = a.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                    let q = b.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                    if abs(p.redComponent - q.redComponent) + abs(p.greenComponent - q.greenComponent)
                        + abs(p.blueComponent - q.blueComponent) + abs(p.alphaComponent - q.alphaComponent) > 0.02 {
                        different += 1
                    }
                }
            }
            if size == .small {
                precondition(different == 0, "Small size still visibly displays its app name: \(different) pixels change")
            } else {
                precondition(different > 20, "\(size.rawValue) size lost its visible app name")
            }
        }
    }

    static func assertIndependentSurfaces(_ bitmap: NSBitmapImageRep, size: NSSize) throws {
        let sx = CGFloat(bitmap.pixelsWide) / size.width
        let sy = CGFloat(bitmap.pixelsHigh) / size.height
        func alpha(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
            bitmap.colorAt(x: min(bitmap.pixelsWide - 1, Int(x * sx)),
                           y: min(bitmap.pixelsHigh - 1, Int(y * sy)))!.alphaComponent
        }
        // Shadows may softly reach the outer margin, but the old enclosing
        // panel was opaque at all these positions. It must remain substantially
        // transparent so the desktop still separates independent controls.
        for y in stride(from: CGFloat(2), to: size.height - 2, by: 8) {
            guard alpha(2, y) < 0.15, alpha(size.width - 3, y) < 0.15 else {
                fail("A shared surface still fills the outer tray margins at y=\(y)")
            }
        }
        // Find actual rows with surfaces on both sides, rather than coupling the
        // test to section-heading height. A meaningful clear run must separate
        // two opaque capsules, allowing their soft shadows; an empty render cannot pass.
        var bestRun = 0
        var run = 0
        for y in 0..<Int(size.height) {
            let row = CGFloat(y)
            if alpha(size.width * 0.25, row) > 0.95,
               alpha(size.width * 0.75, row) > 0.95,
               alpha(size.width / 2, row) < 0.3 {
                run += 1
                bestRun = max(bestRun, run)
            } else {
                run = 0
            }
        }
        guard bestRun >= 24 else {
            fail("No clear gap between two opaque app controls (best run: \(bestRun) pt)")
        }
    }

    static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
'''
with tempfile.TemporaryDirectory(prefix='pinchpad-tray-layout-') as tmp:
    tmp = Path(tmp)
    view = (root / 'Sources/TrayView.swift').read_text().replace('@State private var adding', '@State var adding')
    view = view.replace(r'\.accessibilityReduceTransparency', r'\.fixtureReduceTransparency')
    view = view.replace(r'\.colorSchemeContrast', r'\.fixtureContrast')
    view = view.replace('private struct CellChrome', 'struct CellChrome')
    (tmp / 'TrayView.swift').write_text(view)
    (tmp / 'Probe.swift').write_text(source)
    binary = tmp / 'probe'
    subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library', '-module-cache-path',
                    '/tmp/pinchpad-probe-module-cache', str(root / 'Sources/Model.swift'), str(root / 'Sources/ClotheslinePreferences.swift'),
                    str(root / 'Sources/PinchClassifier.swift'), str(root / 'Sources/TrayGridLayout.swift'),
                    str(root / 'Sources/ClotheslineLayout.swift'),
                    str(tmp / 'TrayView.swift'),
                    str(tmp / 'Probe.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(output)], check=True, timeout=30)
