"""Exercise real library startup, scans, settings and merges in temporary folders.

Only display/input hooks and icon decoding are disabled in the compiled model.
The user's library, installed apps, and computer interface are never accessed.
Run: python3 Tests/AppLibrarySyncProbe.py
"""

from pathlib import Path
import subprocess
import tempfile


def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    cursor = opening + 1
    while depth:
        depth += (source[cursor] == "{") - (source[cursor] == "}")
        cursor += 1
    return source[start:cursor]


root = Path(__file__).resolve().parents[1]
model = (root / "Sources/AppModel.swift").read_text()
start = model.index("        let appSupport =", model.index("private init()"))
end = model.index("        if let data =", start)
model = model[:start] + "        fileURL = ProbeEnvironment.libraryURL\n" + model[end:]
for marker in (
    "private func prefetchIcons()",
    "private func wireMonitors()",
    "private func applyChrome()",
    "func refreshRunningApps()",
):
    method = block(model, marker)
    model = model.replace(method, method[:method.index("{") + 1] + "}")
model = model.replace("        if dragPanel == nil { dragPanel = makeDragPanel() }", "")

harness = r'''import AppKit
import Darwin
import Foundation

enum ProbeEnvironment {
    static let root: URL = {
        guard let path = realpath(CommandLine.arguments[1], nil) else { fatalError("Missing test directory") }
        defer { free(path) }
        return URL(fileURLWithPath: String(cString: path), isDirectory: true)
    }()
    static let libraryURL = root.appendingPathComponent("library.json")
}

@MainActor
final class AppDelegate {
    static var current: AppDelegate?
    var alertParentWindow: NSWindow? { nil }
    func refreshTray() {}
    func openTrayFromPinch() {}
    func dismissTray() {}
}

@main
struct AppLibrarySyncProbe {
    static let files = FileManager.default
    static var failures: [String] = []

    static func require(_ condition: Bool, _ message: String) {
        if !condition { failures.append(message) }
    }

    static func install(_ name: String, in source: URL) throws -> AppItem {
        let app = source.appendingPathComponent(name + ".app")
        let contents = app.appendingPathComponent("Contents")
        try files.createDirectory(at: contents, withIntermediateDirectories: true)
        let id = "app.pinchpad.sync-probe." + name
        let data = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": id,
            "CFBundleName": name,
            "CFBundlePackageType": "APPL"
        ], format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
        return AppItem(id: id, path: app.path, bundleID: id, name: name,
                       customName: nil, hidden: false, addedAt: Date(),
                       lastOpenedAt: nil, sourcePath: source.path)
    }

    @MainActor
    static func wait(_ timeout: TimeInterval = 2, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        } while Date() < deadline
        return condition()
    }

    @MainActor
    static func main() {
        do {
            let source = ProbeEnvironment.root.appendingPathComponent("Applications")
            try files.createDirectory(at: source, withIntermediateDirectories: true)
            let existing = try install("Existing", in: source)
            var retained = try install("Retained", in: source)
            retained.customName = "My app name"
            retained.addedAt = Date(timeIntervalSince1970: 1_000)
            retained.lastOpenedAt = Date(timeIntervalSince1970: 2_000)
            var hidden = try install("Hidden", in: source)
            hidden.hidden = true
            let offlineRemoved = try install("RemovedWhileClosed", in: source)
            let folder = FolderItem(id: UUID(), name: "My folder", appIDs: [existing.id], createdAt: Date())
            let page = Page(slots: [.folder(folder.id), .app(retained.id), .app(offlineRemoved.id)])
            var settings = Preferences()
            settings.sources = [AppSource(id: UUID(), path: source.path, enabled: true, custom: true)]
            let snapshot = LibrarySnapshot(settings: settings,
                                           apps: [existing, retained, hidden, offlineRemoved], folders: [folder],
                                           pages: [page], currentPage: 0,
                                           pinnedAppIDs: [existing.id, retained.id, offlineRemoved.id])
            try JSONEncoder().encode(snapshot).write(to: ProbeEnvironment.libraryURL)
            try files.removeItem(atPath: offlineRemoved.path)
            let offlineAdded = try install("InstalledWhileClosed", in: source)
            let model = AppModel.shared
            model.start()
            require(wait { !model.isScanning && model.app(offlineAdded.id) != nil && model.app(offlineRemoved.id) == nil },
                    "Startup reuses a stale nonempty library instead of reconciling offline changes")
            require(model.app(retained.id) == retained && model.app(hidden.id) == hidden,
                    "Startup loses custom names, hidden state, or saved dates")
            require(model.folders == [folder] && model.pages.first?.id == page.id,
                    "Startup resets existing folders or page identity")
            require(model.pages.first?.slots.prefix(2) == [.folder(folder.id), .app(retained.id)],
                    "Startup reorders existing apps and folders")

            let added = try install("NewlyInstalled", in: source)
            require(wait { model.app(added.id) != nil },
                    "A newly installed app never appears without a manual rescan")
            require(model.pages.flatMap(\.slots).contains(.app(added.id)),
                    "The newly installed app is missing from launcher pages")
            model.openFolderID = folder.id
            model.selection = [Slot.app(existing.id).id, Slot.folder(folder.id).id, Slot.app(retained.id).id]
            try files.removeItem(atPath: existing.path)
            require(wait { model.app(existing.id) == nil },
                    "An uninstalled app remains in the library without a manual rescan")
            require(!model.pages.flatMap(\.slots).contains(.app(existing.id)),
                    "The uninstalled app remains on a launcher page")
            require(model.folder(folder.id) == nil && model.openFolderID == nil
                    && !model.pages.flatMap(\.slots).contains(.folder(folder.id)),
                    "Uninstall leaves an empty or open stale folder behind")
            require(model.pinnedAppIDs == [retained.id] && model.selection == [Slot.app(retained.id).id],
                    "Uninstall leaves stale pinned apps or selections behind")
            require(model.app(retained.id) == retained && model.app(hidden.id) == hidden,
                    "Automatic refresh changes unrelated app preferences")

            let nested = try install("Nested", in: source.appendingPathComponent("Tools/Utilities"))
            require(wait { model.app(nested.id) != nil }, "An app installed in a nested folder never appears")

            let laterSource = ProbeEnvironment.root.appendingPathComponent("CreatedLater/Applications")
            model.settings.sources.append(AppSource(id: UUID(), path: laterSource.path, enabled: true, custom: true))
            require(wait { !model.isScanning }, "Adding a missing source never finishes scanning")
            let later = try install("Later", in: laterSource)
            require(wait { model.app(later.id) != nil }, "A source created after startup is never watched")
            try files.removeItem(at: laterSource)
            require(wait { model.app(later.id) == nil }, "Removing a whole source does not remove its apps")
            let returned = try install("Returned", in: laterSource)
            require(wait { model.app(returned.id) != nil }, "A deleted and recreated source is no longer watched")

            let customSource = ProbeEnvironment.root.appendingPathComponent("Custom")
            // Deliberately use the /var or /tmp alias while FSEvents reports /private/...
            let customSourcePath = customSource.path.hasPrefix("/private/")
                ? String(customSource.path.dropFirst("/private".count)) : customSource.path
            let custom = try install("CustomApp", in: customSource)
            model.settings.sources.append(AppSource(id: UUID(), path: customSourcePath, enabled: false, custom: true))
            require(wait { !model.isScanning }, "Adding a disabled source leaves a pending scan")
            require(model.app(custom.id) == nil, "A disabled source contributes apps")
            let customIndex = model.settings.sources.count - 1
            model.settings.sources[customIndex].enabled = true
            require(wait { model.app(custom.id) != nil }, "Enabling a source does not automatically scan it")

            let movedPath = customSource.appendingPathComponent("Moved.app").path
            try files.moveItem(atPath: retained.path, toPath: movedPath)
            require(wait { model.app(retained.id)?.path == movedPath }, "Moving an app leaves its saved path stale")
            var moved = retained
            moved.path = movedPath
            moved.sourcePath = customSourcePath
            require(model.app(retained.id) == moved && model.pinnedAppIDs == [retained.id],
                    "Moving an app loses its custom name, dates or pin")

            var publishedLibraries: [Set<String>] = []
            model.onContentReady = { publishedLibraries.append(Set(model.apps.map(\.id))) }
            model.rescan()
            model.rescan()
            model.settings.sources[customIndex].enabled = false
            require(wait { !model.isScanning && model.app(custom.id) == nil && model.app(retained.id) == nil },
                    "Changing sources during a scan lets stale results restore excluded apps")
            require(!publishedLibraries.isEmpty && publishedLibraries.allSatisfy {
                !$0.contains(custom.id) && !$0.contains(retained.id)
            }, "An obsolete scan publishes results after its source was disabled")
            let disabled = try install("DisabledInstall", in: customSource)
            _ = wait(1.3) { false }
            require(model.app(disabled.id) == nil, "Changes in a disabled source add unwanted apps")
            let idleRefreshes = publishedLibraries.count
            _ = wait(1.1) { false }
            require(publishedLibraries.count == idleRefreshes, "The idle catalog repeatedly scans without file changes")
            require(wait {
                guard let data = try? Data(contentsOf: ProbeEnvironment.libraryURL),
                      let saved = try? JSONDecoder().decode(LibrarySnapshot.self, from: data) else { return false }
                return saved.apps == model.apps && saved.folders == model.folders
                    && saved.pages == model.pages && saved.pinnedAppIDs == model.pinnedAppIDs
                    && saved.settings == model.settings
            }, "Automatic library and source updates are not persisted")
            if failures.isEmpty {
                print("PASS: installation and removal automatically update the catalog and launcher pages")
                print("PASS: startup reconciles offline changes while preserving names, hidden state, dates and layout")
                print("PASS: uninstall prunes pins, empty folders and stale selections")
                print("PASS: nested, missing and recreated sources are watched; app moves retain metadata")
                print("PASS: source toggles supersede in-flight scans; disabled sources and idle time cause no churn")
            } else {
                for failure in failures { print("FAIL: \(failure)") }
                exit(1)
            }
        } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
'''

with tempfile.TemporaryDirectory(prefix="pinchpad-library-sync-") as directory:
    directory = Path(directory)
    isolated_model = directory / "AppModel.swift"
    isolated_model.write_text(model)
    probe = directory / "AppLibrarySyncProbe.swift"
    probe.write_text(harness)
    binary = directory / "probe"
    sources = [root / "Sources" / name for name in (
        "Model.swift", "PinchClassifier.swift", "Services.swift", "PanelAlertPresenter.swift", "PagingMotion.swift",
        "IconEntrance.swift", "EntranceMotion.swift",
    )]
    sources += sorted((root / "Sources").glob("AppLibrary*.swift"))
    subprocess.run([
        "swiftc", "-swift-version", "5", "-module-cache-path", "/tmp/pinchpad-build-module-cache",
        *map(str, sources), str(isolated_model), str(probe), "-lsqlite3", "-o", str(binary),
    ], check=True)
    result = subprocess.run([str(binary), str(directory)], text=True, capture_output=True)
    print(result.stdout, end="")
    print(result.stderr, end="")
    raise SystemExit(result.returncode)
