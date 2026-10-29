import Foundation

// No application or window is created.
// swiftc Sources/PagingMotion.swift Tests/PageResidencyProbe.swift -o /tmp/PageResidencyProbe
@main
struct PageResidencyProbe {
    static func main() {
        let pages = Array(0..<20)
        var cache: [Int] = []
        for active in Array(0..<20) + Array((0..<20).reversed()) + [7, 15, 2, 18, 0] {
            cache = PageResidency.retaining(pages, active: active, previous: cache)
            precondition(cache.count <= PageResidency.capacity)
            precondition(Set(cache).count == cache.count)
            for neighbor in max(0, active - 1)...min(pages.count - 1, active + 1) {
                precondition(cache.contains(neighbor), "Active page and immediate neighbors must stay mounted")
            }
            precondition(PageResidency.retaining(pages, active: active, previous: cache) == cache,
                         "Repeated layout must not change residency")
        }

        cache = PageResidency.retaining(pages, active: 2, previous: [])
        for active in [3, 2, 3, 2, 3, 2] {
            let previous = Set(cache)
            cache = PageResidency.retaining(pages, active: active, previous: cache)
            precondition(previous.isSubset(of: Set(cache)),
                         "Neighboring reversals must retain the already mounted page grids")
        }
        let beforeStep = cache
        cache = PageResidency.retaining(pages, active: 3, previous: cache, preloadNeighbors: false)
        precondition(cache == beforeStep, "A warm page turn must not construct an outside neighbor")
        cache = PageResidency.retaining(pages, active: 17, previous: cache, preloadNeighbors: false)
        precondition(cache.contains(17) && !cache.contains(16) && !cache.contains(18),
                     "Rapid jumps must mount the destination immediately without mounting its outside neighbors")
        cache = PageResidency.retaining(pages, active: 17, previous: cache)
        precondition([16, 17, 18].allSatisfy(cache.contains), "Idle warmup must restore both neighbors")
        cache = PageResidency.retaining(pages, active: 0, previous: [])
        var outgoing = 0
        for target in Array(1...5) + Array((0..<5).reversed()) {
            cache = PageResidency.retaining(pages, active: target, previous: cache,
                                            preloadNeighbors: false, protecting: outgoing)
            guard cache.contains(outgoing) else {
                fputs("FAIL: rapid reversal discarded outgoing page \(outgoing) while moving to \(target)\n", stderr)
                exit(1)
            }
            outgoing = target
        }
        cache = []
        outgoing = 0
        for target in Array(0..<20) + Array((0..<20).reversed()) {
            cache = PageResidency.retaining(pages, active: target, previous: cache,
                                            protecting: outgoing, pinned: 0)
            precondition(cache.contains(0) && cache.contains(outgoing) && cache.contains(target),
                         "Return-to-first-page mode must retain the homepage and both sliding pages")
            precondition(cache.count <= PageResidency.capacity)
            outgoing = target
        }
        let remaining = [7, 3, 1]
        cache = PageResidency.retaining(remaining, active: 2, previous: cache)
        precondition(Set(cache) == Set(remaining), "Deleted pages must leave the cache")
        precondition(PageResidency.retaining([Int](), active: 0, previous: cache).isEmpty)
        print("PASS: bounded page residency preserves neighbors, reversals, identity changes and empty libraries")
    }
}
