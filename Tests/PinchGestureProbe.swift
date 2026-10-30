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
            if CommandLine.arguments.contains("--calibration-only") {
                try naturalGestureCalibration()
            } else {
                try run()
            }
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
        try naturalGestureCalibration()
        try incidentalMotion()
        try briefThreeFingerContraction()
        try confirmationTiming()
        try sensitivityLevels()
        try sensitivityPreferences()
        try liveSensitivity()
        try independentSensitivities()
        for sensitivity in PinchSensitivity.allCases {
            try systemGesturePassThrough(sensitivity: sensitivity)
        }
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
            _ = classifier.feed(touches(radius: initial), at: 0) { [3, 4].contains($0) }
            _ = classifier.feed(touches(radius: initial), at: 0.01) { [3, 4].contains($0) }
            let detected = settled(&classifier, fingers: fingers, radius: final, at: 0.02)
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

    static func incidentalMotion() throws {
        for fingers in [3, 4] {
            var classifier = PinchClassifier()
            func touches(radius: Float) -> [TouchSample] {
                (0..<fingers).map { index in
                    let angle = Float(index) * 2 * .pi / Float(fingers)
                    return TouchSample(id: Int32(index), state: 4,
                                       x: 0.5 + radius * cos(angle),
                                       y: 0.5 + radius * sin(angle))
                }
            }
            _ = classifier.feed(touches(radius: 0.3)) { [3, 4].contains($0) }
            _ = classifier.feed(touches(radius: 0.3)) { [3, 4].contains($0) }
            for _ in 0..<20 {
                let signal = classifier.feed(touches(radius: 0.265)) { [3, 4].contains($0) }
                try require(signal == nil, "Small \(fingers)-finger contraction unexpectedly opens a panel")
            }
        }
        print("PASS: incidental finger contraction does not open a panel")
    }

    static func samples(fingers: Int, radius: Float, x: Float = 0.5, y: Float = 0.5) -> [TouchSample] {
        (0..<fingers).map { index in
            let angle = Float(index) * 2 * .pi / Float(fingers)
            return TouchSample(id: Int32(index), state: 4,
                               x: x + radius * cos(angle), y: y + radius * sin(angle))
        }
    }

    typealias GestureFrame = (time: TimeInterval, touches: [TouchSample])

    static func ramp(fingers: Int, movement: Float, duration: TimeInterval,
                     frequency: Double, anchoredThumb: Bool = false) -> [GestureFrame] {
        let steps = Int(ceil(duration * frequency))
        let initial = samples(fingers: fingers, radius: 0.3)
        var frames: [GestureFrame] = [(0, initial), (1 / frequency, initial)]
        for step in 1...steps {
            let radius = 0.3 - movement * Float(step) / Float(steps)
            var touches = samples(fingers: fingers, radius: radius)
            if anchoredThumb { touches[0] = initial[0] }
            frames.append((Double(step + 1) / frequency, touches))
        }
        frames.append((Double(steps + 2) / frequency, []))
        return frames
    }

    static func detected(_ frames: [GestureFrame], sensitivity: PinchSensitivity) -> [PinchSignal] {
        var classifier = PinchClassifier(sensitivity: sensitivity)
        return frames.compactMap { frame in
            classifier.feed(frame.touches, at: frame.time) { [3, 4].contains($0) }
        }
    }

    static func naturalGestureCalibration() throws {
        var failures: [String] = []
        for fingers in [3, 4] {
            for frequency in [60.0, 120.0] {
                let quick = ramp(fingers: fingers, movement: 0.08, duration: 0.08, frequency: frequency)
                if detected(quick, sensitivity: .standard) != [.open] {
                    failures.append("Standard misses a natural \(fingers)-finger quick pinch at \(Int(frequency))Hz")
                }
                let clear = ramp(fingers: fingers, movement: 0.1, duration: 0.15, frequency: frequency)
                if detected(clear, sensitivity: .veryLow) != [.open] {
                    failures.append("Very low misses a clear \(fingers)-finger pinch without an extra hold")
                }
                let comfortable = ramp(fingers: fingers, movement: 0.065, duration: 0.2, frequency: frequency)
                if detected(comfortable, sensitivity: .veryLow) != [.open] {
                    failures.append("Very low requires an excessive \(fingers)-finger travel distance")
                }
                for sensitivity in PinchSensitivity.allCases {
                    var staggered = ramp(fingers: fingers, movement: 0.1, duration: 0.12, frequency: frequency)
                    for index in 0..<(fingers - 1) {
                        staggered[index].touches = Array(staggered[index].touches.prefix(index + 1))
                    }
                    for index in (staggered.count - 4)..<(staggered.count - 1) {
                        staggered[index].touches.removeFirst()
                    }
                    if detected(staggered, sensitivity: sensitivity) != [.open] {
                        failures.append("\(sensitivity) misses a \(fingers)-finger pinch with staggered landing/lifting")
                    }
                    for anchoredThumb in [false, true] {
                        for duration in [0.12, 0.3] {
                            let trace = ramp(fingers: fingers, movement: 0.1, duration: duration,
                                             frequency: frequency, anchoredThumb: anchoredThumb)
                            if detected(trace, sensitivity: sensitivity) != [.open] {
                                failures.append("\(sensitivity) misses a clear \(fingers)-finger pinch (anchored thumb: \(anchoredThumb), \(duration)s)")
                            }
                        }
                    }
                    for pulseFrames in [1, 2] {
                        var pulse: [GestureFrame] = [
                            (0, samples(fingers: fingers, radius: 0.3)),
                            (1 / frequency, samples(fingers: fingers, radius: 0.3))
                        ]
                        for frame in 0..<pulseFrames {
                            pulse.append((Double(frame + 2) / frequency, samples(fingers: fingers, radius: 0.19)))
                        }
                        pulse.append((Double(pulseFrames + 2) / frequency, samples(fingers: fingers, radius: 0.3)))
                        pulse.append((Double(pulseFrames + 3) / frequency, []))
                        if !detected(pulse, sensitivity: sensitivity).isEmpty {
                            failures.append("\(sensitivity) triggers on a \(pulseFrames)-frame impulse at \(Int(frequency))Hz")
                        }
                    }
                    var jitter: [GestureFrame] = [(0, samples(fingers: fingers, radius: 0.3))]
                    for frame in 1...30 {
                        let radius: Float = frame.isMultiple(of: 2) ? 0.305 : 0.295
                        jitter.append((Double(frame) / frequency, samples(fingers: fingers, radius: radius)))
                    }
                    jitter.append((31 / frequency, []))
                    if !detected(jitter, sensitivity: sensitivity).isEmpty {
                        failures.append("\(sensitivity) triggers on resting-finger jitter")
                    }
                }
            }
            let impulse: [GestureFrame] = [
                (0, samples(fingers: fingers, radius: 0.3)),
                (0.01, samples(fingers: fingers, radius: 0.3)),
                (0.02, samples(fingers: fingers, radius: 0.19)),
                (0.028, samples(fingers: fingers, radius: 0.3)), (0.04, [])
            ]
            if !detected(impulse, sensitivity: .veryHigh).isEmpty {
                failures.append("Very high still activates on a single-frame \(fingers)-finger impulse")
            }
        }
        try require(failures.isEmpty, failures.joined(separator: "\n"))
        print("PASS: quick/slow pinches, anchored thumbs and impulse/jitter rejection across all presets at 60/120Hz")
    }

    static func settled(_ classifier: inout PinchClassifier, fingers: Int, radius: Float,
                        at start: TimeInterval) -> PinchSignal? {
        var detected: PinchSignal?
        for frame in 0...30 {
            if let signal = classifier.feed(samples(fingers: fingers, radius: radius),
                                            at: start + Double(frame) / 120, tracked: { [3, 4].contains($0) }) {
                detected = signal
            }
        }
        return detected
    }

    static func confirmationTiming() throws {
        for fingers in [3, 4] {
            for sensitivity in PinchSensitivity.allCases {
                var classifier = PinchClassifier(sensitivity: sensitivity)
                // Settle the contact count before measuring movement confirmation.
                _ = classifier.feed(samples(fingers: fingers, radius: 0.3), at: -0.05) { [3, 4].contains($0) }
                _ = classifier.feed(samples(fingers: fingers, radius: 0.3), at: 0.01) { [3, 4].contains($0) }
                let first = classifier.feed(samples(fingers: fingers, radius: 0.19), at: 0.02) { [3, 4].contains($0) }
                let duration = sensitivity.confirmationDuration
                try require(duration >= 0.02 && duration <= 0.03,
                            "Every preset needs basic debounce without requiring a long hold")
                try require(first == nil, "\(sensitivity) activates before confirming the movement")
                let early = classifier.feed(samples(fingers: fingers, radius: 0.19), at: 0.02 + duration - 0.001) { [3, 4].contains($0) }
                try require(early == nil, "Confirmation completes too early")
                let confirmed = classifier.feed(samples(fingers: fingers, radius: 0.19), at: 0.02 + duration + 0.001) { [3, 4].contains($0) }
                try require(confirmed == .open, "A sustained pinch must trigger after confirmation")
            }

            var interrupted = PinchClassifier(sensitivity: .low)
            _ = interrupted.feed(samples(fingers: fingers, radius: 0.3), at: 0) { [3, 4].contains($0) }
            _ = interrupted.feed(samples(fingers: fingers, radius: 0.19), at: 0.01) { [3, 4].contains($0) }
            _ = interrupted.feed(samples(fingers: fingers, radius: 0.3), at: 0.02) { [3, 4].contains($0) }
            _ = interrupted.feed(samples(fingers: fingers, radius: 0.19), at: 0.025) { [3, 4].contains($0) }
            let rebound = interrupted.feed(samples(fingers: fingers, radius: 0.19), at: 0.04) { [3, 4].contains($0) }
            try require(rebound == nil, "Separate short contractions must not accumulate confirmation time")
            let sustained = interrupted.feed(samples(fingers: fingers, radius: 0.19), at: 0.05) { [3, 4].contains($0) }
            try require(sustained == .open, "A stable contraction after a rebound must still activate")

            var fluid = PinchClassifier()
            _ = fluid.feed(samples(fingers: fingers, radius: 0.3), at: -0.05) { [3, 4].contains($0) }
            _ = fluid.feed(samples(fingers: fingers, radius: 0.3), at: 0.005) { [3, 4].contains($0) }
            let partial = fluid.feed(samples(fingers: fingers, radius: 0.27), at: 0.01) { [3, 4].contains($0) }
            try require(partial == nil, "Partial movement must not meet the standard amplitude threshold")
            let complete = fluid.feed(samples(fingers: fingers, radius: 0.255), at: 0.035) { [3, 4].contains($0) }
            try require(complete == .open, "Confirmation must accumulate during movement, without a post-pinch hold")
        }
        print("PASS: confirmation timing, rebound cancellation and sustained pinches at every sensitivity")
    }

    static func briefThreeFingerContraction() throws {
        for sensitivity in PinchSensitivity.allCases {
            let monitor = PinchMonitor()
            monitor.setSensitivities(three: sensitivity, four: sensitivity)
            var openings = 0
            monitor.onOpen = { _ in openings += 1 }
            monitor.handle(samples: samples(fingers: 3, radius: 0.3))
            monitor.handle(samples: samples(fingers: 3, radius: 0.3))
            monitor.handle(samples: samples(fingers: 3, radius: 0.19))
            monitor.handle(samples: samples(fingers: 3, radius: 0.3))
            monitor.handle(samples: [])
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            try require(openings == 0,
                        "Brief three-finger contraction still opens the tray at \(sensitivity) sensitivity")
        }
        print("PASS: every preset filters brief three-finger contractions in the real monitor path")
    }

    static func sensitivityLevels() throws {
        let motions: [(Float, PinchSensitivity)] = [
            (0.033, .veryHigh), (0.039, .high), (0.047, .standard),
            (0.054, .low), (0.065, .veryLow)
        ]
        for fingers in [3, 4] {
            for sensitivity in PinchSensitivity.allCases {
                for signal in [PinchSignal.open, .close] {
                    for (movement, minimumSensitivity) in motions {
                        var classifier = PinchClassifier(sensitivity: sensitivity)
                        // Presets now measure proportional spread, in both directions.
                        let start: Float = 0.3
                        let end = start + (signal == .open ? -movement : movement)
                        let expected: PinchSignal? = sensitivity.rawValue >= minimumSensitivity.rawValue ? signal : nil
                        for cycle in 0..<2 {
                            let time = Double(cycle)
                            _ = classifier.feed(samples(fingers: fingers, radius: start), at: time) { [3, 4].contains($0) }
                            _ = classifier.feed(samples(fingers: fingers, radius: start), at: time + 0.01) { [3, 4].contains($0) }
                            let detected = settled(&classifier, fingers: fingers, radius: end, at: time + 0.02)
                            try require(detected == expected,
                                        "\(fingers)-finger \(signal), \(sensitivity), movement \(movement): unexpected trigger")
                            _ = classifier.feed([], at: time + 0.5) { [3, 4].contains($0) }
                            try require(classifier.sensitivity == sensitivity, "Lifting fingers resets sensitivity")
                        }
                    }
                }

                var swipe = PinchClassifier(sensitivity: sensitivity)
                _ = swipe.feed(samples(fingers: fingers, radius: 0.2)) { [3, 4].contains($0) }
                let translated = swipe.feed(samples(fingers: fingers, radius: 0.2, x: 0.65, y: 0.6)) { [3, 4].contains($0) }
                try require(translated == nil && swipe.kind == .swipe, "Translation is mistaken for a pinch")
                let afterSwipe = swipe.feed(samples(fingers: fingers, radius: 0.05, x: 0.65, y: 0.6)) { [3, 4].contains($0) }
                try require(afterSwipe == nil, "A swipe becomes a pinch partway through")
            }
        }
        print("PASS: all five sensitivity levels, both directions, three/four fingers, rearming and swipe rejection")
    }

    static func sensitivityPreferences() throws {
        let decoder = JSONDecoder()
        func decode(_ json: String) throws -> Preferences {
            try decoder.decode(Preferences.self, from: Data(json.utf8))
        }
        let legacy = try decode(#"{"columns":9,"pinchThree":false,"pinchFour":true}"#)
        try require(legacy.pinchThreeSensitivity == .standard && legacy.pinchFourSensitivity == .standard
                    && legacy.columns == 9 && !legacy.pinchThree && legacy.pinchFour,
                    "Missing levels must default without losing existing preferences")
        for level in PinchSensitivity.allCases {
            let migrated = try decode("{\"pinchSensitivity\":\(level.rawValue)}")
            try require(migrated.pinchThreeSensitivity == level && migrated.pinchFourSensitivity == level,
                        "Shared sensitivity must migrate to both gestures")
        }
        let partial = try decode(#"{"pinchSensitivity":4,"pinchThreeSensitivity":1}"#)
        try require(partial.pinchThreeSensitivity == .veryLow && partial.pinchFourSensitivity == .high,
                    "New keys must take precedence; a missing key inherits the old setting")
        let unknown = try decode(#"{"columns":9,"pinchThreeSensitivity":999,"pinchFourSensitivity":5}"#)
        try require(unknown.pinchThreeSensitivity == .standard && unknown.pinchFourSensitivity == .veryHigh
                    && unknown.columns == 9, "Unknown level must not discard other preferences")
        let invalidLegacy = try decode(#"{"pinchSensitivity":999}"#)
        try require(invalidLegacy.pinchThreeSensitivity == .standard && invalidLegacy.pinchFourSensitivity == .standard,
                    "Invalid legacy levels must use standard")
        for three in PinchSensitivity.allCases {
            for four in PinchSensitivity.allCases {
                var preferences = legacy
                preferences.pinchThreeSensitivity = three
                preferences.pinchFourSensitivity = four
                let data = try JSONEncoder().encode(preferences)
                let restored = try decoder.decode(Preferences.self, from: data)
                try require(restored == preferences, "Independent levels are lost after saving and reopening")
                let keys = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                try require(keys["pinchSensitivity"] == nil, "Saving must not reintroduce an ambiguous shared level")
            }
        }
        print("PASS: 25 independent sensitivity pairs, legacy migration, partial keys and invalid-level fallback")
    }

    static func independentSensitivities() throws {
        let monitor = PinchMonitor()
        var openings: [Int] = []
        monitor.onOpen = { openings.append($0) }
        var time = 0.0
        // Exercise the actual monitor callback with opposite levels, then swap live.
        for three in [PinchSensitivity.veryHigh, .veryLow] {
            let four: PinchSensitivity = three == .veryHigh ? .veryLow : .veryHigh
            monitor.setSensitivities(three: three, four: four)
            for _ in 0..<2 {
                for count in [3, 4] {
                    openings.removeAll()
                    monitor.handle(samples: samples(fingers: count, radius: 0.3), at: time)
                    monitor.handle(samples: samples(fingers: count, radius: 0.3), at: time + 0.01)
                    for frame in 0...30 {
                        monitor.handle(samples: samples(fingers: count, radius: 0.265), at: time + 0.02 + Double(frame) / 120)
                    }
                    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                    let level = count == 3 ? three : four
                    try require(openings == (level == .veryHigh ? [count] : []),
                                "Changing one finger count affects the other's threshold")
                    monitor.handle(samples: [], at: time + 0.4)
                    time += 1
                }
            }
        }
        // A late fourth finger changes the threshold before recognition; lifting
        // it again must retain the four-finger level and routing.
        var classifier = PinchClassifier(threeFingerSensitivity: .veryHigh, fourFingerSensitivity: .veryLow)
        let four = samples(fingers: 4, radius: 0.3)
        _ = classifier.feed(Array(four.prefix(3)), at: 0) { [3, 4].contains($0) }
        _ = classifier.feed(four, at: 0.01) { [3, 4].contains($0) }
        for frame in 0...20 {
            let reduced = Array(samples(fingers: 4, radius: 0.265).prefix(frame < 5 ? 4 : 3))
            let result = classifier.feed(reduced, at: 0.02 + Double(frame) / 120) { [3, 4].contains($0) }
            try require(result == nil && classifier.sensitivity == .veryLow,
                        "A four-finger gesture borrowed the three-finger threshold after contact changes")
        }
        classifier.reset()
        try require(classifier.threeFingerSensitivity == .veryHigh && classifier.fourFingerSensitivity == .veryLow,
                    "Reset lost independent sensitivity values")
        print("PASS: independent live callbacks, rearming, fourth-finger landing and lift-off thresholds")
    }

    static func liveSensitivity() throws {
        for fingers in [3, 4] {
            let monitor = PinchMonitor()
            var openings: [Int] = []
            monitor.onOpen = { openings.append($0) }
            monitor.setSensitivities(three: .veryHigh, four: .veryHigh)
            monitor.handle(samples: samples(fingers: fingers, radius: 0.3), at: 0)
            monitor.handle(samples: samples(fingers: fingers, radius: 0.3), at: 0.01)
            // Change the setting during a contact sequence, without installing any monitors.
            monitor.setSensitivities(three: .veryLow, four: .veryLow)
            monitor.handle(samples: samples(fingers: fingers, radius: 0.3), at: 0.02)
            monitor.handle(samples: samples(fingers: fingers, radius: 0.3), at: 0.03)
            for frame in 0...30 {
                monitor.handle(samples: samples(fingers: fingers, radius: 0.265), at: 0.04 + Double(frame) / 120)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            try require(openings.isEmpty, "Lowering sensitivity does not immediately filter small movements")
            for frame in 0...30 {
                monitor.handle(samples: samples(fingers: fingers, radius: 0.2), at: 0.4 + Double(frame) / 120)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            try require(openings == [fingers], "A clear pinch must still reach the panel callback at low sensitivity")
        }
        print("PASS: live sensitivity changes reach actual gesture callbacks without device hooks")
    }

    static func systemGesturePassThrough(sensitivity: PinchSensitivity) throws {
        func preparedMonitor(expanding: Bool) -> PinchMonitor {
            let monitor = PinchMonitor()
            monitor.setSensitivities(three: sensitivity, four: sensitivity)
            func samples(radius: Float) -> [TouchSample] {
                (0..<4).map { index in
                    let angle = Float(index) * .pi / 2
                    return TouchSample(id: Int32(index), state: 4,
                                       x: 0.5 + radius * cos(angle),
                                       y: 0.5 + radius * sin(angle))
                }
            }
            let initial: Float = expanding ? 0.1 : 0.3
            monitor.handle(samples: samples(radius: initial), at: 0)
            monitor.handle(samples: samples(radius: initial), at: 0.01)
            for frame in 0...30 {
                monitor.handle(samples: samples(radius: expanding ? 0.3 : 0.1), at: 0.02 + Double(frame) / 120)
            }
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

        let missingEnd = PinchMonitor()
        missingEnd.handle(samples: samples(fingers: 4, radius: 0.3), at: 0)
        missingEnd.handle(samples: samples(fingers: 4, radius: 0.3), at: 0.01)
        let began = dockEvent(motion: 3)
        try require(missingEnd.shouldSwallow(type: began.type, event: began),
                    "A configured inward Dock gesture must begin interception")
        missingEnd.handle(samples: [], at: 0.02)
        missingEnd.handle(samples: samples(fingers: 2, radius: 0.2), at: 0.2)
        try require(!missingEnd.shouldSwallow(type: generic.type, event: generic),
                    "A missing Dock end event leaks suppression into a new two-finger gesture")
        print("PASS: a fresh contact sequence clears stale system gesture suppression")

        let contactDropout = preparedMonitor(expanding: false)
        contactDropout.handle(samples: [], at: 0.28)
        try require(!contactDropout.shouldSwallow(type: generic.type, event: generic),
                    "A released contact sequence keeps swallowing generic gesture events")
        contactDropout.handle(samples: samples(fingers: 4, radius: 0.1), at: 0.29)
        try require(contactDropout.shouldSwallow(type: generic.type, event: generic),
                    "A brief sensor dropout loses the already-recognized inward gesture")
        print("PASS: brief sensor gaps preserve recognition without swallowing released input")
    }
}
