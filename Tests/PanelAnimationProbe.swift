import Foundation
import QuartzCore

// No windows, system input, display links, or running app are needed.
// swiftc Sources/IconEntrance.swift Sources/PanelAnimation.swift Tests/PanelAnimationProbe.swift -o /tmp/PanelAnimationProbe
@main
struct PanelAnimationProbe {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw NSError(domain: "PanelAnimationProbe", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    static func checkOpening(maximum: Int) throws {
        let animation: CAAnimation = PanelAnimation.opening(maximumFramesPerSecond: maximum)
        guard let fade = animation as? CABasicAnimation, fade.keyPath == "opacity" else {
            try require(false, "Panel opening must preserve the icon wave; a whole-panel zoom replaces the original effect")
            return
        }
        try require((fade.fromValue as? NSNumber)?.floatValue == 0
                    && (fade.toValue as? NSNumber)?.floatValue == 1,
                    "Opening fade has incorrect endpoints")
        try require(fade.duration == PanelAnimation.opacityDuration,
                    "Background fade must keep the original duration")
        try require(fade.isRemovedOnCompletion && fade.delegate == nil,
                    "Background fade must settle without per-frame app callbacks")
        let cap = Float(maximum > 0 ? maximum : 60)
        let range = fade.preferredFrameRateRange
        try require(range.maximum == cap && range.preferred == min(cap, 120)
                    && range.minimum <= (range.preferred ?? 0),
                    "Frame-rate hint does not follow the display capability (\(maximum) Hz)")
        print("PASS: background fade preserves the icon wave, with refresh hint for \(maximum) Hz")
    }

    static func checkInterruptedOpening() throws {
        let openingAnimation: CAAnimation = PanelAnimation.opening(maximumFramesPerSecond: 120,
                                                                   fromOpacity: 0.4)
        let opening = openingAnimation as? CABasicAnimation
        try require((opening?.fromValue as? NSNumber)?.floatValue == 0.4,
                    "Reopening jumps to zero opacity instead of continuing the presentation")
        let close = PanelAnimation.closing(fromOpacity: 0.4, maximumFramesPerSecond: 120)
        try require(close.keyPath == "opacity" && (close.fromValue as? NSNumber)?.floatValue == 0.4
                    && (close.toValue as? NSNumber)?.floatValue == 0,
                    "Closing jumps instead of fading from the current presentation")
        try require(close.preferredFrameRateRange.preferred == 120,
                    "Closing does not request high refresh")
        print("PASS: rapid open/close preserves opacity and high-refresh hints")
    }

    static func checkFadeEndpoints() throws {
        for fade in [PanelAnimation.opening(maximumFramesPerSecond: 120),
                     PanelAnimation.closing(fromOpacity: 1, maximumFramesPerSecond: 120)] {
            var first: [Float] = [0, 0]
            var second: [Float] = [0, 0]
            fade.timingFunction?.getControlPoint(at: 1, values: &first)
            fade.timingFunction?.getControlPoint(at: 2, values: &second)
            try require(first[0] > 0 && first[1] == 0 && second[0] < 1 && second[1] == 1,
                        "Panel fade starts or stops at nonzero speed instead of joining smoothly")
        }
        print("PASS: panel fades ease into and out of rest without cutting the animation")
    }

    static func checkIconWave() throws {
        typealias Signal = IconEntrance.Signal
        let idle = Signal(reset: 0, bloom: 0)
        let prepared = Signal(reset: 1, bloom: 0)
        let opened = Signal(reset: 1, bloom: 1)
        try require(IconEntrance.action(from: idle, to: prepared, enabled: true, reduceMotion: false) == .reset,
                    "Preparing must hide the active-page icons before opening")
        for previous in [idle, prepared] {
            try require(IconEntrance.action(from: previous, to: opened, enabled: true, reduceMotion: false) == .animate,
                        "Coalesced reset and open must still play the original wave")
            try require(IconEntrance.action(from: previous, to: opened, enabled: false, reduceMotion: false) == .show,
                        "Offscreen pages must remain visible without animating")
            try require(IconEntrance.action(from: previous, to: opened, enabled: true, reduceMotion: true) == .show,
                        "Reduce Motion must reveal icons immediately")
        }
        for enabled in [false, true] {
            try require(IconEntrance.action(from: opened, to: opened, enabled: enabled, reduceMotion: false) == .none,
                        "Changing pages must not replay the entrance")
        }
        let closed = Signal(reset: 2, bloom: 1)
        let reopened = Signal(reset: 3, bloom: 2)
        try require(IconEntrance.action(from: opened, to: closed, enabled: true, reduceMotion: false) == .reset
                    && IconEntrance.action(from: closed, to: reopened, enabled: true, reduceMotion: false) == .animate,
                    "Repeated openings must reset and replay the wave")
        try require(IconEntrance.ring(for: 24, columns: 7, rows: 7) == 0
                    && IconEntrance.ring(for: 0, columns: 7, rows: 7) == 3,
                    "Wave must progress from the center to the outer corners")
        let rings = Set((0..<49).map { IconEntrance.ring(for: $0, columns: 7, rows: 7) })
        try require(rings == Set(0..<4), "The original four rings must remain distinct")
        try require(IconEntrance.ringCount == 4 && IconEntrance.ringDelay > 0
                    && IconEntrance.ringDelay < IconEntrance.duration
                    && IconEntrance.initialScale > 0 && IconEntrance.initialScale < 1,
                    "Icon wave lost its overlapping center-out expansion")
        try require(IconEntrance.curve.y1 == 0 && IconEntrance.curve.y2 == 1
                    && IconEntrance.curve.x1 > 0 && IconEntrance.curve.x2 < 1,
                    "Icon motion must start and settle with zero velocity")
        print("PASS: original four-ring wave, repeated openings, offscreen pages, page changes and Reduce Motion")
    }

    static func main() {
        do {
            for maximum in [60, 120, 144, 240, 0] { try checkOpening(maximum: maximum) }
            try checkInterruptedOpening()
            try checkFadeEndpoints()
            try checkIconWave()
        } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
