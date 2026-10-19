"""Measure paging CPU work in a hidden, isolated SwiftUI hosting fixture.

The temporary instrumented build uses the real view/model and scroll handlers.
It never makes a window visible, posts system input, reads the user's library, or starts
device monitors. Results describe CPU updates and invalidations, not screen FPS.
Run: python3 Tests/PagingPerformanceProbe.py
"""

from pathlib import Path
import argparse
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


def instrument_body(source, declaration, counter):
    start = source.index(declaration)
    opening = source.index("var body: some View {", start)
    insertion = opening + len("var body: some View {")
    return source[:insertion] + f"\n        let _ = ProbeCounters.record(\"{counter}\")" + source[insertion:]


root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--apps", type=int, default=116)
parser.add_argument("--columns", type=int, default=8)
parser.add_argument("--rows", type=int, default=5)
parser.add_argument("--check", action="store_true", help="Fail if continuous swipe invalidates unrelated root UI")
parser.add_argument("--large-fixture", action="store_true", help="Also run a 600-app fixture using the same compiled binary")
arguments = parser.parse_args()
model = (root / "Sources/AppModel.swift").read_text()
view = (root / "Sources/PinchpadView.swift").read_text()
app = (root / "Sources/AppMain.swift").read_text()
start = model.index("        let appSupport =", model.index("private init()"))
end = model.index("        if let data =", start)
model = model[:start] + "        fileURL = ProbeEnvironment.libraryURL\n" + model[end:]
for marker in (
    "private func prefetchIcons()",
    "private func wireMonitors()",
    "private func updateAppSources()",
    "private func applyChrome()",
    "func refreshRunningApps()",
    "private func persist()",
):
    method = block(model, marker)
    model = model.replace(method, method[:method.index("{") + 1] + "}")
method = block(model, "func icon(for app: AppItem)")
model = model.replace(method, method[:method.index("{") + 1] + " return ProbeEnvironment.icon }")
method = block(model, "func noteSlotFrames(_ frames: [String: CGRect])")
model = model.replace(method, method.replace("slotFrames = frames", "slotFrames = frames\n        ProbeCounters.acceptedFrames(frames)"))

for declaration, counter in (
    ("struct PinchpadRoot:", "rootBody"),
    ("private struct JellyPages:", "pagerBody"),
    ("private struct IconGrid:", "gridBody"),
    ("private struct SlotCell:", "cellBody"),
):
    view = instrument_body(view, declaration, counter)
for marker, counter in (
    ("@MainActor init(_ model: AppModel, slots: [Slot], isActivePage: Bool = true, tracksSlotFrames: Bool = true) {", "gridState"),
    ("init(slot: Slot, model: AppModel, iconSide: CGFloat, plate: CGFloat) {", "cellInit"),
    ("private func targetFrames(origin: CGPoint, columnCount: Int, strideX: CGFloat, strideY: CGFloat) -> [String: CGRect] {", "frames"),
):
    record = 'ProbeCounters.recordGridState(slots)' if counter == "gridState" else f'ProbeCounters.record("{counter}")'
    view = view.replace(marker, marker + f'\n        {record}')
offset_line = next(line for line in view.splitlines() if ".offset(x: -CGFloat(page) * width +" in line)
offset_expression = offset_line.strip()[len(".offset(x: "):-1]
view = view.replace(offset_line, offset_line.replace(offset_expression, f"ProbeCounters.presentedOffset({offset_expression})"))

handlers = "\n".join(block(app, marker).replace("NSEvent", "ScrollEvent") for marker in (
    "private func handlePageSwipe(_ event: NSEvent)", "private func settleSwipe()",
))

harness = r'''import AppKit
import Combine
import Foundation
import SwiftUI

enum ProbeEnvironment {
    static let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    static var libraryURL: URL { root.appendingPathComponent("library.json") }
    static let icon = NSImage(size: NSSize(width: 128, height: 128))
}

@MainActor
enum ProbeCounters {
    static var counts: [String: Int] = [:]
    static var presentedOffsets: Set<CGFloat> = []
    static var cachedFrames: [String: CGRect] = [:]
    static var residentPageKeys: Set<String> = []
    static func record(_ key: String) { counts[key, default: 0] += 1 }
    static func recordGridState(_ slots: [Slot]) {
        residentPageKeys.insert(slots.first?.id ?? "empty")
        record("gridState")
    }
    static func acceptedFrames(_ frames: [String: CGRect]) {
        cachedFrames = frames
        record("acceptedFrameUpdates")
    }
    static func presentedOffset(_ value: CGFloat) -> CGFloat {
        presentedOffsets.insert(value)
        return value
    }
    static func reset() { counts = [:]; presentedOffsets = []; residentPageKeys = [] }
}

@MainActor
final class AppDelegate {
    static var current: AppDelegate?
    var alertParentWindow: NSWindow? { nil }
    func refreshTray() {}
    func openTrayFromPinch() {}
    func dismissTray() {}
}

struct ScrollEvent {
    struct Phase: OptionSet {
        let rawValue: Int
        static let began = Phase(rawValue: 1)
        static let changed = Phase(rawValue: 2)
        static let stationary = Phase(rawValue: 4)
        static let ended = Phase(rawValue: 8)
        static let cancelled = Phase(rawValue: 16)
    }
    var momentumPhase: Phase = []
    var scrollingDeltaX: CGFloat
    var scrollingDeltaY: CGFloat = 0
    var hasPreciseScrollingDeltas = true
    var phase: Phase
    var timestamp: TimeInterval
}

@MainActor
final class SwipeDriver {
    var panel: NSWindow?
    private var swipeAccum: CGFloat = 0
    private var swipeSamples: [(TimeInterval, CGFloat)] = []
    private var swipeIdleWork: DispatchWorkItem?
    func feed(_ event: ScrollEvent) { _ = handlePageSwipe(event) }
''' + handlers + r'''
}

@main
struct PagingPerformanceProbe {
    @MainActor
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        var settings = Preferences()
        settings.sources = []
        settings.columns = Int(CommandLine.arguments[3])!
        settings.rows = Int(CommandLine.arguments[4])!
        let apps = (0..<Int(CommandLine.arguments[2])!).map {
            AppItem(id: "test.\($0)", path: "/fixture/App\($0).app", bundleID: "test.\($0)",
                    name: "App \($0)", hidden: false, addedAt: Date(timeIntervalSince1970: 0), sourcePath: "/fixture")
        }
        let pages = stride(from: 0, to: apps.count, by: settings.pageCapacity).map { start in
            Page(slots: apps[start..<min(start + settings.pageCapacity, apps.count)].map { .app($0.id) })
        }
        let snapshot = LibrarySnapshot(settings: settings, apps: apps, folders: [], pages: pages, currentPage: min(1, pages.count - 1))
        try JSONEncoder().encode(snapshot).write(to: ProbeEnvironment.libraryURL)
        let model = AppModel.shared
        model.isOpen = true
        let size = NSSize(width: 1600, height: 1000)
        let host = NSHostingView(rootView: PinchpadRoot(model: model))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.isReleasedWhenClosed = false
        // The fixture remains unordered throughout; nothing appears on screen.
        precondition(!window.isVisible)
        let driver = SwipeDriver()
        driver.panel = window
        func update() {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.0005))
            host.layoutSubtreeIfNeeded()
        }
        let checking = CommandLine.arguments[5] == "check"
        var failures: [String] = []
        func require(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }
        func flush() { for _ in 0..<8 { update() } }
        func finishAnimations() {
            let deadline = ProcessInfo.processInfo.systemUptime + 0.5
            repeat { update() } while ProcessInfo.processInfo.systemUptime < deadline
        }
        func expectedIDs(_ indices: [Int]) -> Set<String> {
            Set(indices.flatMap { model.slots(on: $0).map(\.id) })
        }
        func checkFrames(_ indices: [Int], _ context: String) {
            require(Set(ProbeCounters.cachedFrames.keys) == expectedIDs(indices),
                    "\(context): frame IDs mismatch; found \(ProbeCounters.cachedFrames.count), expected \(expectedIDs(indices).count)")
            let activeIDs = expectedIDs([model.clampedPage])
            for id in activeIDs {
                guard let frame = ProbeCounters.cachedFrames[id] else { continue }
                require(frame.width > 0 && frame.height > 0 && frame.midX >= 0 && frame.midX <= size.width
                        && frame.midY >= 0 && frame.midY <= size.height,
                        "\(context): active icon frame is outside the fixture bounds")
            }
        }
        for _ in 0..<8 { update() }
        checkFrames([model.clampedPage], "initial active page")
        let initialFrames = ProbeCounters.cachedFrames
        print("fixture: \(apps.count) apps, \(pages.count) pages, \(settings.pageCapacity) icons/page")
        print("initial body work: \(ProbeCounters.counts.sorted { $0.key < $1.key })")
        let subscription = model.objectWillChange.sink { ProbeCounters.record("modelInvalidation") }
        ProbeCounters.reset()
        var idleSamples: [Double] = []
        for _ in 0..<120 {
            let start = ProcessInfo.processInfo.systemUptime
            update()
            idleSamples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        idleSamples.sort()
        print("120 idle forced updates: \(ProbeCounters.counts.sorted { $0.key < $1.key })")
        print(String(format: "idle forced update wall time: median %.3f ms, p95 %.3f ms", idleSamples[60], idleSamples[114]))
        var samples: [Double] = []
        ProbeCounters.reset()
        for index in 0..<240 {
            let event = ScrollEvent(scrollingDeltaX: index % 120 < 60 ? -0.8 : 0.8,
                                    phase: index == 0 ? .began : .changed,
                                    timestamp: Double(index) / 120)
            let start = ProcessInfo.processInfo.systemUptime
            driver.feed(event)
            update()
            samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        let firstInputMilliseconds = samples[0]
        samples.sort()
        print("240 precise-scroll samples: \(ProbeCounters.counts.sorted { $0.key < $1.key })")
        print("distinct presented horizontal offsets: \(ProbeCounters.presentedOffsets.count)")
        print("distinct resident grids during pan: \(ProbeCounters.residentPageKeys.count)")
        print(String(format: "event + forced update wall time: median %.3f ms, p95 %.3f ms, max %.3f ms", samples[120], samples[228], samples[239]))
        print(String(format: "first swipe input + forced update: %.3f ms", firstInputMilliseconds))
        if checking {
            let rootBodies = ProbeCounters.counts["rootBody", default: 0]
            let pagerBodies = ProbeCounters.counts["pagerBody", default: 0]
            guard rootBodies <= 2 else {
                fputs("FAIL: continuous swipe rebuilt unrelated root UI \(rootBodies) times (limit 2)\n", stderr)
                exit(1)
            }
            guard pagerBodies >= 120 && ProbeCounters.presentedOffsets.count >= 30 else {
                fputs("FAIL: pager stopped updating during actual swipe input: \(pagerBodies) updates\n", stderr)
                exit(1)
            }
            guard ProbeCounters.counts["frames", default: 0] == 0 else {
                fputs("FAIL: continuous swipe rebuilt drag hit geometry \(ProbeCounters.counts["frames", default: 0]) times\n", stderr)
                exit(1)
            }
            guard ProbeCounters.residentPageKeys.count <= 3 else {
                fputs("FAIL: continuous pan mounted more than 3 page grids\n", stderr)
                exit(1)
            }
            print("PASS: continuous motion updates the pager while root UI stays isolated")
        }
        require(ProbeCounters.cachedFrames == initialFrames,
                "Continuous swipe discarded the previous hit-test frames before settlement")

        ProbeCounters.reset()
        let pageBeforeSettle = model.clampedPage
        driver.feed(ScrollEvent(scrollingDeltaX: 0, phase: .ended, timestamp: 2))
        finishAnimations()
        require(!model.paging.isSwiping && model.paging.offset == 0 && model.clampedPage == pageBeforeSettle,
                "Finishing a subthreshold swipe does not return to the same page")
        checkFrames([model.clampedPage], "settled active page")
        require(ProbeCounters.counts["frames", default: 0] > 0,
                "Settling does not restore active-page geometry collection")
        print("settled frame work: \(ProbeCounters.counts.sorted { $0.key < $1.key })")

        ProbeCounters.reset()
        driver.feed(ScrollEvent(scrollingDeltaX: -0.8, phase: .began, timestamp: 3))
        flush()
        require(ProbeCounters.counts["frames", default: 0] == 0,
                "Starting another swipe recreates hit-test geometry while moving")
        driver.feed(ScrollEvent(scrollingDeltaX: 0, phase: .cancelled, timestamp: 3.2))
        finishAnimations()
        require(!model.paging.isSwiping && model.paging.offset == 0 && model.clampedPage == pageBeforeSettle,
                "Cancelling a subthreshold swipe does not restore its page state")
        checkFrames([model.clampedPage], "cancelled active page")
        require(ProbeCounters.counts["frames", default: 0] > 0,
                "Cancelling leaves hit-test geometry collection disabled")

        if model.pages.count > 1 {
            ProbeCounters.reset()
            let direction = model.clampedPage < model.pages.count - 1 ? 1 : -1
            let previousPage = model.clampedPage
            driver.feed(ScrollEvent(scrollingDeltaX: -CGFloat(direction) * 220, phase: .began, timestamp: 4))
            flush()
            driver.feed(ScrollEvent(scrollingDeltaX: -CGFloat(direction) * 40, phase: .changed, timestamp: 4.1))
            flush()
            require(ProbeCounters.counts["frames", default: 0] == 0,
                    "Committed pan collects drag geometry before the gesture ends")
            driver.feed(ScrollEvent(scrollingDeltaX: 0, phase: .ended, timestamp: 4.2))
            finishAnimations()
            require(model.clampedPage == previousPage + direction && !model.paging.isSwiping && model.paging.offset == 0,
                    "A committed swipe does not advance once and clear motion state")
            checkFrames([model.clampedPage], "committed swipe active page")
        }

        ProbeCounters.reset()
        // Set state only: beginDrag would create a native drag panel and is intentionally never called.
        model.draggingID = model.slots(on: model.clampedPage).first?.id
        flush()
        let adjacentPages = model.pages.indices.filter { abs($0 - model.clampedPage) <= 1 }
        checkFrames(adjacentPages, "drag adjacent pages")
        for index in adjacentPages where index != model.clampedPage {
            if let id = model.slots(on: index).first?.id, let frame = ProbeCounters.cachedFrames[id] {
                require(index < model.clampedPage ? frame.midX < 0 : frame.midX > size.width,
                        "Adjacent page hit frames have stale on-screen coordinates during drag")
            }
        }
        if model.pages.count > 1 {
            let direction = model.clampedPage < model.pages.count - 1 ? 1 : -1
            let previousPage = model.clampedPage
            model.turnPage(direction)
            finishAnimations()
            require(model.clampedPage == previousPage + direction, "Drag edge page turn did not advance once")
            checkFrames(model.pages.indices.filter { abs($0 - model.clampedPage) <= 1 }, "drag after edge page turn")
        }
        model.draggingID = nil
        flush()
        checkFrames([model.clampedPage], "drag ended active page")

        model.showPage(min(2, model.pages.count - 1))
        finishAnimations()
        print("keyboard workload starts at page \(model.clampedPage + 1)")
        ProbeCounters.reset()
        var keySamples: [Double] = []
        if model.pages.count > 1 {
            for index in 0..<12 {
                let direction = index % 2 == 0 ? (model.clampedPage > 0 ? -1 : 1)
                    : (model.clampedPage < model.pages.count - 1 ? 1 : -1)
                let previousPage = model.clampedPage
                let start = ProcessInfo.processInfo.systemUptime
                model.turnPage(direction)
                update()
                keySamples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                require(model.clampedPage == previousPage + direction,
                        "Keyboard-equivalent turnPage did not move exactly one page")
                checkFrames([model.clampedPage], "keyboard page step \(index + 1)")
            }
            keySamples.sort()
            print("12 keyboard-equivalent page steps: \(ProbeCounters.counts.sorted { $0.key < $1.key })")
            print(String(format: "page step + forced update wall time: median %.3f ms, max %.3f ms", keySamples[6], keySamples[11]))
            if model.pages.count <= 3 {
                require(ProbeCounters.counts["cellBody", default: 0] == 0,
                        "Keyboard paging unnecessarily remounts offscreen cells in a three-page library")
            }
        }

        // Search and vertical browsing keep geometry enabled even if stale gesture state exists.
        model.paging.isSwiping = true
        model.query = "App 1"
        flush()
        require(Set(ProbeCounters.cachedFrames.keys) == Set(model.visibleSlots.map(\.id)),
                "Search results lost their hit-test frames")
        model.query = ""
        model.settings.browsing = .scroll
        flush()
        require(Set(ProbeCounters.cachedFrames.keys) == Set(model.visibleSlots.map(\.id)),
                "Vertical browsing lost its hit-test frames")
        model.paging.isSwiping = false
        model.settings.browsing = .paged
        flush()
        checkFrames([model.clampedPage], "restored paged browsing")
        if checking {
            guard failures.isEmpty else {
                for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
                exit(1)
            }
            print("PASS: pan geometry stays paused; settle/cancel restore active frames; drag and edge turns retain adjacent frames")
            print("PASS: keyboard-equivalent page steps, search and vertical browsing preserve geometry")
        }
        precondition(!window.isVisible)
        withExtendedLifetime(subscription) {}
        print("NOTE: CPU fixture only; excludes visible-window composition/GPU and is not an FPS measurement")
    }
}
'''

with tempfile.TemporaryDirectory(prefix="pinchpad-paging-performance-") as directory:
    directory = Path(directory)
    isolated_model = directory / "AppModel.swift"
    isolated_model.write_text(model)
    isolated_view = directory / "PinchpadView.swift"
    isolated_view.write_text(view)
    probe = directory / "PagingPerformanceProbe.swift"
    probe.write_text(harness)
    binary = directory / "probe"
    sources = [root / "Sources" / name for name in (
        "Model.swift", "PinchClassifier.swift", "Services.swift", "PanelAlertPresenter.swift", "IconEntrance.swift",
    )]
    sources += sorted((root / "Sources").glob("AppLibrary*.swift"))
    sources += sorted((root / "Sources").glob("PagingMotion.swift"))
    sources += sorted((root / "Sources").glob("EntranceMotion.swift"))
    subprocess.run([
        "swiftc", "-swift-version", "5", "-O", "-module-cache-path", "/tmp/pinchpad-build-module-cache",
        *map(str, sources), str(isolated_model), str(isolated_view), str(probe), "-lsqlite3", "-o", str(binary),
    ], check=True)
    fixtures = [(arguments.apps, arguments.columns, arguments.rows)]
    if arguments.large_fixture and (600, 10, 6) not in fixtures:
        fixtures.append((600, 10, 6))
    exit_code = 0
    for app_count, columns, rows in fixtures:
        result = subprocess.run([
            str(binary), str(directory), str(app_count), str(columns), str(rows),
            "check" if arguments.check else "measure",
        ], text=True, capture_output=True)
        print(result.stdout, end="")
        print(result.stderr, end="")
        exit_code = exit_code or result.returncode
    raise SystemExit(exit_code)
