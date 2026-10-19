import AppKit
import Foundation

// No system input is posted and no windows are displayed.
// swiftc -swift-version 5 Sources/Model.swift Sources/PinchClassifier.swift \
//   Sources/Services.swift Sources/LauncherPanelVisibility.swift \
//   Tests/IdleResponsivenessProbe.swift -lsqlite3 -o /tmp/IdleResponsivenessProbe
@main
struct IdleResponsivenessProbe {
    final class SourceObservation {
        let scheduled = DispatchSemaphore(value: 0)
        let delivered = DispatchSemaphore(value: 0)
        var runLoop: CFRunLoop?
        var deliveredOnMain = false
    }

    final class ProbePanel: NSPanel {
        var onScreen = true
        override var isVisible: Bool { onScreen }
        override func orderOut(_ sender: Any?) { onScreen = false }
    }

    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else {
            throw NSError(domain: "IdleResponsivenessProbe", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    static func source(observing observation: SourceObservation) -> CFRunLoopSource {
        var context = CFRunLoopSourceContext()
        context.info = Unmanaged.passRetained(observation).toOpaque()
        context.release = { info in
            if let info { Unmanaged<SourceObservation>.fromOpaque(info).release() }
        }
        context.schedule = { info, runLoop, _ in
            guard let info else { return }
            let observation = Unmanaged<SourceObservation>.fromOpaque(info).takeUnretainedValue()
            observation.runLoop = runLoop
            observation.scheduled.signal()
        }
        context.perform = { info in
            guard let info else { return }
            let observation = Unmanaged<SourceObservation>.fromOpaque(info).takeUnretainedValue()
            observation.deliveredOnMain = Thread.isMainThread
            observation.delivered.signal()
        }
        return CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context)!
    }

    static func waitForInvalidation(_ source: CFRunLoopSource) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.5
        while CFRunLoopSourceIsValid(source), ProcessInfo.processInfo.systemUptime < deadline {
            usleep(1_000)
        }
        return !CFRunLoopSourceIsValid(source)
    }

    static func checkInputLoop() throws {
        try require(Thread.isMainThread, "Probe must stall the real main thread")
        let observation = SourceObservation()
        let source = Self.source(observing: observation)
        let worker = EventTapRunLoop(source: source)
        defer { worker.stop() }
        try require(observation.scheduled.wait(timeout: .now() + 0.5) == .success,
                    "Input source was not scheduled")
        for _ in 0..<3 {
            CFRunLoopSourceSignal(source)
            CFRunLoopWakeUp(observation.runLoop)
            // Waiting here deliberately prevents the main run loop from running.
            try require(observation.delivered.wait(timeout: .now() + 0.2) == .success,
                        "Input handling stalls while the UI main thread is busy")
            try require(!observation.deliveredOnMain, "Input callback still runs on the UI thread")
        }
        worker.stop()
        worker.stop()
        try require(waitForInvalidation(source), "Stopping leaves a live input source behind")
        CFRunLoopSourceSignal(source)
        CFRunLoopWakeUp(observation.runLoop)
        try require(observation.delivered.wait(timeout: .now() + 0.03) == .timedOut,
                    "Stopped input source still handles callbacks")
        print("PASS: input remains responsive while the UI thread is blocked; stop is idempotent")

        for _ in 0..<30 {
            let observation = SourceObservation()
            let source = Self.source(observing: observation)
            var worker: EventTapRunLoop? = EventTapRunLoop(source: source)
            worker?.stop()
            worker = nil
            try require(waitForInvalidation(source), "Immediate stop/release leaks an input source")
        }
        let releasedSource = Self.source(observing: SourceObservation())
        autoreleasepool { _ = EventTapRunLoop(source: releasedSource) }
        try require(waitForInvalidation(releasedSource), "Releasing the worker leaks its run loop")
        print("PASS: immediate shutdown and deinitialization release input sources")
    }

    @MainActor
    static func checkHiddenPanel() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        for style: NSWindow.StyleMask in [[], [.titled, .closable]] {
            let panel = ProbePanel(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                                   styleMask: style, backing: .buffered, defer: true)
            panel.isReleasedWhenClosed = false
            let effect = NSVisualEffectView()
            effect.state = .active
            effect.wantsLayer = true
            panel.contentView = effect
            panel.alphaValue = 0.4
            effect.layer?.opacity = 0
            effect.layer?.transform = CATransform3DMakeScale(0.96, 0.96, 1)
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.duration = 60
            effect.layer?.add(animation, forKey: "test.fade")
            for _ in 0..<2 {
                LauncherPanelVisibility.suspend(panel)
                try require(!panel.isVisible, "Closed launcher remains in the display list")
                try require(panel.ignoresMouseEvents, "Closed launcher still consumes mouse input")
                try require(effect.state == .inactive, "Closed launcher keeps its backdrop effect active")
                try require(panel.alphaValue == 1 && effect.layer?.opacity == 1,
                            "Hidden panel retains stale fade state on reopening")
                try require(effect.layer.map { CATransform3DIsIdentity($0.transform) } == true,
                            "Hidden panel retains a stale zoom transform on reopening")
                try require(effect.layer?.animationKeys()?.isEmpty != false,
                            "Hidden panel retains an active fade animation")
            }
        }
        print("PASS: full-screen and windowed launchers leave the display list and suspend effects")
    }

    @MainActor
    static func main() {
        do {
            if !CommandLine.arguments.contains("--panel-only") { try checkInputLoop() }
            if !CommandLine.arguments.contains("--input-only") { try checkHiddenPanel() }
        } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
