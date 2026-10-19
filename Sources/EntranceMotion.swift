import Combine
import Foundation

/// 入场信号只更新波纹动画，避免重新构造整页图标。
@MainActor
final class EntranceMotion: ObservableObject {
    @Published private(set) var signal = IconEntrance.Signal(reset: 0, bloom: 0)

    func prepare() {
        var next = signal
        next.reset &+= 1
        signal = next
    }

    func play() {
        var next = signal
        next.bloom &+= 1
        signal = next
    }
}
