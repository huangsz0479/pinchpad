"""Exercise tray sizing through production preferences and AppModel methods.

Uses only in-memory app metadata and a temporary encoded snapshot. No app launch,
window, device hook, accessibility query, or user preference is accessed.
Run: python3 Tests/TraySizePersistenceProbe.py
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


model = (root / 'Sources/AppModel.swift').read_text()
methods = '\n'.join(block(model, marker) for marker in (
    'func traySize(for app: AppItem)', 'func traySize(for app: RunningApp)',
    'func setTraySize(_ size: TrayAppSize, for app: AppItem)',
    'func setTraySize(_ size: TrayAppSize, for app: RunningApp)',
))
source = r'''import Foundation

struct ProcessMetadata {
    var bundleURL: URL?
    var processIdentifier: Int
}
struct RunningApp {
    var bundleID: String?
    var application: ProcessMetadata
}
final class AppModel {
    var saves = 0
    var settings = Preferences() {
        didSet { if settings != oldValue { saves += 1 } }
    }
''' + methods + r'''
}

@main struct Probe {
    static func main() throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let legacy = try decoder.decode(Preferences.self, from: Data(#"{"columns":9,"pinchThree":false}"#.utf8))
        precondition(legacy.columns == 9 && !legacy.pinchThree && legacy.trayAppSizes.isEmpty)
        precondition(legacy.traySize(bundleID: "example.legacy", path: nil) == .medium)

        let future = try decoder.decode(Preferences.self, from: Data(#"{"columns":8,"trayAppSizes":{"bundle:small":"small","bundle:future":"huge","bundle:bad":42,"bundle:object":{"x":1},"bundle:large":"large"}}"#.utf8))
        precondition(future.columns == 8)
        precondition(future.traySize(bundleID: "small", path: nil) == .small)
        precondition(future.traySize(bundleID: "large", path: nil) == .large)
        for key in ["future", "bad", "object"] {
            precondition(future.traySize(bundleID: key, path: nil) == .medium)
        }
        let malformedMap = try decoder.decode(Preferences.self, from: Data(#"{"rows":6,"trayAppSizes":[1,2]}"#.utf8))
        precondition(malformedMap.rows == 6 && malformedMap.trayAppSizes.isEmpty)

        let catalog = AppItem(id: "catalog-id", path: "/Applications/Example.app", bundleID: "example.app",
            name: "Example", customName: nil, hidden: false, addedAt: Date(timeIntervalSince1970: 0),
            lastOpenedAt: nil, sourcePath: "/Applications")
        let running = RunningApp(bundleID: "example.app", application: ProcessMetadata(
            bundleURL: URL(fileURLWithPath: "/Applications/Example.app"), processIdentifier: 41))
        let restarted = RunningApp(bundleID: "example.app", application: ProcessMetadata(
            bundleURL: URL(fileURLWithPath: "/Volumes/Other/Example.app"), processIdentifier: 999))
        let model = AppModel()
        precondition(model.traySize(for: catalog) == .medium && model.traySize(for: running) == .medium)
        model.setTraySize(.small, for: running)
        precondition(model.traySize(for: catalog) == .small && model.traySize(for: restarted) == .small)
        precondition(model.saves == 1, "Resize did not reach settings persistence")
        model.setTraySize(.small, for: catalog)
        precondition(model.saves == 1, "Choosing the current size should not save again")
        model.setTraySize(.large, for: catalog)
        precondition(model.traySize(for: running) == .large)
        precondition(model.saves == 2)

        var other = catalog
        other.id = "another-catalog-id"
        other.bundleID = "example.other"
        other.path = "/Applications/Other.app"
        model.setTraySize(.small, for: other)
        precondition(model.traySize(for: catalog) == .large && model.traySize(for: other) == .small)

        // Save and reload the same production snapshot type used by persist().
        let snapshot = LibrarySnapshot(settings: model.settings, apps: [catalog, other], folders: [],
            pages: [], currentPage: 0, pinnedAppIDs: [catalog.id])
        let file = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("library.json")
        try encoder.encode(snapshot).write(to: file, options: .atomic)
        let restored = try decoder.decode(LibrarySnapshot.self, from: Data(contentsOf: file))
        let reloaded = AppModel()
        reloaded.settings = restored.settings
        precondition(reloaded.traySize(for: restarted) == .large && reloaded.traySize(for: other) == .small)
        precondition(restored.apps == [catalog, other] && restored.pinnedAppIDs == [catalog.id])
        let json = String(data: try encoder.encode(restored.settings), encoding: .utf8)!
        precondition(json.contains("bundle:example.app") && json.contains("large"))
        precondition(!json.contains("999"), "Process identifier leaked into persisted identity")

        var noBundle = catalog
        noBundle.id = "path-only"
        noBundle.bundleID = nil
        noBundle.path = "/Applications/Tools/../PathOnly.app"
        let pathRunning = RunningApp(bundleID: nil, application: ProcessMetadata(
            bundleURL: URL(fileURLWithPath: "/Applications/PathOnly.app"), processIdentifier: 18))
        model.setTraySize(.small, for: noBundle)
        precondition(model.traySize(for: pathRunning) == .small)
        model.setTraySize(.large, for: pathRunning)
        precondition(model.traySize(for: noBundle) == .large)
        model.setTraySize(.medium, for: noBundle)
        precondition(model.traySize(for: pathRunning) == .medium)
        precondition(model.settings.trayAppSizes["path:/Applications/PathOnly.app"] == nil)
        let identityless = RunningApp(bundleID: nil, application: ProcessMetadata(bundleURL: nil, processIdentifier: 5))
        let before = model.settings
        model.setTraySize(.large, for: identityless)
        precondition(model.settings == before && model.traySize(for: identityless) == .medium)

        precondition(TrayAppSize.allCases.map(\.columns) == [1, 2, 2])
        precondition(TrayAppSize.allCases.map(\.rows) == [1, 1, 2])
        print("PASS: legacy preferences, unknown and malformed sizes retain the library and default to medium")
        print("PASS: independent app sizes persist through a production snapshot save/reload")
        print("PASS: catalog/menu-bar sizes share stable bundle or path identity across process restarts")
        print("PASS: resize methods reach settings persistence; repeated choices and default reset remain stable")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='pinchpad-tray-size-') as temp:
    temp = Path(temp)
    (temp / 'Probe.swift').write_text(source)
    binary = temp / 'probe'
    subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library', '-module-cache-path',
                    '/tmp/pinchpad-probe-module-cache', str(root / 'Sources/Model.swift'), str(root / 'Sources/ClotheslinePreferences.swift'),
                    str(root / 'Sources/PinchClassifier.swift'), str(temp / 'Probe.swift'),
                    '-o', str(binary)], check=True, timeout=60)
    subprocess.run([str(binary), str(temp)], check=True, timeout=15)
