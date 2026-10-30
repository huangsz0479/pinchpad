"""Replay real opening signals and SwiftUI view work without visible windows.

The temporary model uses isolated fixture storage and no device/source hooks.
Activation, native reveal/ordering and desktop presentation are excluded; the
production open/close/entrance logic and real root/grid/BloomIn views are used.
Both window and fullscreen layouts use decoded, nonempty bitmap fixtures.
A 500 ms observation covers the complete four-ring wave. Counts and
main-thread CPU time describe app-side work, not visible-window FPS.
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
parser.add_argument("--apps", type=int, default=116)
parser.add_argument("--mode", choices=("paged", "window", "both"), default="both")
arguments = parser.parse_args()
if arguments.apps < 80:
    parser.error("--apps must be at least 80 for the multi-page regression")
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
model = model.replace(method, method[:method.index("{") + 1] + ' return ProbeEnvironment.icons[Int(app.id.split(separator: ".").last!)! % ProbeEnvironment.icons.count] }')
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
view = view.replace("private struct BloomIn<Content: View>: View {", "private struct BloomIn<Content: View>: View {\n    @Environment(\\.probePageID) private var probePageID\n    @Environment(\\.probeGridSize) private var probeGridSize")
view = view.replace("                .zIndex(\n                    ringed[ring].contains", "                .environment(\\.probePageID, slots.first?.id ?? \"empty\")\n                .environment(\\.probeGridSize, CGSize(width: gridWidth, height: gridHeight))\n                .zIndex(\n                    ringed[ring].contains")
bloom_start = view.index("private struct BloomIn<Content: View>: View {")
content_start = view.index("        content\n", bloom_start)
view = view[:content_start] + view[content_start:].replace("        content\n", r'''        content
            .background {
                GeometryReader { geometry in
                    Color.clear.onAppear {
                        ProbeCounters.ringGeometry["\(probePageID):\(delay)"] = (geometry.size, probeGridSize)
                    }
                }
            }
''', 1)
bloom_start = view.index("private struct BloomIn<Content: View>: View {")
receiver_start = view.index("private struct EntranceSignalReceiver:", bloom_start)
view = view[:bloom_start] + view[bloom_start:receiver_start].replace(
    "DispatchQueue.main.async {", 'ProbeCounters.record("bloomDeferred"); DispatchQueue.main.async {'
) + view[receiver_start:]
# This environment value is read-only in SwiftUI; pin only the temporary fixture's input.
view = view.replace("@Environment(\\.accessibilityReduceMotion) private var reduceMotion", "private let reduceMotion = false")

finish_conceal = block(app, "private func finishConceal(token: Int)")
finish_conceal = finish_conceal.replace(block(finish_conceal, "if let panel {"), "")
finish_conceal = finish_conceal.replace("        auroraView?.layer?.sublayers?.forEach { $0.removeAllAnimations() }\n", "")
finish_conceal = finish_conceal.replace("        setDockHidden(false)\n", "")

mode_sync = block(app, "private func sync(")
mode_ensure = block(app, "private func ensurePanel()")
mode_ensure = mode_ensure.replace("        self.panel = panel", "        allPanels.append(WeakPanel(panel: panel))\n        self.panel = panel")

harness = r'''import AppKit
import Combine
import Darwin
import Foundation
import SwiftUI

enum ProbeEnvironment {
    static let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    static var libraryURL: URL { root.appendingPathComponent("library.json") }
    static let icons: [NSImage] = (0..<116).map { index in
        let side = 256
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor(calibratedHue: CGFloat(index % 23) / 23,
                                     saturation: 0.65, brightness: 0.9, alpha: 1).cgColor)
        context.addPath(CGPath(roundedRect: CGRect(x: 20, y: 20, width: 216, height: 216),
                               cornerWidth: 48, cornerHeight: 48, transform: nil))
        context.fillPath()
        context.setFillColor(CGColor(gray: 1, alpha: 0.9))
        context.fillEllipse(in: CGRect(x: 66, y: 66, width: 124, height: 124))
        let image = NSImage(cgImage: context.makeImage()!, size: NSSize(width: 128, height: 128))
        precondition(!image.representations.isEmpty)
        return image
    }
}

struct ProbePageKey: EnvironmentKey {
    static let defaultValue = ""
}

struct ProbeGridSizeKey: EnvironmentKey {
    static let defaultValue = CGSize.zero
}

extension EnvironmentValues {
    var probeGridSize: CGSize {
        get { self[ProbeGridSizeKey.self] }
        set { self[ProbeGridSizeKey.self] = newValue }
    }
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
    static var ringGeometry: [String: (actual: CGSize, expected: CGSize)] = [:]
    static func record(_ key: String) { counts[key, default: 0] += 1 }
    static func bloomBody(page: String, enabled: Bool, delay: TimeInterval, appeared: Bool) {
        record("bloomBody")
        record(enabled ? "activeBloomBody" : "offscreenBloomBody")
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
    func openClotheslineFromPinch() {}
    func dismissCompanionPanels() {}
    func dismissTray() {}
}

@MainActor
final class OpeningDriver {
    private var visibilityToken = 0
    private var pendingCloseToken: Int?
    func bind() {
        AppModel.shared.onOpenChange = { [weak self] _ in self?.synchronize() }
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

typealias PanelHost = NSHostingView<PinchpadRoot>
final class KeyPanel: NSPanel {}
struct WeakPanel { weak var panel: NSPanel? }

@MainActor
final class ModeOpeningDriver: NSObject, NSWindowDelegate {
    static let coverLevel = NSWindow.Level.floating
    var panel: KeyPanel?
    var host: PanelHost?
    var auroraView: NSView?
    var panelWindowed = false
    var panelRevealed = false
    var visibilityToken = 0
    var auroraBuilt = false
    var auroraBuiltSize = CGSize.zero
    var auroraBuiltBackdrop: BackdropKind?
    var allPanels: [WeakPanel] = []
    func bind() { AppModel.shared.onOpenChange = { [weak self] animated in self?.sync(animated: animated) } }
    func dismissTray() {}
    func setDockHidden(_ value: Bool) {}
    func installOutsideMonitor() {}
    func removeOutsideMonitor() {}
    func conceal(token: Int) {}
    func finishConceal(token: Int) {}
    func layout() {
        let size = panelWindowed ? CGSize(width: 850, height: 650) : CGSize(width: 1470, height: 956)
        panel?.setContentSize(size)
        host?.frame = CGRect(origin: .zero, size: size)
    }
    func reveal() {
        precondition(panel?.isVisible == false)
        panelRevealed = true
        AppModel.shared.beginEntrance()
    }
    func synchronizeAgain() { sync() }
''' + mode_sync + "\n" + mode_ensure + r'''
}

struct Measurement {
    var wall: Double
    var mainCPU: Double
    var counts: [String: Int]
    var peakUpdateCPU: Double
    var initialCPU: Double
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
        let windowed = CommandLine.arguments[4] == "window"
        settings.browsing = windowed ? .window : .paged
        let appCount = Int(CommandLine.arguments[5])!
        let apps = (0..<appCount).map {
            AppItem(id: "test.\($0)", path: "/fixture/App\($0).app", bundleID: "test.\($0)",
                    name: "App \($0)", hidden: false, addedAt: Date(timeIntervalSince1970: 0), sourcePath: "/fixture")
        }
        let pages = stride(from: 0, to: apps.count, by: settings.pageCapacity).map { start in
            Page(slots: apps[start..<min(start + settings.pageCapacity, apps.count)].map { .app($0.id) })
        }
        let snapshot = LibrarySnapshot(settings: settings, apps: apps, folders: [], pages: pages, currentPage: 1)
        try JSONEncoder().encode(snapshot).write(to: ProbeEnvironment.libraryURL)
        let model = AppModel.shared
        let host = NSHostingView(rootView: AnyView(PinchpadRoot(model: model)))
        host.frame = NSRect(x: 0, y: 0, width: windowed ? 850 : 1470, height: windowed ? 650 : 956)
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
            host.displayIfNeeded()
        }
        func flush() { for _ in 0..<8 { update() } }
        func measure(duration: Double = 0, _ action: () -> Void) -> Measurement {
            ProbeCounters.reset()
            let wallStart = ProcessInfo.processInfo.systemUptime
            let cpuStart = threadMilliseconds()
            action()
            flush()
            let initialCPU = threadMilliseconds() - cpuStart
            var peakUpdateCPU = initialCPU
            while ProcessInfo.processInfo.systemUptime - wallStart < duration {
                // Drive deferred SwiftUI work at up to 120 Hz, without ordering a window on screen.
                usleep(7_000)
                let updateStart = threadMilliseconds()
                update()
                peakUpdateCPU = max(peakUpdateCPU, threadMilliseconds() - updateStart)
            }
            return Measurement(wall: (ProcessInfo.processInfo.systemUptime - wallStart) * 1000,
                               mainCPU: threadMilliseconds() - cpuStart,
                               counts: ProbeCounters.counts, peakUpdateCPU: peakUpdateCPU, initialCPU: initialCPU)
        }
        func report(_ label: String, _ samples: [Measurement]) {
            let wall = samples.map(\.wall).sorted()
            let cpu = samples.map(\.mainCPU).sorted()
            let initial = samples.map(\.initialCPU).sorted()
            var total: [String: Int] = [:]
            for sample in samples { for (key, value) in sample.counts { total[key, default: 0] += value } }
            print("\(label) (\(samples.count) repetitions): \(total.sorted { $0.key < $1.key })")
            print(String(format: "  median wall %.3f ms, max wall %.3f ms; median main-thread CPU %.3f ms, max CPU %.3f ms",
                         wall[wall.count / 2], wall.last!, cpu[cpu.count / 2], cpu.last!))
            print(String(format: "  median initial action/flush CPU %.3f ms, peak action/update CPU %.3f ms",
                         initial[initial.count / 2], samples.map(\.peakUpdateCPU).max()!))
        }
        var failures: [String] = []
        func require(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }
        flush()
        print("fixture: \(appCount) decoded bitmap icons,\(pages.count) pages,8x5 grid,\(Int(host.frame.width))x\(Int(host.frame.height)) points,\(settings.browsing.rawValue); full 500 ms wave observation")
        print("initial warm-up work: \(ProbeCounters.counts.sorted { $0.key < $1.key })")
        let wrongOrigins = ProbeCounters.ringGeometry.filter {
            $0.value.expected != .zero
                && (abs($0.value.actual.width - $0.value.expected.width) > 1
                    || abs($0.value.actual.height - $0.value.expected.height) > 1)
        }
        require(wrongOrigins.isEmpty,
                "Wave rings scale around their cell instead of the full grid center: \(wrongOrigins)")
        // Production prewarmPanel prepares once after hidden layout/display work.
        let preparation = measure { model.prepareEntrance() }
        report("hidden prewarm prepareEntrance", [preparation])
        require(ProbeCounters.activeAppearances.count == 4 && ProbeCounters.activeAppearances.values.allSatisfy { !$0 },
                "Hidden preparation did not reset the actual four active BloomIn rings")
        let subscription = model.objectWillChange.sink { ProbeCounters.record("modelInvalidation") }
        let idle = (0..<3).map { _ in measure(duration: 0.5) {} }
        report("idle drain", idle)
        var openings: [Measurement] = []
        var closings: [Measurement] = []
        var finishing: [Measurement] = []
        for cycle in 0..<Int(CommandLine.arguments[3])! {
            let opening = measure(duration: 0.5) { model.open() }
            openings.append(opening)
            require(opening.counts["bloomDeferred", default: 0] == 0,
                    "A prepared opening inserted an extra main-loop gap before starting the wave")
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
        let interrupted = measure {
            model.close()
            model.open()
        }
        require(interrupted.counts["action.reset", default: 0] == 0
                && interrupted.counts["bloomPlay", default: 0] == 0,
                "Reopening during fade-out reset or replayed already-visible icons")
        let staleClose = measure { driver.finishClosing() }
        require(model.isOpen && staleClose.counts["action.reset", default: 0] == 0,
                "A stale close completion resets a newly opened panel")
        _ = measure { model.close() }
        _ = measure { driver.finishClosing() }
        _ = measure { model.open() }
        model.settings.returnToFirstPage = true
        for page in 2..<model.pages.count {
            let navigation = measure { model.showPage(page) }
            require(navigation.counts["bloomPlay", default: 0] == 0,
                    "Ordinary navigation to page \(page) replayed the entrance wave")
        }
        let pageChange = measure(duration: 0.5) {}
        require(pageChange.counts["bloomPlay", default: 0] == 0,
                "Ordinary page navigation replayed the entrance wave")
        _ = measure { model.close() }
        _ = measure { driver.finishClosing() }
        flush()
        let returned = measure { model.open() }
        let firstPageID = model.slots(on: 0).first!.id
        require(model.clampedPage == 0 && returned.counts["bloomPlay", default: 0] == 4
                && ProbeCounters.playedPages == [firstPageID] && ProbeCounters.animatedPages == [firstPageID],
                "Returning to the first page played the opening wave on the old or offscreen page")
        require(ProbeCounters.pageAppearances[firstPageID]?.count == 4
                && ProbeCounters.pageAppearances[firstPageID]!.values.allSatisfy { $0 },
                "Returning to the first page left its actual rings hidden")
        _ = measure { model.showPage(model.pages.count - 1) }
        let immediateReopen = measure {
            model.close()
            model.open()
            driver.finishClosing()
        }
        require(model.isOpen && model.clampedPage == 0
                && immediateReopen.counts["bloomPlay", default: 0] == 4
                && ProbeCounters.playedPages == [firstPageID],
                "Closing on a distant page and immediately reopening skipped or misplaced the four rings")
        _ = measure { model.close() }
        _ = measure { driver.finishClosing() }

        // Folder items use tracksResets=false: preparing the main grid must not hide them.
        _ = measure { model.open() }
        model.makeFolder(from: [.app("test.0"), .app("test.1")])
        flush()
        let folder = model.folders.last!
        _ = measure(duration: 0.5) { model.openFolderID = folder.id }
        require(ProbeCounters.pageAppearances[""]?.count == 2
                && ProbeCounters.pageAppearances[""]!.values.allSatisfy { $0 },
                "Opening the folder left a newly mounted item hidden")
        _ = measure { model.prepareEntrance() }
        require(ProbeCounters.pageAppearances[""]?.values.allSatisfy { $0 } == true,
                "A main-page reset hid the folder's tracksResets=false items")
        _ = measure { model.close() }
        _ = measure { driver.finishClosing() }
        // Exercise the production new-panel/host creation and sync ordering. Native reveal
        // is replaced only at the final boundary, so every fixture stays off screen.
        host.rootView = AnyView(EmptyView())
        flush()
        let modeDriver = ModeOpeningDriver()
        modeDriver.bind()
        func flushMode() {
            for _ in 0..<12 {
                modeDriver.panel?.contentView?.layoutSubtreeIfNeeded()
                modeDriver.panel?.displayIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.0005))
            }
        }
        ProbeCounters.reset()
        model.open()
        flushMode()
        require(ProbeCounters.counts["bloomPlay", default: 0] == 4,
                "A newly created launcher host swallowed its first entrance signal")
        for browsing in [Browsing.window, .paged, .window] {
            if browsing == model.settings.browsing { continue }
            ProbeCounters.reset()
            model.settings.browsing = browsing
            flushMode()
            require(ProbeCounters.counts["bloomPlay", default: 0] == 4,
                    "Switching to \(browsing.rawValue) played \(ProbeCounters.counts["bloomPlay", default: 0]) rings instead of four")
            ProbeCounters.reset()
            modeDriver.synchronizeAgain()
            flushMode()
            require(ProbeCounters.counts["bloomPlay", default: 0] == 0
                    && ProbeCounters.counts["action.reset", default: 0] == 0,
                    "Synchronizing an existing host reset or replayed the entrance")
        }
        for reference in modeDriver.allPanels {
            if let panel = reference.panel {
                precondition(!panel.isVisible)
                panel.close()
            }
        }
        model.onOpenChange = nil
        if CommandLine.arguments[2] == "check" {
            let offscreenUpdates = openings.reduce(0) { $0 + $1.counts["offscreenBloomBody", default: 0] }
            require(offscreenUpdates == 0,
                    "Warm openings invalidated \(offscreenUpdates) unchanged offscreen ring bodies")
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
        window.close()
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
        "Model.swift", "ClotheslinePreferences.swift", "PinchClassifier.swift", "Services.swift", "PanelAlertPresenter.swift", "IconEntrance.swift", "PagingMotion.swift",
    )]
    sources += sorted((root / "Sources").glob("AppLibrary*.swift"))
    sources += sorted((root / "Sources").glob("EntranceMotion.swift"))
    # Compile one source snapshot even while independent fixes are being edited.
    for index, source in enumerate(sources):
        snapshot = directory / source.name
        snapshot.write_text(source.read_text())
        sources[index] = snapshot
    subprocess.run([
        "swiftc", "-swift-version", "5", "-O", "-module-cache-path", "/tmp/pinchpad-build-module-cache",
        *map(str, sources), str(isolated_model), str(isolated_view), str(probe), "-lsqlite3", "-o", str(binary),
    ], check=True)
    modes = ("paged", "window") if arguments.mode == "both" else (arguments.mode,)
    status = 0
    for mode in modes:
        result = subprocess.run([
            str(binary), str(directory), "check" if arguments.check else "measure", str(arguments.cycles), mode, str(arguments.apps),
        ], text=True, capture_output=True)
        print(result.stdout, end="")
        print(result.stderr, end="")
        status = status or result.returncode
    raise SystemExit(status)
