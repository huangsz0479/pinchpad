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
        switch self {
        case .veryLow: return 0.095
        case .low: return 0.082
        case .standard: return 0.07
        case .high: return 0.06
        case .veryHigh: return 0.05
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
    static let pairMove: Float = 0.01
    static let minPeakFrames = 2
    private static let confirmationSpread: Float = 0.025

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
    let sensitivity: PinchSensitivity
    private var peakFrames = 0
    private var fired = false
    private var landing: [Int32: (x: Float, y: Float)] = [:]
    private var pairBase: [Pair: Float] = [:]
    private var confirmation: Confirmation?

    init(sensitivity: PinchSensitivity = .standard) {
        self.sensitivity = sensitivity
    }

    mutating func reset() { self = PinchClassifier(sensitivity: sensitivity) }

    /// 系统已经把这次手势认作平移（切换空间、调度中心），之后不再判成捏合。
    mutating func markSwipe() {
        if fingers > 0, kind == .unknown {
            kind = .swipe
            confirmation = nil
        }
    }

    mutating func feed(_ samples: [TouchSample], at timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime,
                       tracked: (Int) -> Bool) -> PinchSignal? {
        let touches = samples.filter { $0.isDown && $0.x > -0.5 && $0.x < 1.5 && $0.y > -0.5 && $0.y < 1.5 }
        guard !touches.isEmpty else {
            reset()
            return nil
        }
        track(touches)
        guard tracked(peak), peakFrames >= Self.minPeakFrames, fingers >= max(2, peak - 1),
              kind == .unknown, !fired else {
            confirmation = nil
            return nil
        }

        var change: Float = 0
        var shrinking = 0
        var growing = 0
        for i in touches.indices {
            for j in touches.indices where j > i {
                let delta = Self.distance(touches[i], touches[j]) - (pairBase[Pair(touches[i].id, touches[j].id)] ?? 0)
                change += delta
                if delta < -Self.pairMove { shrinking += 1 }
                if delta > Self.pairMove { growing += 1 }
            }
        }
        let pairs = fingers * (fingers - 1) / 2
        change /= Float(pairs)

        var driftX: Float = 0
        var driftY: Float = 0
        for touch in touches {
            let origin = landing[touch.id] ?? (touch.x, touch.y)
            driftX += touch.x - origin.x
            driftY += touch.y - origin.y
        }
        let drift = hypotf(driftX, driftY) / Float(fingers)

        var proposed: PinchSignal?
        if abs(change) > Self.confirmationSpread, abs(change) > drift * 0.5 {
            // 拇指加三指捏合时，离拇指最近的那根手指和别的手指之间的距离可能不变甚至变大，允许少数几对例外。
            let agree = pairs - (fingers - 2)
            if change < 0, shrinking >= agree {
                proposed = .open
            } else if change > 0, growing >= agree {
                proposed = .close
            }
        }
        if let proposed {
            if confirmation?.signal != proposed || timestamp < (confirmation?.began ?? timestamp) {
                confirmation = Confirmation(signal: proposed, began: timestamp)
            }
            // 收拢过程中就累计确认；达到档位要求后可直接触发，不额外要求停住。
            if let confirmation, abs(change) > sensitivity.spreadThreshold,
               timestamp - confirmation.began >= sensitivity.confirmationDuration {
                kind = .pinch
                fired = true
                signal = proposed
                return proposed
            }
        } else {
            confirmation = nil
        }
        if drift > Self.swipeDrift, drift > abs(change) * 2 { kind = .swipe }
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
