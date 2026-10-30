import Foundation

struct TouchSample: Equatable {
    var id: Int32
    var state: Int32
    var x: Float
    var y: Float

    /// MTTouchStateMakeTouch(3)、MTTouchStateTouching(4)。抬起、悬停中的触点不算手指。
    var isDown: Bool { state == 3 || state == 4 }
}

enum PinchSignal: Equatable { case open, close }

enum PinchSensitivity: Int, Codable, CaseIterable, Identifiable {
    case veryLow = 1, low, standard, high, veryHigh

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .veryLow: return "很低"
        case .low: return "低"
        case .standard: return "标准"
        case .high: return "高"
        case .veryHigh: return "很高"
        }
    }

    var spreadThreshold: Float {
        // Fraction of the initial pairwise span, independent of hand size.
        switch self {
        case .veryLow: return 0.19
        case .low: return 0.164
        case .standard: return 0.14
        case .high: return 0.12
        case .veryHigh: return 0.10
        }
    }

    var confirmationDuration: TimeInterval {
        // 各档统一基础防抖；灵敏度只控制收拢幅度，不再叠加长时间等待。
        0.02
    }
}

/// 只根据触点几何判断一次多指手势是捏合还是平移。
/// 以两两触点间距为基准：手指先后落下、先后抬起时，已经落下的手指积累的位移不会丢，
/// 真实的捏合往往只有 0.1~0.2 秒，三指同时在板上的窗口更短，不能每次换手指就重新计。
struct PinchClassifier {
    enum Kind { case unknown, pinch, swipe }

    static let swipeDrift: Float = 0.06
    static let minPeakFrames = 2
    private static let confirmationSpread: Float = 0.05
    private static let maximumFrameGap: TimeInterval = 0.12
    private static let contactDropoutGrace: TimeInterval = 0.045
    private static let fingerCountGrace: TimeInterval = 0.05

    private struct Pair: Hashable {
        let a: Int32
        let b: Int32
        init(_ x: Int32, _ y: Int32) { a = min(x, y); b = max(x, y) }
    }

    private struct Confirmation {
        let signal: PinchSignal
        let began: TimeInterval
    }

    private(set) var kind = Kind.unknown
    private(set) var fingers = 0
    private(set) var peak = 0
    private(set) var signal: PinchSignal?
    private(set) var resetGeneration: UInt = 0
    let threeFingerSensitivity: PinchSensitivity
    let fourFingerSensitivity: PinchSensitivity
    // Peak count survives finger lift-off; a four-finger gesture must never
    // switch to the three-finger threshold while its contacts are releasing.
    var sensitivity: PinchSensitivity { peak >= 4 ? fourFingerSensitivity : threeFingerSensitivity }
    private var peakFrames = 0
    private var fired = false
    private var landing: [Int32: (x: Float, y: Float)] = [:]
    private var pairBase: [Pair: Float] = [:]
    private var confirmation: Confirmation?
    private var lastTimestamp: TimeInterval?
    private var releasedAt: TimeInterval?
    private var multiContactBegan: TimeInterval?
    private var tailConfirmationUntil: TimeInterval?

    init(threeFingerSensitivity: PinchSensitivity = .standard, fourFingerSensitivity: PinchSensitivity = .standard) {
        self.threeFingerSensitivity = threeFingerSensitivity
        self.fourFingerSensitivity = fourFingerSensitivity
    }

    init(sensitivity: PinchSensitivity) {
        self.init(threeFingerSensitivity: sensitivity, fourFingerSensitivity: sensitivity)
    }

    mutating func reset() {
        let generation = resetGeneration &+ 1
        self = PinchClassifier(threeFingerSensitivity: threeFingerSensitivity, fourFingerSensitivity: fourFingerSensitivity)
        resetGeneration = generation
    }

    /// 系统已经把这次手势认作平移（切换空间、调度中心），之后不再判成捏合。
    mutating func markSwipe() {
        if fingers > 0, kind == .unknown {
            kind = .swipe
            confirmation = nil
        }
    }

    mutating func feed(_ samples: [TouchSample], at timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime,
                       tracked: (Int) -> Bool) -> PinchSignal? {
        guard timestamp.isFinite else { reset(); return nil }
        if let previous = lastTimestamp,
           timestamp < previous || timestamp - previous > Self.maximumFrameGap {
            let keepRecognition = fired && releasedAt == nil && fingers >= 2
                && Set(samples.filter(\.isDown).map(\.id)).intersection(landing.keys).count >= 2
            let previousSignal = signal
            reset()
            if keepRecognition {
                // Lost samples invalidate geometric evidence, not an action
                // already delivered for contacts that never released.
                fired = true
                kind = .pinch
                signal = previousSignal
            }
        }
        lastTimestamp = timestamp
        var ids = Set<Int32>()
        let touches = samples.filter {
            $0.isDown && $0.x > -0.5 && $0.x < 1.5 && $0.y > -0.5 && $0.y < 1.5
                && ids.insert($0.id).inserted
        }
        guard !touches.isEmpty else {
            // One missing sensor frame must not rearm a gesture that already fired.
            // A real release starts a fresh gesture when contacts return after the grace.
            fingers = 0
            confirmation = nil
            if releasedAt == nil { releasedAt = timestamp }
            return nil
        }
        if let releasedAt, touches.count >= 2 {
            let sharedIDs = ids.intersection(landing.keys).count
            if timestamp - releasedAt > Self.contactDropoutGrace || sharedIDs < min(touches.count, 2) {
                reset()
                lastTimestamp = timestamp
            }
            self.releasedAt = nil
        }
        if touches.count == 1 {
            if releasedAt == nil { releasedAt = timestamp }
            fingers = 1
            confirmation = nil
            // Keep peer identities through a brief partial sensor dropout too.
            // If one finger really remains, the grace expires before the next gesture.
            return nil
        }
        let previousIDs = Set(landing.keys)
        if previousIDs.count == touches.count && previousIDs != ids {
            confirmation = nil
        }
        if touches.count >= 3 && multiContactBegan == nil { multiContactBegan = timestamp }
        track(touches)
        let completingThreeFingerPinch = peak == 3 && fingers == 2 && confirmation != nil
            && timestamp <= (tailConfirmationUntil ?? -.infinity)
        guard tracked(peak), peakFrames >= Self.minPeakFrames,
              fingers >= max(3, peak - 1) || completingThreeFingerPinch,
              kind == .unknown, !fired else {
            confirmation = nil
            return nil
        }

        var change: Float = 0
        var baseline: Float = 0
        var shrinking = 0
        var growing = 0
        for i in touches.indices {
            for j in touches.indices where j > i {
                let base = pairBase[Pair(touches[i].id, touches[j].id)] ?? 0
                let delta = Self.distance(touches[i], touches[j]) - base
                change += delta
                baseline += base
                if delta < -max(0.004, base * 0.02) { shrinking += 1 }
                if delta > max(0.004, base * 0.02) { growing += 1 }
            }
        }
        let pairs = fingers * (fingers - 1) / 2
        let absoluteChange = change / Float(pairs)
        // Use proportional spread so the same pinch works for a small hand span
        // or either axis of a rectangular trackpad. Keep a small absolute noise floor.
        change /= max(baseline, 0.001)

        var driftX: Float = 0
        var driftY: Float = 0
        for touch in touches {
            let origin = landing[touch.id] ?? (touch.x, touch.y)
            driftX += touch.x - origin.x
            driftY += touch.y - origin.y
        }
        let drift = hypotf(driftX, driftY) / Float(fingers)

        var proposed: PinchSignal?
        if abs(change) > Self.confirmationSpread, abs(absoluteChange) > 0.012,
           abs(absoluteChange) > drift * 0.5 {
            // 固定拇指、其余手指成组移动时，组内间距不变；连接拇指的
            // fingers - 1 对距离同向变化就有完整的多指收拢证据。
            let agree = fingers - 1
            if change < 0, shrinking >= agree {
                proposed = .open
            } else if change > 0, growing >= agree {
                proposed = .close
            }
        }
        if fingers >= 3 {
            tailConfirmationUntil = proposed != nil && abs(change) >= sensitivity.spreadThreshold * 0.8
                ? timestamp + Self.contactDropoutGrace : nil
        } else if proposed != confirmation?.signal {
            // Two remaining fingers may finish a nearly complete multi-finger
            // pinch, but must never originate a gesture or reverse its direction.
            proposed = nil
        }
        if let proposed {
            if confirmation?.signal != proposed || timestamp < (confirmation?.began ?? timestamp) {
                confirmation = Confirmation(signal: proposed, began: timestamp)
            }
            // 收拢过程中就累计确认；达到档位要求后可直接触发，不额外要求停住。
            if let confirmation, abs(change) > sensitivity.spreadThreshold,
               timestamp - confirmation.began >= sensitivity.confirmationDuration,
               peak != 3 || timestamp - (multiContactBegan ?? timestamp) >= Self.fingerCountGrace {
                kind = .pinch
                fired = true
                signal = proposed
                return proposed
            }
        } else {
            confirmation = nil
        }
        if drift > Self.swipeDrift, drift > abs(absoluteChange) * 2 { kind = .swipe }
        return nil
    }

    private mutating func track(_ touches: [TouchSample]) {
        let ids = Set(touches.map(\.id))
        for id in landing.keys where !ids.contains(id) {
            landing[id] = nil
        }
        pairBase = pairBase.filter { ids.contains($0.key.a) && ids.contains($0.key.b) }
        for touch in touches where landing[touch.id] == nil {
            landing[touch.id] = (touch.x, touch.y)
            for other in touches where other.id != touch.id {
                pairBase[Pair(touch.id, other.id)] = Self.distance(touch, other)
            }
        }
        fingers = touches.count
        if fingers > peak {
            peak = fingers
            peakFrames = 0
        }
        if fingers == peak { peakFrames += 1 }
    }

    private static func distance(_ a: TouchSample, _ b: TouchSample) -> Float {
        hypotf(a.x - b.x, a.y - b.y)
    }
}
