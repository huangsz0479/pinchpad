"""Replay real reorder previews in a hidden, isolated SwiftUI hosting fixture.

Never reads the user library, opens a visible window, posts input, or starts monitors.
Tracks mounted cell identity and CPU update cost, rather than display frame rate.
Run: python3 Tests/DragPerformanceProbe.py
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
view = (root / 'Sources/PinchpadView.swift').read_text()
start = model.index('        let appSupport =', model.index('private init()'))
end = model.index('        if let data =', start)
model = model[:start] + '        fileURL = ProbeEnvironment.libraryURL\n' + model[end:]
for marker in ('private func prefetchIcons()', 'private func wireMonitors()',
               'private func updateAppSources()', 'private func applyChrome()',
               'func refreshRunningApps()', 'private func persist()'):
    method = block(model, marker)
    model = model.replace(method, method[:method.index('{') + 1] + '}')
method = block(model, 'func icon(for app: AppItem)')
model = model.replace(method, method[:method.index('{') + 1] + ' return ProbeEnvironment.icon }')
model = model.replace('    private func previewGap(', '    func previewGap(')
model = model.replace('func previewGap(_ id: String, at destination: Int) {', 'func previewGap(_ id: String, at destination: Int) {\n        ProbeCounters.previews += 1')
model = model.replace('private func iconUnderPointer(_ point: CGPoint) -> String? {', 'private func iconUnderPointer(_ point: CGPoint) -> String? {\n        ProbeCounters.hitTests += 1')
model = model.replace('    private var orderAtDragStart:', '    var orderAtDragStart:')
model = model.replace('    private var slotFrames:', '    var slotFrames:')
model = model.replace('    private var dragDirty', '    var dragDirty')
model = model.replace('    private func updateDrag(', '    func updateDrag(')
model = model.replace('    private func nudgeDragEdge(', '    func nudgeDragEdge(')
model = model.replace('    private var edgeArmed:', '    var edgeArmed:')
model = model.replace('    private var lastEdgeTurn', '    var lastEdgeTurn')
# Retain real drag state setup, omit only native image/timer/event boundaries.
method = block(model, 'func beginDrag(')
model = model.replace(method, method[:method.index('        showDragImage(')] + '    }')

view = view.replace('.opacity(dragging ? 0.28 : 1)', '.opacity(dragging ? 0.28 : 1)\n        .onAppear { ProbeCounters.mounts += 1 }')
view = view.replace('buckets[ring].append((index, slot))', 'ProbeCounters.ringMaps[slot.id] = ring\n                buckets[ring].append((index, slot))')
harness = r'''import AppKit
import Combine
import SwiftUI

enum ProbeEnvironment {
    static var libraryURL: URL { URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("library.json") }
    static let icon = NSImage(size: NSSize(width: 128, height: 128))
}
@MainActor enum ProbeCounters {
    static var mounts = 0
    static var previews = 0
    static var hitTests = 0
    static var ringMaps: [String: Int] = [:]
}
@MainActor final class AppDelegate {
    static var current: AppDelegate?
    var alertParentWindow: NSWindow? { nil }
    func refreshTray() {}
    func openClotheslineFromPinch() {}
    func dismissCompanionPanels() {}
    func dismissTray() {}
}
@main struct DragPerformanceProbe {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        var settings = Preferences()
        settings.sources = []
        settings.columns = 8
        settings.rows = 5
        settings.sortBy = .custom
        let apps = (0..<120).map {
            AppItem(id: "test.\($0)", path: "/fixture/App\($0).app", bundleID: "test.\($0)",
                    name: "App \($0)", hidden: false, addedAt: Date(timeIntervalSince1970: 0), sourcePath: "/fixture")
        }
        let pages = stride(from: 0, to: apps.count, by: settings.pageCapacity).map { start in
            Page(slots: apps[start..<min(start + settings.pageCapacity, apps.count)].map { .app($0.id) })
        }
        let snapshot = LibrarySnapshot(settings: settings, apps: apps, folders: [], pages: pages, currentPage: 1)
        try JSONEncoder().encode(snapshot).write(to: ProbeEnvironment.libraryURL)
        let model = AppModel.shared
        model.isOpen = true
        let host = NSHostingView(rootView: PinchpadRoot(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 1600, height: 1000)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.isReleasedWhenClosed = false
        defer { window.close() }
        func update() {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
            host.layoutSubtreeIfNeeded()
        }
        func flush() { for _ in 0..<8 { update() } }
        flush()
        let source = model.pages[1].slots[0].id
        model.beginDrag(source)
        flush()
        ProbeCounters.mounts = 0
        var times: [Double] = []
        for destination in Array(41...79) + Array((41...79).reversed()) {
            let begin = ProcessInfo.processInfo.systemUptime
            model.previewGap(source, at: destination)
            update()
            times.append((ProcessInfo.processInfo.systemUptime - begin) * 1000)
        }
        flush()
        times.sort()
        let remounts = ProbeCounters.mounts
        print("78 in-page reorder previews: \(remounts) remounted icon cells")
        print(String(format: "preview + layout CPU wall time: median %.3f ms; p95 %.3f ms", times[times.count / 2], times[Int(Double(times.count) * 0.95)]))
        // Merely passing over another icon must not undo an established gap preview.
        model.previewGap(source, at: 47)
        flush()
        let preview = model.pages
        let target = model.pages[1].slots.first { $0.id != source }!
        let frame = model.slotFrames[target.id]!
        model.updateDrag(at: CGPoint(x: frame.midX, y: frame.midY), width: host.frame.width, now: Date(timeIntervalSince1970: 1))
        let reverted = model.pages != preview
        print("passing over an icon immediately reverts the preview: \(reverted)")
        var failures: [String] = []
        if remounts > 0 { failures.append("Reordering changes cell identity and restarts icon rendering") }
        if reverted { failures.append("Pointer crossing an icon snaps the entire layout back") }
        let targetPoint = CGPoint(x: frame.midX, y: frame.midY)
        model.updateDrag(at: targetPoint, width: host.frame.width, now: Date(timeIntervalSince1970: 1.2))
        if model.folderHoverID != nil { failures.append("A passing pointer arms folder creation too soon") }
        model.updateDrag(at: targetPoint, width: host.frame.width, now: Date(timeIntervalSince1970: 1.31))
        if model.folderHoverID != target.id { failures.append("Deliberate icon dwell does not arm folder creation") }
        if model.pages != preview { failures.append("Folder dwell resets the existing preview") }
        model.endDrag()
        let created = model.folders.first!
        if Set(created.appIDs) != Set(["test.40", "test.41"]) {
            failures.append("Dropping after dwell does not create the intended folder")
        }
        flush()
        // A second app can still be moved into that folder via the same dwell path.
        model.beginDrag("a:test.42")
        flush()
        let folderFrame = model.slotFrames[Slot.folder(created.id).id]!
        let folderPoint = CGPoint(x: folderFrame.midX, y: folderFrame.minY + folderFrame.width / 2)
        for time in [2.0, 2.31] {
            model.updateDrag(at: folderPoint, width: host.frame.width, now: Date(timeIntervalSince1970: time))
        }
        model.endDrag()
        if Set(model.folders.first!.appIDs) != Set(["test.40", "test.41", "test.42"]) {
            failures.append("Dropping after dwell does not add an app to an existing folder")
        }
        let allAfterFolder = model.pages.flatMap(\.slots).compactMap { slot -> String? in
            if case .app(let id) = slot { return id }; return nil
        } + model.folders.flatMap(\.appIDs)
        if allAfterFolder.count != apps.count || Set(allAfterFolder) != Set(apps.map(\.id)) {
            failures.append("Folder operations lost or duplicated an app")
        }
        model.beginDrag("a:test.43")
        model.folderHoverID = Slot.folder(created.id).id
        model.updateDrag(at: CGPoint(x: 0, y: 300), width: host.frame.width, now: Date())
        if model.folderHoverID != nil { failures.append("Moving to a page edge retains a stale folder drop target") }
        model.endDrag()
        print("folder dwell: create and add-to-folder paths preserve all apps; page edges clear old targets")

        model.folders = []
        model.pages = pages
        model.currentPage = 1
        flush()
        model.beginDrag(source)
        flush()
        let left = model.slotFrames["a:test.45"]!
        let right = model.slotFrames["a:test.46"]!
        let gap = CGPoint(x: (left.maxX + right.minX) / 2, y: left.midY)
        ProbeCounters.previews = 0
        model.updateDrag(at: gap, width: host.frame.width, now: Date(timeIntervalSince1970: 3))
        model.updateDrag(at: gap, width: host.frame.width, now: Date(timeIntervalSince1970: 3.046))
        flush()
        let heldPreview = model.pages
        if ProbeCounters.previews != 1 || heldPreview == pages || heldPreview[1].slots[5].id != source {
            failures.append("A real 46ms gap dwell did not move the source into the intended slot")
        }
        ProbeCounters.hitTests = 0
        model.updateDrag(at: gap, width: host.frame.width, now: Date(timeIntervalSince1970: 4))
        model.updateDrag(at: CGPoint(x: gap.x + 5.9, y: gap.y), width: host.frame.width,
                         now: Date(timeIntervalSince1970: 4.1))
        if model.pages != heldPreview || model.folderHoverID != nil || ProbeCounters.previews != 1
            || ProbeCounters.hitTests != 0 {
            failures.append("Stationary pointer or sub-6pt jitter retargets an established gap preview")
        }
        model.updateDrag(at: CGPoint(x: gap.x + 6, y: gap.y), width: host.frame.width,
                         now: Date(timeIntervalSince1970: 4.2))
        if ProbeCounters.hitTests != 1 {
            failures.append("Moving exactly 6pt does not release the stationary-preview lock")
        }
        let nextLeft = model.slotFrames["a:test.46"]!
        let nextRight = model.slotFrames["a:test.47"]!
        let nextGap = CGPoint(x: (nextLeft.maxX + nextRight.minX) / 2, y: nextLeft.midY)
        model.updateDrag(at: nextGap, width: host.frame.width, now: Date(timeIntervalSince1970: 5))
        model.updateDrag(at: nextGap, width: host.frame.width, now: Date(timeIntervalSince1970: 5.046))
        flush()
        if ProbeCounters.previews != 2 || model.pages == heldPreview || model.pages[1].slots[6].id != source {
            failures.append("A released pointer cannot continue to the next gap preview")
        }
        print("gap trajectory: 46ms dwell, stationary/jitter hold, 6pt unlock and next preview all pass")
        var pageWrites = 0
        let subscription = model.$pages.dropFirst().sink { _ in pageWrites += 1 }
        model.previewGap(source, at: 119)
        if pageWrites != 1 { failures.append("A multi-page preview publishes \(pageWrites) separate layout changes") }
        let allAfterPreview = model.pages.flatMap(\.slots)
        if allAfterPreview.count != apps.count || Set(allAfterPreview.map(\.id)).count != apps.count {
            failures.append("Cross-page preview loses or duplicates an app")
        }
        withExtendedLifetime(subscription) {}
        model.endDrag()
        model.pages = pages
        model.currentPage = 1
        flush()
        model.beginDrag(source)
        model.edgeArmed = Date(timeIntervalSinceNow: -1)
        model.lastEdgeTurn = .distantPast
        model.nudgeDragEdge(1)
        flush()
        if model.clampedPage != 2 { failures.append("Edge drag does not turn to the next page") }
        model.previewGap(source, at: 87)
        flush()
        if !model.pages[2].slots.contains(where: { $0.id == source }) {
            failures.append("A gap preview after an edge turn pulls the app back to the old page")
        }
        model.edgeArmed = Date(timeIntervalSinceNow: -1)
        model.lastEdgeTurn = .distantPast
        model.nudgeDragEdge(-1)
        model.endDrag()
        flush()
        let afterEdges = model.pages.flatMap(\.slots)
        if model.clampedPage != 1 || afterEdges.count != apps.count || Set(afterEdges.map(\.id)).count != apps.count {
            failures.append("Repeated edge turns lose/duplicate an app or leave the wrong page")
        }
        print("cross-page previews: one publication, no lost/duplicate apps, continuous edge-turn baseline")

        // Next hidden reset restores geometric ring assignment without remounting
        // icons during the drag itself.
        model.prepareEntrance()
        flush()
        for page in model.pages {
            let rows = max(Int(ceil(Double(page.slots.count) / Double(settings.columns))), 1)
            for (index, slot) in page.slots.enumerated() {
                if ProbeCounters.ringMaps[slot.id] != IconEntrance.ring(for: index, columns: settings.columns, rows: rows) {
                    failures.append("Next entrance no longer groups icons by spatial ring")
                    break
                }
            }
        }
        print("next entrance: four spatial rings restored after reordering")
        precondition(!window.isVisible)
        if !failures.isEmpty {
            for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
            exit(1)
        }
        print("PASS: reorder preserves mounted cells and stable previews")
        print("NOTE: offscreen CPU fixture; excludes visible composition and is not an FPS measurement")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='pinchpad-drag-performance-') as directory:
    directory = Path(directory)
    (directory / 'AppModel.swift').write_text(model)
    (directory / 'PinchpadView.swift').write_text(view)
    (directory / 'Probe.swift').write_text(harness)
    sources = ['Model.swift', 'ClotheslinePreferences.swift', 'PinchClassifier.swift', 'Services.swift', 'PanelAlertPresenter.swift',
               'IconEntrance.swift', 'AppLibraryMonitor.swift', 'PagingMotion.swift', 'EntranceMotion.swift']
    for source in sources:
        (directory / source).write_text((root / 'Sources' / source).read_text())
    binary = directory / 'probe'
    subprocess.run(['swiftc', '-swift-version', '5', '-O', '-module-cache-path', '/tmp/pinchpad-drag-module-cache',
                    *[str(directory / source) for source in sources], str(directory / 'AppModel.swift'),
                    str(directory / 'PinchpadView.swift'), str(directory / 'Probe.swift'), '-lsqlite3', '-o', str(binary)],
                   check=True, timeout=180)
    result = subprocess.run([str(binary), str(directory)], timeout=30)
    raise SystemExit(result.returncode)
