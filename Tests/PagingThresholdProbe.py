"""Replay the production swipe handlers with synthetic events, without windows.

Run: python3 Tests/PagingThresholdProbe.py
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


source = (root / "Sources/AppMain.swift").read_text()
handlers = "\n".join(block(source, marker).replace("NSEvent", "ScrollEvent") for marker in (
    "private func handlePageSwipe(_ event: NSEvent)", "private func settleSwipe(",
))
harness = r'''import AppKit
import SwiftUI

@MainActor final class AppModel {
    enum Browsing { case paged, scroll }
    struct Settings { var browsing: Browsing = .paged }
    static let shared = AppModel()
    var settings = Settings()
    var openFolderID: UUID?
    var query = ""
    var draggingID: String?
    var pages = Array(0..<5)
    var clampedPage = 2
    let paging = PagingMotion()
    func turnPage(_ delta: Int) { clampedPage = max(0, min(pages.count - 1, clampedPage + delta)) }
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
@MainActor final class Driver {
    var panel: NSWindow?
    var swipeAccum: CGFloat = 0
    var swipeSamples: [(TimeInterval, CGFloat)] = []
    var swipeIdleWork: DispatchWorkItem?
    func feed(_ x: CGFloat, _ phase: ScrollEvent.Phase, at time: TimeInterval) {
        _ = handlePageSwipe(ScrollEvent(scrollingDeltaX: x, phase: phase, timestamp: time))
    }
''' + handlers + r'''
}
@main struct Probe {
    @MainActor static func main() {
        let model = AppModel.shared
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }
        func replay(width: CGFloat, distance: CGFloat, duration: Double, cancelled: Bool = false,
                    start: Int = 2, pause: Bool = false) -> Int {
            let driver = Driver()
            model.clampedPage = start
            model.paging.offset = 0
            model.paging.isSwiping = false
            model.paging.interruptedSettlement = false
            model.paging.presentation.record(position: -CGFloat(start) * width, pageWidth: width)
            driver.feed(0, .began, at: 1)
            let steps = 12
            for step in 1...steps {
                driver.feed(distance / CGFloat(steps), .changed, at: 1 + duration * Double(step) / Double(steps))
            }
            driver.feed(0, cancelled ? .cancelled : .ended, at: 1 + duration + (pause ? 0.2 : 0.008))
            check(!model.paging.isSwiping && model.paging.offset == 0, "Gesture did not settle")
            check(driver.swipeIdleWork == nil, "Gesture left an idle callback scheduled")
            return model.clampedPage
        }
        for width: CGFloat in [600, 1024, 1440, 2560] {
            for direction: CGFloat in [-1, 1] {
                let destination = 2 - Int(direction)
                check(replay(width: width, distance: direction * 64, duration: 0.42, pause: true) == destination,
                      "Slow 64-point swipe failed on a \(Int(width))-point page (direction \(direction))")
                check(replay(width: width, distance: direction * 28, duration: 0.055) == destination,
                      "Short deliberate flick failed on a \(Int(width))-point page")
                check(replay(width: width, distance: direction * 10, duration: 0.3) == 2,
                      "Incidental movement turned a page")
                check(replay(width: width, distance: direction * 8, duration: 0.008) == 2,
                      "Brief input jitter turned a page")
                check(replay(width: width, distance: direction * 64, duration: 0.42, cancelled: true) == 2,
                      "Cancelled swipe turned a page")
            }
            check(replay(width: width, distance: 64, duration: 0.42, start: 0) == 0, "Overscrolled first page")
            check(replay(width: width, distance: -64, duration: 0.42, start: 4) == 4, "Overscrolled last page")
        }
        for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
        if !failures.isEmpty { exit(1) }
        print("PASS: short slow swipes and deliberate flicks turn one page at all widths; jitter, cancellation and edges stay stable")
    }
}
'''
with tempfile.TemporaryDirectory(prefix="pinchpad-paging-threshold-") as directory:
    directory = Path(directory)
    probe = directory / "Probe.swift"
    probe.write_text(harness)
    binary = directory / "probe"
    subprocess.run(["swiftc", "-swift-version", "5", "-O", "-module-cache-path", "/tmp/pinchpad-build-module-cache",
                    str(root / "Sources/PagingMotion.swift"), str(probe), "-o", str(binary)], check=True, timeout=60)
    result = subprocess.run([str(binary)], text=True, capture_output=True, timeout=15)
    print(result.stdout, end="")
    print("\n".join(line for line in result.stderr.splitlines() if line.startswith("FAIL:")))
    raise SystemExit(result.returncode)
