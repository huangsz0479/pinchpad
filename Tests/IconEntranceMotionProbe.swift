import Foundation

// Samples the exact cubic control points consumed by BloomIn's timingCurve.
// The separate OpeningPerformanceProbe checks the real SwiftUI ring geometry and lifecycle.
// swiftc Sources/IconEntrance.swift Tests/IconEntranceMotionProbe.swift -o /tmp/IconEntranceMotionProbe
@main
struct IconEntranceMotionProbe {
    static func require(_ condition: Bool, _ message: String) {
        guard condition else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func cubic(_ t: Double, _ first: Double, _ second: Double) -> Double {
        let remaining = 1 - t
        return 3 * remaining * remaining * t * first + 3 * remaining * t * t * second + t * t * t
    }

    static func progress(_ time: Double) -> Double {
        if time <= 0 { return 0 }
        if time >= 1 { return 1 }
        let curve = IconEntrance.curve
        var low = 0.0
        var high = 1.0
        for _ in 0..<48 {
            let parameter = (low + high) / 2
            if cubic(parameter, curve.x1, curve.x2) < time { low = parameter }
            else { high = parameter }
        }
        return cubic((low + high) / 2, curve.y1, curve.y2)
    }

    static func main() {
        let values = (0...2_000).map { progress(Double($0) / 2_000) }
        require(values.first == 0 && values.last == 1, "The entrance does not reach exact endpoints")
        require(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 && $1 <= 1 },
                "The configured wave overshoots or reverses instead of settling")
        let epsilon = 0.000_01
        require(progress(epsilon) / epsilon < 0.001
                && (1 - progress(1 - epsilon)) / epsilon < 0.001,
                "The wave starts or stops with an abrupt nonzero velocity")
        require(Double(IconEntrance.ringCount - 1) * IconEntrance.ringDelay < IconEntrance.duration,
                "Rings run as separate beats instead of overlapping into one continuous wave")
        require(abs(IconEntrance.totalDuration
                    - (IconEntrance.duration + Double(IconEntrance.ringCount - 1) * IconEntrance.ringDelay)) < 0.000_01,
                "The interaction settling boundary ends before the outer ring")

        // A 1/60 second sample is a geometric continuity check, not a display FPS test.
        let step = 1.0 / 60 / IconEntrance.duration
        let positions = (0...Int(ceil(1 / step))).map { progress(min(Double($0) * step, 1)) }
        let increments = zip(positions, positions.dropFirst()).map { $1 - $0 }
        require(increments.first! < increments.max()! * 0.25,
                "The first movement jumps to near peak speed")
        print(String(format: "PASS: configured wave has zero endpoint velocity; first-step progress %.4f, peak-step %.4f; overlapping rings settle in %.3f s",
                     increments.first!, increments.max()!, IconEntrance.totalDuration))
    }
}
