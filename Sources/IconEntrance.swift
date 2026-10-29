import Foundation

/// Shared choreography and event policy for the original center-out icon wave.
enum IconEntrance {
    static let ringCount = 4
    static let ringDelay: TimeInterval = 0.024
    static let duration: TimeInterval = 0.32
    static let initialScale: CGFloat = 0.90
    static let totalDuration = duration + Double(ringCount - 1) * ringDelay

    /// Zero endpoint velocity avoids the old ease-out's immediate kick and hard visual stop.
    static let curve = (x1: 0.25, y1: 0.0, x2: 0.25, y2: 1.0)

    struct Signal: Equatable {
        var reset: Int
        var bloom: Int
    }

    enum Action: Equatable {
        case none, show, reset, animate
    }

    static func action(from old: Signal, to new: Signal, enabled: Bool, reduceMotion: Bool) -> Action {
        guard old != new else { return .none }
        guard enabled && !reduceMotion else { return .show }
        // Reset and bloom may be coalesced in one SwiftUI update: playback wins.
        if old.bloom != new.bloom { return .animate }
        if old.reset != new.reset { return .reset }
        return .none
    }

    static func ring(for index: Int, columns: Int, rows: Int) -> Int {
        let columns = max(columns, 1)
        let centerX = Double(columns - 1) / 2
        let centerY = Double(max(rows, 1) - 1) / 2
        let maximum = max(sqrt(centerX * centerX + centerY * centerY), 1)
        let dx = Double(index % columns) - centerX
        let dy = Double(index / columns) - centerY
        let normalized = sqrt(dx * dx + dy * dy) / maximum
        return min(Int(normalized * Double(ringCount)), ringCount - 1)
    }
}
