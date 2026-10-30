import Foundation

/// Physical key codes keep navigation usable with Chinese and other input methods.
struct CardNavigationShortcuts: Codable, Equatable {
    enum Direction { case previous, next }
    private(set) var next: UInt16 = 48
    private(set) var previous: UInt16 = 50

    static func accepts(_ code: UInt16) -> Bool {
        if code >= 256 { return [0, 1, 2, 3, 7, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 25].contains(Int(code) - 256) }
        return code < 127 && ![54, 55, 58, 59, 61, 62, 63].contains(code)
    }

    func direction(for code: UInt16) -> Direction? {
        if code == next { return .next }
        if code == previous { return .previous }
        return nil
    }

    mutating func set(_ code: UInt16, for direction: Direction) {
        guard Self.accepts(code) else { return }
        // Swapping avoids leaving one direction unreachable after a conflict.
        switch direction {
        case .next:
            if previous == code { previous = next }
            next = code
        case .previous:
            if next == code { next = previous }
            previous = code
        }
    }

    init() {}
    private enum CodingKeys: String, CodingKey { case next, previous }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let code = try? values.decode(UInt16.self, forKey: .next), Self.accepts(code) { next = code }
        if let code = try? values.decode(UInt16.self, forKey: .previous), Self.accepts(code), code != next {
            previous = code
        } else if previous == next { previous = 48 }
    }

    /// Navigation wraps over all pages, including reverse navigation from the first card.
    static func index(current: Int?, count: Int, direction: Direction, pageStart: Int = 0) -> Int? {
        guard count > 0 else { return nil }
        let step = direction == .next ? 1 : -1
        let start = current ?? (direction == .next ? pageStart - 1 : pageStart)
        return ((start + step) % count + count) % count
    }
}

/// Normalized screen-local positions survive relaunches and display-size changes.
struct ClotheslinePosition: Codable, Equatable {
    var x: Double
    var y: Double
    var isValid: Bool { x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) }
}
