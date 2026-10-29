"""Replay real swipe handlers and SwiftUI translation in an unordered window.

Measures rendered/interpolated position, not just the model's target offset.
Never posts input events, reads another app, or opens a visible window.
Run: python3 Tests/PagingTrajectoryProbe.py
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]

def block(source, marker):
    start = source.index(marker)
    cursor = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[cursor] == "{") - (source[cursor] == "}")
        cursor += 1
    return source[start:cursor]

app = (root / "Sources/AppMain.swift").read_text()
view = (root / "Sources/PinchpadView.swift").read_text()
model = (root / "Sources/AppModel.swift").read_text()
handlers = "\n".join(block(app, marker).replace("NSEvent", "ScrollEvent") for marker in (
    "private func handlePageSwipe(_ event: NSEvent)", "private func settleSwipe(",
))
translation = block(view, "private struct PagingTranslation<")
if "private struct PagingPosition:" in view:
    effect = block(view, "private struct PagingPosition:")
    effect = effect.replace("func effectValue(size: CGSize) -> ProjectionTransform {", "func effectValue(size: CGSize) -> ProjectionTransform {\n        TraceStore.record(position)")
    translation += "\n" + effect
    if "private struct PagingLayoutPosition:" in view:
        translation += "\n" + block(view, "private struct PagingLayoutPosition:")
else:
    translation = translation.replace(".offset(x: -CGFloat(page) * width + paging.offset)", ".modifier(TracePosition(position: -CGFloat(page) * width + paging.offset))")
turn_page = block(model, "func turnPage(_ delta: Int)")
harness = r'''import AppKit
import Combine
import Foundation
import SwiftUI

enum TraceStore {
    static var samples: [CGFloat] = []
    static var latest: CGFloat { samples.last ?? 0 }
    static func record(_ position: CGFloat) { samples.append(position) }
}
struct TracePosition: GeometryEffect {
    var position: CGFloat
    var animatableData: CGFloat { get { position } set { position = newValue } }
    func effectValue(size: CGSize) -> ProjectionTransform {
        TraceStore.record(position)
        return ProjectionTransform(CGAffineTransform(translationX: position, y: 0))
    }
}
@MainActor final class AppModel: ObservableObject {
    enum Browsing { case paged, scroll }
    struct Settings { var browsing: Browsing = .paged }
    static let shared = AppModel()
    var settings = Settings()
    var openFolderID: UUID?
    var query = ""
    var draggingID: String?
    var pages = Array(0..<4)
    @Published var currentPage = 1
    @Published var pageWidth: CGFloat = 600
    @Published var pageDirection = 1
    let paging = PagingMotion()
    var clampedPage: Int { min(max(currentPage, 0), pages.count - 1) }
    func persist() {}
''' + turn_page + r'''
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
@MainActor final class SwipeDriver {
    var panel: NSWindow?
    private var swipeAccum: CGFloat = 0
    private var swipeSamples: [(TimeInterval, CGFloat)] = []
    private var swipeIdleWork: DispatchWorkItem?
    func feed(_ delta: CGFloat, _ phase: ScrollEvent.Phase, at time: TimeInterval) {
        _ = handlePageSwipe(ScrollEvent(scrollingDeltaX: delta, phase: phase, timestamp: time))
    }
''' + handlers + r'''
}
''' + translation + r'''
struct Root: View {
    @ObservedObject var model: AppModel
    var body: some View {
        PagingTranslation(paging: model.paging, page: model.clampedPage, width: model.pageWidth, isDragging: false) {
            HStack(spacing: 0) {
                ForEach(model.pages, id: \.self) { page in
                    Color.blue.opacity(Double(page + 1) / 4).frame(width: model.pageWidth, height: 300)
                }
            }
        }.frame(width: model.pageWidth, height: 300, alignment: .leading).clipped()
    }
}
@main struct Probe {
    @MainActor static func main() { exit(run() ? 0 : 1) }
    @MainActor static func run() -> Bool {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let model = AppModel.shared
        let host = NSHostingView(rootView: Root(model: model))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 500)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        let driver = SwipeDriver()
        driver.panel = window
        var failures: [String] = []
        func require(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }
        func tick(_ seconds: Double = 0.008) {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
            host.layoutSubtreeIfNeeded()
        }
        func run(_ seconds: Double) {
            let end = ProcessInfo.processInfo.systemUptime + seconds
            repeat { tick() } while ProcessInfo.processInfo.systemUptime < end
        }
        func reset() {
            driver.feed(0, .cancelled, at: 0)
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                model.paging.isSwiping = false
                model.paging.offset = 0
                model.currentPage = 1
            }
            run(0.65)
            TraceStore.samples = []
            tick()
        }
        run(0.05)
        reset()
        driver.feed(-240, .began, at: 1)
        driver.feed(-40, .changed, at: 1.1)
        tick()
        driver.feed(0, .cancelled, at: 1.2)
        run(0.65)
        require(model.currentPage == 1, "Cancelled swipe committed a page turn")

        reset()
        driver.feed(-1000, .began, at: 2)
        tick()
        require(abs(model.paging.offset) <= 600.001,
                "Swipe displacement exceeds actual 600-point page stride: \\(model.paging.offset)")

        reset()
        driver.feed(-90, .began, at: 3)
        tick()
        let priorGesture = TraceStore.latest
        driver.feed(0, .began, at: 3.1)
        tick()
        let repeatedBeginJump = abs(TraceStore.latest - priorGesture)
        require(repeatedBeginJump < 8, "New began event snapped existing motion by \\(repeatedBeginJump) points")

        reset()
        driver.feed(-220, .began, at: 4)
        driver.feed(-40, .changed, at: 4.1)
        tick()
        driver.feed(0, .ended, at: 4.2)
        run(0.018)
        let springPosition = TraceStore.latest
        let distinct = Set(TraceStore.samples).count
        require(distinct >= 4, "Fixture did not exercise real interpolated SwiftUI motion")
        driver.feed(0, .began, at: 4.3)
        tick()
        let interruptedJump = abs(TraceStore.latest - springPosition)
        print(String(format: "spring interruption: %.3f -> %.3f, jump %.3f pt; %d interpolated samples", springPosition, TraceStore.latest, interruptedJump, distinct))
        require(interruptedJump < 8, "Taking over a settling spring snapped by \\(interruptedJump) points")
        driver.feed(24, .changed, at: 4.32)
        tick()
        require(abs(TraceStore.latest - (springPosition + 24)) < 8,
                "Reversing after takeover did not follow the finger from its current visual position")

        reset()
        driver.feed(-220, .began, at: 5)
        driver.feed(-40, .changed, at: 5.1)
        tick()
        driver.feed(0, .ended, at: 5.2)
        let halfwayDeadline = ProcessInfo.processInfo.systemUptime + 0.3
        while TraceStore.latest > -1020 && ProcessInfo.processInfo.systemUptime < halfwayDeadline { tick(0.004) }
        require(TraceStore.latest < -1000 && TraceStore.latest > -1198,
                "Fixture did not intercept the second half of a page spring")
        driver.feed(0, .began, at: 5.3)
        tick()
        driver.feed(0, .ended, at: 5.31)
        run(0.65)
        require(model.currentPage == 2, "Touching and releasing a mostly settled page reversed to the previous page without finger movement")

        reset()
        var direct = Transaction(animation: nil)
        direct.disablesAnimations = true
        withTransaction(direct) { model.currentPage = 0 }
        run(0.65)
        driver.feed(120, .began, at: 6)
        tick()
        let edgeBefore = TraceStore.latest
        driver.feed(0, .began, at: 6.1)
        tick()
        require(abs(TraceStore.latest - edgeBefore) < 0.1,
                "Grabbing an existing edge bounce applied resistance twice")
        driver.feed(24, .changed, at: 6.12)
        tick()
        require(abs(TraceStore.latest - edgeBefore - 24 * 0.42) < 0.1,
                "Edge bounce no longer follows the original resistance curve")

        reset()
        model.turnPage(1)
        run(0.08)
        let keyboardBefore = TraceStore.latest
        model.turnPage(-1)
        tick()
        let keyboardJump = abs(TraceStore.latest - keyboardBefore)
        require(keyboardJump < 60, "Keyboard reversal jumps to an endpoint before animating")
        run(0.7)
        require(abs(TraceStore.latest + 600) < 2, "Reversed spring did not settle on its final page")
        model.pageWidth = 700
        tick()
        require(abs(TraceStore.latest + 700) < 1,
                "Resizing the viewport incorrectly starts a page-turn spring")
        require(model.paging.presentation.sample?.pageWidth == 700,
                "Resizing left gesture hit distances at the previous viewport width")
        precondition(!window.isVisible)
        if !failures.isEmpty {
            for failure in failures { fputs("FAIL: \\(failure)\\n", stderr) }
            return false
        }
        print("PASS: actual position stays continuous across repeated began, spring takeover and reversal")
        print("PASS: cancellation returns to its starting page; swipe displacement uses the actual viewport")
        return true
    }
}
'''
harness = harness.replace('\\\\', '\\')
with tempfile.TemporaryDirectory(prefix="pinchpad-paging-trajectory-") as directory:
    directory = Path(directory)
    source = directory / "Probe.swift"
    source.write_text(harness)
    binary = directory / "probe"
    subprocess.run(["swiftc", "-swift-version", "5", "-O", "-module-cache-path", "/tmp/pinchpad-build-module-cache",
                    str(root / "Sources/PagingMotion.swift"), str(source), "-o", str(binary)], check=True)
    result = subprocess.run([str(binary)], text=True, capture_output=True, timeout=30)
    print(result.stdout, end="")
    # Keep platform XPC diagnostics out of the result; preserve assertion failures.
    print("\n".join(line for line in result.stderr.splitlines() if line.startswith("FAIL:")), end="\n")
    raise SystemExit(result.returncode)
