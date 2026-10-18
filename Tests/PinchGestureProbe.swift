import AppKit
import Foundation

// No device hooks, permissions, or running app needed:
// swiftc -swift-version 5 Sources/Model.swift Sources/PinchClassifier.swift \
//   Sources/Services.swift Tests/PinchGestureProbe.swift -lsqlite3 \
//   -o /tmp/PinchGestureProbe && /tmp/PinchGestureProbe
@main
struct PinchGestureProbe {
    static func main() {
        do {
            try run()
        } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw NSError(domain: "PinchGestureProbe", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    static func run() throws {
        try systemGesturePassThrough()
        let monitor = PinchMonitor()
        var trayOpen = false
        var launcherOpen = false
        monitor.bindPanels(
            openTray: { trayOpen = true; launcherOpen = false },
            closeTray: { trayOpen = false },
            openLauncher: { launcherOpen = true; trayOpen = false },
            closeLauncher: { launcherOpen = false }
        )

        func replay(fingers: Int, signal: PinchSignal) throws {
            var classifier = PinchClassifier()
            func touches(radius: Float) -> [TouchSample] {
                (0..<fingers).map { index in
                    let angle = Float(index) * 2 * .pi / Float(fingers)
                    return TouchSample(id: Int32(index), state: 4,
                                       x: 0.5 + radius * cos(angle),
                                       y: 0.5 + radius * sin(angle))
                }
            }
            let initial: Float = signal == .open ? 0.3 : 0.1
            let final: Float = signal == .open ? 0.1 : 0.3
            _ = classifier.feed(touches(radius: initial)) { [3, 4].contains($0) }
            _ = classifier.feed(touches(radius: initial)) { [3, 4].contains($0) }
            let detected = classifier.feed(touches(radius: final)) { [3, 4].contains($0) }
            try require(detected == signal, "\(fingers)-finger \(signal) was not recognized")
            if detected == .open {
                monitor.onOpen?(classifier.peak)
            } else {
                monitor.onClose?(classifier.peak)
            }
        }

        try replay(fingers: 4, signal: .open)
        try require(launcherOpen && !trayOpen, "Four-finger pinch must open the launcher")
        try replay(fingers: 4, signal: .close)
        try require(!launcherOpen && !trayOpen, "Four-finger spread must close the launcher")
        print("PASS: four-finger launcher open/close")

        try replay(fingers: 3, signal: .open)
        try require(trayOpen && !launcherOpen, "Three-finger pinch must open the tray")
        try replay(fingers: 4, signal: .close)
        try require(!trayOpen && !launcherOpen,
                    "Four-finger spread leaves the tray open after a three-finger pinch")
        print("PASS: four-finger spread closes the tray opened by three fingers")

        try replay(fingers: 3, signal: .open)
        try replay(fingers: 3, signal: .close)
        try require(!trayOpen && !launcherOpen, "Three-finger spread must still close the tray")
        print("PASS: three-finger tray open/close")

        try replay(fingers: 4, signal: .open)
        try replay(fingers: 3, signal: .close)
        try require(!trayOpen && !launcherOpen,
                    "Spreading must close the visible panel even if one finger is not tracked")
        print("PASS: closing targets the visible panel, not the original finger count")
    }

    static func systemGesturePassThrough() throws {
        func preparedMonitor(expanding: Bool) -> PinchMonitor {
            let monitor = PinchMonitor()
            func samples(radius: Float) -> [TouchSample] {
                (0..<4).map { index in
                    let angle = Float(index) * .pi / 2
                    return TouchSample(id: Int32(index), state: 4,
                                       x: 0.5 + radius * cos(angle),
                                       y: 0.5 + radius * sin(angle))
                }
            }
            let initial: Float = expanding ? 0.1 : 0.3
            monitor.handle(samples: samples(radius: initial))
            monitor.handle(samples: samples(radius: initial))
            monitor.handle(samples: samples(radius: expanding ? 0.3 : 0.1))
            return monitor
        }
        func dockEvent(motion: Int64, phase: Int64 = 1) -> CGEvent {
            let event = CGEvent(source: nil)!
            event.type = CGEventType(rawValue: 30)!
            event.setIntegerValueField(CGEventField(rawValue: 110)!, value: 23)
            event.setIntegerValueField(CGEventField(rawValue: 123)!, value: motion)
            event.setIntegerValueField(CGEventField(rawValue: 132)!, value: phase)
            return event
        }

        // Captured from the user's system Show Desktop gesture: motion 5,
        // phase 0. Replay the actual event shape without posting system input.
        let spread = preparedMonitor(expanding: true)
        let showDesktop = dockEvent(motion: 5, phase: 0)
        try require(!spread.shouldSwallow(type: showDesktop.type, event: showDesktop),
                    "System Show Desktop event is swallowed after a four-finger spread")
        let generic = CGEvent(source: nil)!
        generic.type = CGEventType(rawValue: 29)!
        try require(!spread.shouldSwallow(type: generic.type, event: generic),
                    "Low-level events for an outward spread must reach macOS")
        print("PASS: system Show Desktop and outward gesture events pass through")

        let pinch = preparedMonitor(expanding: false)
        let launchpad = dockEvent(motion: 3)
        try require(pinch.shouldSwallow(type: launchpad.type, event: launchpad),
                    "Inward pinch must still suppress the system app launcher")
        let unknown = dockEvent(motion: 99)
        try require(!pinch.shouldSwallow(type: unknown.type, event: unknown),
                    "Unrelated Dock gestures must not inherit pinch suppression")
        print("PASS: only the app-launcher pinch is intercepted")

        for motion: Int64 in [1, 2] {
            let swipe = dockEvent(motion: motion)
            try require(!preparedMonitor(expanding: false).shouldSwallow(type: swipe.type, event: swipe),
                        "System horizontal/vertical swipes must remain available")
        }
        print("PASS: system horizontal and vertical swipes pass through")
    }
}
