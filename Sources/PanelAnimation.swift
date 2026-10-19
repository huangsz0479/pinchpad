import QuartzCore

enum PanelAnimation {
    static let opacityDuration: CFTimeInterval = 0.13
    static let closingDuration: CFTimeInterval = 0.18

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
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fade.preferredFrameRateRange = frameRateRange(maximumFramesPerSecond: maximumFramesPerSecond)
        return fade
    }

    static func closing(fromOpacity: Float, maximumFramesPerSecond: Int) -> CABasicAnimation {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = fromOpacity
        fade.toValue = 0
        fade.duration = closingDuration
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        fade.preferredFrameRateRange = frameRateRange(maximumFramesPerSecond: maximumFramesPerSecond)
        return fade
    }
}
