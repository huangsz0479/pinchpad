import QuartzCore

enum PanelAnimation {
    static let opacityDuration: CFTimeInterval = 0.18
    static let closingDuration: CFTimeInterval = 0.16
    static let timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0, 0.25, 1)

    static func frameRateRange(maximumFramesPerSecond: Int) -> CAFrameRateRange {
        let maximum = Float(maximumFramesPerSecond > 0 ? maximumFramesPerSecond : 60)
        return CAFrameRateRange(minimum: min(60, maximum), maximum: maximum,
                                preferred: min(120, maximum))
    }

    static func opening(maximumFramesPerSecond: Int, fromOpacity: Float = 0) -> CABasicAnimation {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = fromOpacity
        fade.toValue = 1
        fade.duration = opacityDuration
        fade.timingFunction = timingFunction
        fade.preferredFrameRateRange = frameRateRange(maximumFramesPerSecond: maximumFramesPerSecond)
        return fade
    }

    static func closing(fromOpacity: Float, maximumFramesPerSecond: Int) -> CABasicAnimation {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = fromOpacity
        fade.toValue = 0
        fade.duration = closingDuration
        fade.timingFunction = timingFunction
        fade.preferredFrameRateRange = frameRateRange(maximumFramesPerSecond: maximumFramesPerSecond)
        return fade
    }
}
