"""Replay real opening signals and SwiftUI view work without visible windows.

The temporary model uses isolated fixture storage and no device/source hooks.
Activation, native reveal/ordering and desktop presentation are excluded; the
production open/close/entrance logic and real root/grid/BloomIn views are used.
Counts and main-thread CPU time describe app-side work, not visible-window FPS.
Run: python3 Tests/OpeningPerformanceProbe.py [--check]
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


def instrument_body(source, declaration, statement):
    start = source.index(declaration)
    opening = source.index("var body: some View {", start)
    insertion = opening + len("var body: some View {")
    return source[:insertion] + "\n        let _ = " + statement + source[insertion:]


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--check", action="store_true", help="Reject grid/cell reconstruction during repeated warm opening")
parser.add_argument("--cycles", type=int, default=8)
arguments = parser.parse_args()
if arguments.cycles < 1:
    parser.error("--cycles must be positive")
root = Path(__file__).resolve().parents[1]
model = (root / "Sources/AppModel.swift").read_text()
view = (root / "Sources/PinchpadView.swift").read_text()
app = (root / "Sources/AppMain.swift").read_text()
start = model.index("        let appSupport =", model.index("private init()"))
end = model.index("        if let data =", start)
model = model[:start] + "        fileURL = ProbeEnvironment.libraryURL\n" + model[end:]
for marker in (
    "private func prefetchIcons()", "private func wireMonitors()", "private func updateAppSources()",
    "private func applyChrome()", "func refreshRunningApps()", "private func persist()",
):
    method = block(model, marker)
    model = model.replace(method, method[:method.index("{") + 1] + "}")
method = block(model, "func icon(for app: AppItem)")
model = model.replace(method, method[:method.index("{") + 1] + " return ProbeEnvironment.icon }")
activation = block(model, "if !NSApp.isActive")
model = model.replace(activation, 'ProbeCounters.record("activationBoundary")')

for declaration, statement in (
    ("struct PinchpadRoot:", 'ProbeCounters.record("rootBody")'),
    ("private struct JellyPages:", 'ProbeCounters.record("pagerBody")'),
    ("private struct IconGrid:", 'ProbeCounters.record("gridBody")'),
    ("private struct SlotCell:", 'ProbeCounters.record("cellBody")'),
    ("private struct BloomIn<Content:", 'ProbeCounters.bloomBody(page: probePageID, enabled: enabled, delay: delay, appeared: appeared)'),
):
    view = instrument_body(view, declaration, statement)
for marker, counter in (
    ("init(slot: Slot, model: AppModel, iconSide: CGFloat, plate: CGFloat) {", "cellInit"),
    ("private func setAppeared(_ value: Bool) {", "setAppeared"),
    ("private func bloomIn(signal: IconEntrance.Signal) {", "bloomSchedule"),
):
    view = view.replace(marker, marker + f'\n        ProbeCounters.record("{counter}")')
action = "IconEntrance.action(from: old, to: new, enabled: enabled, reduceMotion: reduceMotion)"
view = view.replace("switch " + action + " {", "switch ProbeCounters.action(" + action + ", page: probePageID) {")
view = view.replace("guard scheduledSignal == signal else { return }", "guard scheduledSignal == signal else { return }\n            ProbeCounters.record(\"bloomPlay\")\n            ProbeCounters.playedPages.insert(probePageID)")
view = view.replace("private struct BloomIn<Content: View>: View {", "private struct BloomIn<Content: View>: View {\n    @Environment(\\.probePageID) private var probePageID")
view = view.replace("                .zIndex(\n                    ringed[ring].contains", "                .environment(\\.probePageID, slots.first?.id ?? \"empty\")\n                .zIndex(\n                    ringed[ring].contains")
# This environment value is read-only in SwiftUI; pin only the temporary fixture's input.
view = view.replace("@Environment(\\.accessibilityReduceMotion) private var reduceMotion", "private let reduceMotion = false")

finish_conceal = block(app, "private func finishConceal(token: Int)")
finish_conceal = finish_conceal.replace(block(finish_conceal, "if let panel {"), "")
finish_conceal = finish_conceal.replace("        auroraView?.layer?.sublayers?.forEach { $0.removeAllAnimations() }\n", "")
finish_conceal = finish_conceal.replace("        setDockHidden(false)\n", "")

harness = r'''import AppKit
import Combine
import Darwin
import Foundation
import SwiftUI

enum ProbeEnvironment {
    static let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    static var libraryURL: URL { root.appendingPathComponent("library.json") }
    static let icon = NSImage(size: NSSize(width: 128, height: 128))
}

struct ProbePageKey: EnvironmentKey {
    static let defaultValue = ""
}

extension EnvironmentValues {
    var probePageID: String {
        get { self[ProbePageKey.self] }
        set { self[ProbePageKey.self] = newValue }
    }
}

@MainActor
enum ProbeCounters {
    static var counts: [String: Int] = [:]
    static var activeAppearances: [TimeInterval: Bool] = [:]
    static var pageAppearances: [String: [TimeInterval: Bool]] = [:]
    static var playedPages: Set<String> = []
    static var animatedPages: Set<String> = []
    static func record(_ key: String) { counts[key, default: 0] += 1 }
    static func bloomBody(page: String, enabled: Bool, delay: TimeInterval, appeared: Bool) {
        record("bloomBody")
        pageAppearances[page, default: [:]][delay] = appeared
        if enabled { activeAppearances[delay] = appeared }
    }
    static func action(_ value: IconEntrance.Action, page: String) -> IconEntrance.Action {
        switch value {
        case .none: record("action.none")
        case .show: record("action.show")
        case .reset: record("action.reset")
        case .animate:
            record("action.animate")
            animatedPages.insert(page)
        }
        return value
    }
    static func reset() { counts = [:]; playedPages = []; animatedPages = [] }
}

@MainActor
final class AppDelegate {
    static var current: AppDelegate?
    var alertParentWindow: NSWindow? { nil }
    func refreshTray() {}
    func openTrayFromPinch() {}
    func dismissTray() {}
}

@MainActor
final class OpeningDriver {
    private var visibilityToken = 0
    private var pendingCloseToken: Int?
    func bind() {
        AppModel.shared.onOpenChange = { [weak self] in self?.synchronize() }
    }
    private func synchronize() {
        visibilityToken += 1
        if AppModel.shared.isOpen {
            // Production sync -> reveal starts the wave synchronously.
            AppModel.shared.beginEntrance()
        } else {
            pendingCloseToken = visibilityToken
        }
    }
    func finishClosing() {
        if let token = pendingCloseToken { finishConceal(token: token) }
        pendingCloseToken = nil
    }
''' + finish_conceal + r'''
}

struct Measurement {
    var wall: Double
    var mainCPU: Double
    var counts: [String: Int]
}

@main
struct OpeningPerformanceProbe {
    static func threadMilliseconds() -> Double {
        var time = timespec()
        precondition(clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time) == 0)
        return Double(time.tv_sec) * 1000 + Double(time.tv_nsec) / 1_000_000
    }

    @MainActor
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        var settings = Preferences()
        settings.sources = []
        settings.columns = 8
        settings.rows = 5
        settings.returnToFirstPage = false
        let apps = (0..<116).map {
            AppItem(id: "test.\($0)", path: "/fixture/App\($0).app", bundleID: "test.\($0)",
                    name: "App \($0)", hidden: false, addedAt: Date(timeIntervalSince1970: 0), sourcePath: "/fixture")
        }
        let pages = stride(from: 0, to: apps.count, by: settings.pageCapacity).map { start in
            Page(slots: apps[start..<min(start + settings.pageCapacity, apps.count)].map { .app($0.id) })
        }
        let snapshot = LibrarySnapshot(settings: settings, apps: apps, folders: [], pages: pages, currentPage: 1)
        try JSONEncoder().encode(snapshot).write(to: ProbeEnvironment.libraryURL)
        let model = AppModel.shared
        let host = NSHostingView(rootView: PinchpadRoot(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 1470, height: 956)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.isReleasedWhenClosed = false
        precondition(!window.isVisible)
        let driver = OpeningDriver()
        driver.bind()
        func update() {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.0005))
            host.layoutSubtreeIfNeeded()
        }
        func flush() { for _ in 0..<8 { update() } }
        func measure(_ action: () -> Void) -> Measurement {
            ProbeCounters.reset()
            let wallStart = ProcessInfo.processInfo.systemUptime
            let cpuStart = threadMilliseconds()
            action()
            flush()
            return Measurement(wall: (ProcessInfo.processInfo.systemUptime - wallStart) * 1000,
                               mainCPU: threadMilliseconds() - cpuStart,
                               counts: ProbeCounters.counts)
        }
        func report(_ label: String, _ samples: [Measurement]) {
            let wall = samples.map(\.wall).sorted()
            let cpu = samples.map(\.mainCPU).sorted()
            var total: [String: Int] = [:]
            for sample in samples { for (key, value) in sample.counts { total[key, default: 0] += value } }
            print("\(label) (\(samples.count) repetitions): \(total.sorted { $0.key < $1.key })")
            print(String(format: "  median wall %.3f ms, max wall %.3f ms; median main-thread CPU %.3f ms, max CPU %.3f ms",
                         wall[wall.count / 2], wall.last!, cpu[cpu.count / 2], cpu.last!))
        }
        var failures: [String] = []
        func require(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }
        flush()
        print("fixture: 116 apps,3 pages,8x5 grid,1470x956 points; original wave forced on")
        print("initial warm-up work: \(ProbeCounters.counts.sorted { $0.key < $1.key })")
        // Production prewarmPanel prepares once after hidden layout/display work.
        let preparation = measure { model.prepareEntrance() }
        report("hidden prewarm prepareEntrance", [preparation])
        require(ProbeCounters.activeAppearances.count == 4 && ProbeCounters.activeAppearances.values.allSatisfy { !$0 },
                "Hidden preparation did not reset the actual four active BloomIn rings")
        let subscription = model.objectWillChange.sink { ProbeCounters.record("modelInvalidation") }
        let idle = (0..<4).map { _ in measure {} }
        report("idle drain", idle)
        var openings: [Measurement] = []
        var closings: [Measurement] = []
        var finishing: [Measurement] = []
        for cycle in 0..<Int(CommandLine.arguments[3])! {
            let opening = measure { model.open() }
            openings.append(opening)
            require(opening.counts["action.animate", default: 0] == 4 && opening.counts["bloomPlay", default: 0] == 4,
                    "Opening \(cycle + 1) failed to replay the original four active rings once")
            let activePageID = model.slots(on: model.clampedPage).first!.id
            require(ProbeCounters.playedPages == [activePageID] && ProbeCounters.animatedPages == [activePageID],
                    "Opening \(cycle + 1) played the wave on an offscreen page")
            require(ProbeCounters.activeAppearances.count == 4 && ProbeCounters.activeAppearances.values.allSatisfy { $0 },
                    "Opening \(cycle + 1) left a rendered active ring hidden")
            let closing = measure { model.close() }
            closings.append(closing)
            let finish = measure { driver.finishClosing() }
            finishing.append(finish)
            require(!model.isOpen && ProbeCounters.activeAppearances.values.allSatisfy { !$0 },
                    "Finishing close \(cycle + 1) did not prepare the actual active rings")
        }
        report("warm open + wave", openings)
        report("close signal", closings)
        report("finishConceal + hidden preparation", finishing)
        print(String(format: "first warm open: wall %.3f ms, main-thread CPU %.3f ms", openings[0].wall, openings[0].mainCPU))

        _ = measure { model.open() }
        let repeated = measure { model.open() }
        require(repeated.counts["rootBody", default: 0] == 0 && repeated.counts["bloomPlay", default: 0] == 0
                && repeated.counts["action.reset", default: 0] == 0,
                "Opening an already-open model replays or reconstructs the panel")
        _ = measure { model.close() }
        _ = measure { model.open() }
        let staleClose = measure { driver.finishClosing() }
        require(model.isOpen && staleClose.counts["action.reset", default: 0] == 0,
                "A stale close completion resets a newly opened panel")
        _ = measure { model.close() }
        _ = measure { driver.finishClosing() }
        _ = measure { model.open() }
        _ = measure { model.showPage(2) }
        _ = measure { model.close() }
        _ = measure { driver.finishClosing() }
        model.settings.returnToFirstPage = true
        flush()
        let returned = measure { model.open() }
        let firstPageID = model.slots(on: 0).first!.id
        require(model.clampedPage == 0 && returned.counts["bloomPlay", default: 0] == 4
                && ProbeCounters.playedPages == [firstPageID] && ProbeCounters.animatedPages == [firstPageID],
                "Returning to the first page played the opening wave on the old or offscreen page")
        require(ProbeCounters.pageAppearances[firstPageID]?.count == 4
                && ProbeCounters.pageAppearances[firstPageID]!.values.allSatisfy { $0 },
                "Returning to the first page left its actual rings hidden")
        _ = measure { model.close() }
        _ = measure { driver.finishClosing() }
        if CommandLine.arguments[2] == "check" {
            let reconstructed = openings.reduce(0) { $0 + $1.counts["cellInit", default: 0] }
            require(reconstructed == 0,
                    "Repeated warm opens reconstructed \(reconstructed) unchanged SlotCell values; entrance motion must reuse existing cells")
            guard failures.isEmpty else {
                for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
                exit(1)
            }
            print("PASS: warm opening reuses cells, replays four rings and rejects duplicate/stale lifecycle signals")
        }
        precondition(!window.isVisible)
        withExtendedLifetime(subscription) {}
        print("NOTE: native activation, window reveal/order, blur and visible-window/GPU composition excluded; not an FPS measurement")
    }
}
'''

with tempfile.TemporaryDirectory(prefix="pinchpad-opening-performance-") as directory:
    directory = Path(directory)
    isolated_model = directory / "AppModel.swift"
    isolated_model.write_text(model)
    isolated_view = directory / "PinchpadView.swift"
    isolated_view.write_text(view)
    probe = directory / "OpeningPerformanceProbe.swift"
    probe.write_text(harness)
    binary = directory / "probe"
    sources = [root / "Sources" / name for name in (
        "Model.swift", "PinchClassifier.swift", "Services.swift", "PanelAlertPresenter.swift", "IconEntrance.swift", "PagingMotion.swift",
    )]
    sources += sorted((root / "Sources").glob("AppLibrary*.swift"))
    sources += sorted((root / "Sources").glob("EntranceMotion.swift"))
    subprocess.run([
        "swiftc", "-swift-version", "5", "-O", "-module-cache-path", "/tmp/pinchpad-build-module-cache",
        *map(str, sources), str(isolated_model), str(isolated_view), str(probe), "-lsqlite3", "-o", str(binary),
    ], check=True)
    result = subprocess.run([
        str(binary), str(directory), "check" if arguments.check else "measure", str(arguments.cycles),
    ], text=True, capture_output=True)
    print(result.stdout, end="")
    print(result.stderr, end="")
    raise SystemExit(result.returncode)
