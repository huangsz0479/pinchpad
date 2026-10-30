import Foundation

// Pure geometry only; no application, windows, input, device hooks or user data.
// swiftc -swift-version 5 Sources/Model.swift Sources/PinchClassifier.swift \
//   Sources/TrayGridLayout.swift Tests/TrayGridLayoutProbe.swift -o /tmp/TrayGridLayoutProbe
@main struct TrayGridLayoutProbe {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func validate(_ sizes: [TrayAppSize], width: CGFloat, columns: Int = 4) {
        let layout = TrayGridMetrics(sizes: sizes, width: width, columns: columns)
        require(layout.frames.count == sizes.count, "An application disappeared or was duplicated")
        require(layout.frames == TrayGridMetrics(sizes: sizes, width: width, columns: columns).frames,
                "The same app sizes produced unstable placement")
        require(layout.height.isFinite && layout.height >= 0, "Invalid total height")
        for (index, frame) in layout.frames.enumerated() {
            require(frame.minX >= 0 && frame.minY >= 0 && frame.maxX <= max(0, width) + 0.001,
                    "An application extends outside the available width")
            require(frame.maxY <= layout.height + 0.001, "Window height clips an application")
            let span = min(max(1, columns), sizes[index].columns)
            require(abs(frame.width - (CGFloat(span) * layout.unit + CGFloat(span - 1) * layout.spacing)) < 0.001,
                    "App width does not honor its selected size")
            require(abs(frame.height - (CGFloat(sizes[index].rows) * layout.unit
                         + CGFloat(sizes[index].rows - 1) * layout.spacing)) < 0.001,
                    "App height does not honor its selected size")
            for other in layout.frames.prefix(index) {
                require(!frame.intersects(other), "Application controls overlap")
            }
        }
        require(abs(layout.height - (layout.frames.map(\.maxY).max() ?? 0)) < 0.001,
                "Reported height differs from the lowest control")
    }

    static func main() {
        let empty = TrayGridMetrics(sizes: [], width: 336)
        require(empty.frames.isEmpty && empty.height == 0, "Empty app sections reserve a phantom row")
        let oneRow = TrayGridMetrics(sizes: [.small, .small, .small, .small], width: 336)
        require(oneRow.frames == [CGRect(x: 0, y: 0, width: 75, height: 75),
                                 CGRect(x: 87, y: 0, width: 75, height: 75),
                                 CGRect(x: 174, y: 0, width: 75, height: 75),
                                 CGRect(x: 261, y: 0, width: 75, height: 75)],
                "Four small controls must fit one row")
        let fillGap = TrayGridMetrics(sizes: [.small, .large, .small, .medium], width: 336)
        require(fillGap.frames[1] == CGRect(x: 87, y: 0, width: 162, height: 162),
                "Large control must occupy a square spanning two columns and rows")
        require(fillGap.frames[2] == CGRect(x: 261, y: 0, width: 75, height: 75),
                "Small control did not fill the first available gap")
        require(fillGap.frames[3] == CGRect(x: 0, y: 174, width: 162, height: 75),
                "Medium control must move below occupied cells")
        let changed = TrayGridMetrics(sizes: [.small, .small, .small, .medium], width: 336)
        require(changed.height < fillGap.height, "Shrinking an app does not release its occupied space")

        var seed: UInt64 = 0x50494e4348
        for count in 0...160 {
            let sizes: [TrayAppSize] = (0..<count).map { _ in
                seed = seed &* 6364136223846793005 &+ 1
                return TrayAppSize.allCases[Int((seed >> 32) % 3)]
            }
            for width: CGFloat in [1, 36, 240, 272, 336, 512] {
                validate(sizes, width: width)
            }
            for columns in [1, 2] { validate(sizes, width: 240, columns: columns) }
        }
        for size in TrayAppSize.allCases {
            let hundred = Array(repeating: size, count: 100)
            validate(hundred, width: 336)
            let layout = TrayGridMetrics(sizes: hundred, width: 336)
            let expectedRows = size == .small ? 25 : size == .medium ? 50 : 100
            require(layout.height == CGFloat(expectedRows) * 75 + CGFloat(expectedRows - 1) * 12,
                    "A large uniform list has an incorrect preferred height")
        }
        let zero = TrayGridMetrics(sizes: [.small, .medium, .large], width: 0)
        require(zero.height == 0 && zero.frames.allSatisfy { $0.width == 0 && $0.height == 0 },
                "Zero available width must not produce invalid or out-of-bounds frames")
        print("PASS: small/medium/large spans, gap filling, stable placement and resizing")
        print("PASS: 1,288 deterministic mixed-size fixtures; narrow widths and 1/2/4 columns")
        print("PASS: empty and 100-app lists; no overlaps, omissions, overflow or incorrect heights")
    }
}
