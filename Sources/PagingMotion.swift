import Combine
import Foundation

/// 连续滑动只更新翻页区域，不广播到搜索栏、收纳面板和其他应用状态观察者。
@MainActor
final class PagingMotion: ObservableObject {
    @Published var offset: CGFloat = 0
    @Published var isSwiping = false
    let presentation = PagingPresentation()
    var interruptedSettlement = false

    func presentedOffset(on page: Int) -> CGFloat {
        guard let sample = presentation.sample else { return offset }
        return sample.position + CGFloat(page) * sample.pageWidth
    }
}

/// The last interpolated position, not the spring's destination. Recording it
/// does not publish a view update; a new gesture can take over exactly there.
final class PagingPresentation {
    struct Sample {
        var position: CGFloat
        var pageWidth: CGFloat
    }
    private let lock = NSLock()
    private var latest: Sample?

    var sample: Sample? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    func record(position: CGFloat, pageWidth: CGFloat) {
        lock.lock()
        defer { lock.unlock() }
        latest = Sample(position: position, pageWidth: pageWidth)
    }
}

enum PageResidency {
    static let capacity = 5

    /// Keep the active neighborhood ready and retain recent pages through reversals.
    static func retaining<ID: Hashable>(_ pages: [ID], active: Int, previous: [ID],
                                       preloadNeighbors: Bool = true, protecting outgoing: ID? = nil,
                                       pinned: ID? = nil) -> [ID] {
        guard !pages.isEmpty else { return [] }
        let neighborCount = min(pages.count, 3)
        let start = min(max(active - 1, 0), pages.count - neighborCount)
        var requiredPages = preloadNeighbors ? Array(pages[start..<(start + neighborCount)])
            : [pages[min(max(active, 0), pages.count - 1)]]
        let available = Set(pages)
        for id in [outgoing, pinned].compactMap({ $0 }) where available.contains(id) && !requiredPages.contains(id) {
            requiredPages.append(id)
        }
        let required = Set(requiredPages)
        let valid = previous.filter { available.contains($0) }
        // Reversing inside the cache should not publish a second layout update
        // merely to reorder bookkeeping for the same mounted pages.
        if valid.count <= capacity && required.isSubset(of: Set(valid)) { return valid }
        let retained = valid.filter { !required.contains($0) }
        let nearest = retained.sorted {
            abs((pages.firstIndex(of: $0) ?? active) - active)
                < abs((pages.firstIndex(of: $1) ?? active) - active)
        }
        let survivors = Set(nearest.prefix(max(0, capacity - requiredPages.count)))
        return retained.filter(survivors.contains) + requiredPages
    }
}
