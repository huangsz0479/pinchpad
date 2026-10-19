import Combine
import Foundation

/// 连续滑动只更新翻页区域，不广播到搜索栏、收纳面板和其他应用状态观察者。
@MainActor
final class PagingMotion: ObservableObject {
    @Published var offset: CGFloat = 0
    @Published var isSwiping = false
}
