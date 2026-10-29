import Foundation

// In-memory contact traces only. No device hooks, windows, or posted events.
// swiftc Sources/Model.swift Sources/PinchClassifier.swift Sources/Services.swift \
//   Tests/PinchTrajectoryProbe.swift -lsqlite3 -o /tmp/PinchTrajectoryProbe
@main
struct PinchTrajectoryProbe {
    typealias Frame = (time: TimeInterval, touches: [TouchSample])

    static func circle(_ count: Int, radius: Float) -> [TouchSample] {
        (0..<count).map { index in
            let angle = Float(index) * 2 * .pi / Float(count)
            return TouchSample(id: Int32(index), state: 4,
                               x: 0.5 + radius * cos(angle), y: 0.5 + radius * sin(angle))
        }
    }

    static func trace(_ initial: [TouchSample], frequency: Double = 120,
                      duration: Double = 0.16,
                      transform: (TouchSample, Float) -> TouchSample) -> [Frame] {
        let steps = Int(ceil(duration * frequency))
        return [(0, initial)] + (1...steps).map { step in
            (Double(step) / frequency, initial.map { transform($0, Float(step) / Float(steps)) })
        }
    }

    static func detections(_ frames: [Frame], sensitivity: PinchSensitivity = .standard) -> [(PinchSignal, Int)] {
        var classifier = PinchClassifier(sensitivity: sensitivity)
        return frames.compactMap { frame in
            classifier.feed(frame.touches, at: frame.time) { [3, 4].contains($0) }.map { ($0, classifier.peak) }
        }
    }

    static func main() {
        var failures: [String] = []
        func require(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }
        for count in [3, 4] {
            for frequency in [60.0, 120.0] {
                for radius: Float in [0.12, 0.2, 0.3] {
                    for aspect: Float in [0.6, 1, 1.7] {
                        let initial = circle(count, radius: radius).map { touch -> TouchSample in
                            var touch = touch
                            touch.y = 0.5 + (touch.y - 0.5) * aspect
                            return touch
                        }
                        let frames = trace(initial, frequency: frequency) { touch, progress in
                            var touch = touch
                            touch.x = 0.5 + (touch.x - 0.5) * (1 - progress * 0.34)
                            touch.y = 0.5 + (touch.y - 0.5) * (1 - progress * 0.34)
                            return touch
                        }
                        for sensitivity in PinchSensitivity.allCases {
                            let signals = detections(frames, sensitivity: sensitivity)
                            require(signals.count == 1 && signals.first?.0 == .open,
                                    "Missed proportional pinch: \(count) fingers, span \(radius), aspect \(aspect), \(frequency)Hz, \(sensitivity)")
                        }
                    }
                }
                let baseline = circle(count, radius: 0.4)
                let small = trace(baseline, frequency: frequency) { touch, progress in
                    var touch = touch
                    touch.x = 0.5 + (touch.x - 0.5) * (1 - progress * 0.08)
                    touch.y = 0.5 + (touch.y - 0.5) * (1 - progress * 0.08)
                    return touch
                }
                require(detections(small, sensitivity: .veryHigh).isEmpty,
                        "Wide hand's 8% adjustment fires at very high sensitivity (\(count), \(frequency)Hz)")
            }
        }

        let anchored = [TouchSample(id: 0, state: 4, x: 0.2, y: 0.2)]
            + [Float(0.35), 0.5, 0.65].enumerated().map {
                TouchSample(id: Int32($0.offset + 1), state: 4, x: $0.element, y: 0.7)
            }
        let anchoredFrames = trace(anchored) { touch, progress in
            guard touch.id != 0 else { return touch }
            var touch = touch
            touch.x -= 0.12 * progress
            touch.y -= 0.25 * progress
            return touch
        }
        require(detections(anchoredFrames).first?.0 == .open,
                "Anchored thumb with three fingers moving together is rejected")

        let three = circle(3, radius: 0.3)
        let tail = [(0.0, three), (0.01, three)] + trace(Array(three.prefix(2))) { touch, progress in
            var touch = touch
            touch.x = 0.5 + (touch.x - 0.5) * (1 - progress * 0.6)
            touch.y = 0.5 + (touch.y - 0.5) * (1 - progress * 0.6)
            return touch
        }.map { ($0.time + 0.02, $0.touches) }
        require(detections(tail).isEmpty, "Two-finger tail creates a new three-finger pinch")

        var landing: [Frame] = []
        for step in 0...24 {
            let time = Double(step) / 120
            let contacts = circle(4, radius: 0.3 - min(Float(step) / 5, 1) * 0.1
                                  - max(Float(step - 6), 0) / 18 * 0.04)
            landing.append((time, time < 0.05 ? Array(contacts.prefix(3)) : contacts))
        }
        let landed = detections(landing, sensitivity: .veryHigh)
        require(landed.count == 1 && landed.first?.1 == 4,
                "Early three-finger frames steal a four-finger pinch")
        let staggeredFourth: [Frame] = [
            (0, Array(circle(4, radius: 0.3).prefix(2))),
            (0.01, Array(circle(4, radius: 0.3).prefix(2))),
            (0.04, Array(circle(4, radius: 0.27).prefix(3))),
            (0.045, Array(circle(4, radius: 0.19).prefix(3))),
            (0.066, Array(circle(4, radius: 0.17).prefix(3))),
            (0.07, circle(4, radius: 0.16)), (0.08, circle(4, radius: 0.15)),
            (0.105, circle(4, radius: 0.12))
        ]
        let lateFourth = detections(staggeredFourth, sensitivity: .veryHigh)
        require(lateFourth.count == 1 && lateFourth.first?.1 == 4,
                "Two early contacts consume the grace needed for a late third/fourth finger")

        let contracted = circle(3, radius: 0.18)
        let gap: [Frame] = [(0, three), (0.01, three), (0.02, contracted), (0.5, contracted), (0.55, contracted)]
        require(detections(gap).isEmpty, "A stale candidate is confirmed across a 480 ms frame gap")
        let reversedClock: [Frame] = [(1, three), (1.01, contracted), (0.1, contracted), (0.14, contracted)]
        require(detections(reversedClock).isEmpty, "A backwards timestamp reuses pre-discontinuity geometry")

        let four = circle(4, radius: 0.3)
        var swapped = circle(4, radius: 0.22)
        swapped[3].id = 99
        let replacement: [Frame] = [(0, four), (0.01, circle(4, radius: 0.25)),
                                    (0.02, swapped), (0.035, swapped)]
        require(detections(replacement).isEmpty, "A replacement finger inherits the old candidate's confirmation time")
        var dropout = trace(three, duration: 0.3) { touch, progress in
            var touch = touch
            touch.x = 0.5 + (touch.x - 0.5) * (1 - progress * 0.7)
            touch.y = 0.5 + (touch.y - 0.5) * (1 - progress * 0.7)
            return touch
        }
        dropout[18].touches = []
        dropout[22].touches = []
        dropout[25].touches = []
        require(detections(dropout).count == 1, "One dropped contact frame retriggers the same pinch")
        var singleContactDropout = dropout
        singleContactDropout[18].touches = [three[0]]
        require(detections(singleContactDropout).count == 1,
                "A single-contact dropout deletes peer IDs and retriggers the same pinch")
        var replacedAfterFire = dropout
        for index in 20..<replacedAfterFire.count {
            replacedAfterFire[index].touches = replacedAfterFire[index].touches.map {
                var touch = $0; touch.id += 100; return touch
            }
        }
        require(detections(replacedAfterFire).count == 1,
                "Replacing contact IDs after recognition retriggers the same physical gesture")
        var lateFrames = trace(three, duration: 0.3) { touch, progress in
            var touch = touch
            touch.x = 0.5 + (touch.x - 0.5) * (1 - progress * 0.7)
            touch.y = 0.5 + (touch.y - 0.5) * (1 - progress * 0.7)
            return touch
        }
        for index in 18..<lateFrames.count { lateFrames[index].time += 0.3 }
        require(detections(lateFrames).count == 1,
                "A long callback stall rearms already-recognized contacts without a release")
        let newCohort = three.map { original -> TouchSample in
            var touch = original; touch.id += 100; return touch
        }
        let newContacts = trace(newCohort, duration: 0.2) { touch, progress in
            var touch = touch
            touch.x = 0.5 + (touch.x - 0.5) * (1 - progress * 0.4)
            touch.y = 0.5 + (touch.y - 0.5) * (1 - progress * 0.4)
            return touch
        }.map { ($0.time + 1, $0.touches) }
        require(detections(lateFrames + newContacts).count == 2,
                "A new contact cohort after a stalled device inherits the old fired state")
        for count in [3, 4] {
            let moving = trace(circle(count, radius: 0.25)) { touch, progress in
                var touch = touch
                touch.x = 0.5 + (touch.x - 0.5) * (1 - progress * 0.08) + 0.2 * progress
                touch.y = 0.5 + (touch.y - 0.5) * (1 - progress * 0.08) + 0.08 * progress
                return touch
            }
            require(detections(moving, sensitivity: .veryHigh).isEmpty,
                    "Translation with slight finger-shape change is mistaken for pinch")
            for frequency in [60.0, 120.0] {
                for rotation: Float in [0, .pi / 3] {
                    let diagonal = trace(circle(count, radius: 0.25), frequency: frequency) { touch, progress in
                        let angle = rotation * progress
                        let x = (touch.x - 0.5) * (1 - progress * 0.4)
                        let y = (touch.y - 0.5) * (1 - progress * 0.4)
                        return TouchSample(id: touch.id, state: 4,
                                           x: 0.5 + x * cos(angle) - y * sin(angle) + progress * 0.08,
                                           y: 0.5 + x * sin(angle) + y * cos(angle) + progress * 0.04)
                    }
                    for sensitivity in PinchSensitivity.allCases {
                        require(detections(diagonal, sensitivity: sensitivity).first?.0 == .open,
                                "Diagonal/rotating pinch is locked out as a swipe (\(count), \(frequency)Hz, \(sensitivity))")
                    }
                }
                let rotation = trace(circle(count, radius: 0.25), frequency: frequency) { touch, progress in
                    let angle = Float.pi / 3 * progress
                    let x = touch.x - 0.5, y = touch.y - 0.5
                    return TouchSample(id: touch.id, state: 4,
                                       x: 0.5 + x * cos(angle) - y * sin(angle),
                                       y: 0.5 + x * sin(angle) + y * cos(angle))
                }
                require(detections(rotation, sensitivity: .veryHigh).isEmpty,
                        "Pure rotation is mistaken for a pinch")
            }
        }

        let monitor = PinchMonitor()
        var openings: [Int] = []
        monitor.onOpen = { openings.append($0) }
        for start in [0.0, 0.3] {
            let motion = trace(three) { touch, progress in
                var touch = touch
                touch.x = 0.5 + (touch.x - 0.5) * (1 - progress * 0.45)
                touch.y = 0.5 + (touch.y - 0.5) * (1 - progress * 0.45)
                return touch
            }
            for frame in motion { monitor.handle(samples: frame.touches, at: frame.time + start) }
            monitor.handle(samples: [], at: start + 0.18)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        require(openings == [3, 3], "Global cooldown drops a separate quick second gesture")

        let devices = PinchMonitor()
        var deviceOpenings: [Int] = []
        devices.onOpen = { deviceOpenings.append($0) }
        for frame in trace(three, transform: { touch, progress in
            var touch = touch
            touch.x = 0.5 + (touch.x - 0.5) * (1 - progress * 0.45)
            touch.y = 0.5 + (touch.y - 0.5) * (1 - progress * 0.45)
            return touch
        }) {
            devices.handle(samples: frame.touches, at: frame.time, deviceID: 1)
            devices.handle(samples: [], at: frame.time + 0.001, deviceID: 2)
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        require(deviceOpenings == [3], "An idle second trackpad cancels the active trackpad's pinch")
        let guardedUntil = devices.pinchPointerGuardUntil()
        for frame in 0..<60 {
            devices.handle(samples: [three[0]], at: 0.17 + Double(frame) / 120, deviceID: 1)
        }
        require(devices.pinchPointerGuardUntil() == guardedUntil,
                "A final resting finger keeps extending the pointer guard indefinitely")

        // The remaining thumb does not prevent a new, complete gesture from rearming.
        for frame in trace(three, transform: { touch, progress in
            var touch = touch
            touch.x = 0.5 + (touch.x - 0.5) * (1 - progress * 0.45)
            touch.y = 0.5 + (touch.y - 0.5) * (1 - progress * 0.45)
            return touch
        }) {
            devices.handle(samples: frame.touches, at: 0.7 + frame.time, deviceID: 1)
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        require(deviceOpenings == [3, 3], "A resting last finger leaves the classifier permanently disarmed")
        devices.handle(samples: [three[0]], at: 0.87, deviceID: 1)
        for frame in trace(three, transform: { touch, progress in
            var touch = touch
            touch.x = 0.5 + (touch.x - 0.5) * (1 - progress * 0.45)
            touch.y = 0.5 + (touch.y - 0.5) * (1 - progress * 0.45)
            return touch
        }) {
            devices.handle(samples: frame.touches, at: 0.9 + frame.time, deviceID: 2)
            devices.handle(samples: [three[0]], at: 0.901 + frame.time, deviceID: 1)
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        require(deviceOpenings == [3, 3, 3], "A resting finger prevents switching to the other trackpad")
        let disconnected = PinchMonitor()
        var recovered = 0
        disconnected.onOpen = { _ in recovered += 1 }
        disconnected.handle(samples: three, at: 0, deviceID: 1)
        disconnected.handle(samples: three, at: 0.01, deviceID: 1)
        for frame in trace(three, transform: { touch, progress in
            var touch = touch
            touch.x = 0.5 + (touch.x - 0.5) * (1 - progress * 0.45)
            touch.y = 0.5 + (touch.y - 0.5) * (1 - progress * 0.45)
            return touch
        }) {
            disconnected.handle(samples: frame.touches, at: 0.3 + frame.time, deviceID: 2)
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        require(recovered == 1, "A disconnected active trackpad permanently blocks another device")

        if failures.isEmpty {
            print("PASS: scale/aspect invariance, anchored thumb, finger-count arbitration, tails, discontinuities and rearming")
            print("PASS: interleaved trackpads and final resting finger do not cancel gestures or prolong pointer blocking")
        } else {
            for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
            exit(1)
        }
    }
}
