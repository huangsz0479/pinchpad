import SwiftUI

/// The same packing calculation drives both the window height and SwiftUI layout.
/// Items keep their input identities; smaller controls can fill earlier free cells.
struct TrayGridMetrics {
    let frames: [CGRect]
    let height: CGFloat
    let width: CGFloat
    let columns: Int
    let spacing: CGFloat
    let unit: CGFloat

    init(sizes: [TrayAppSize], width proposedWidth: CGFloat,
         columns requestedColumns: Int = 4, spacing proposedSpacing: CGFloat = 12) {
        columns = max(1, requestedColumns)
        width = proposedWidth.isFinite ? max(0, proposedWidth) : 0
        // Keep both cells and gaps within even very narrow display fixtures.
        let desiredSpacing = proposedSpacing.isFinite ? max(0, proposedSpacing) : 0
        spacing = min(desiredSpacing, width / CGFloat(columns * 2 - 1))
        unit = max(0, (width - CGFloat(columns - 1) * spacing) / CGFloat(columns))

        var occupied: [[Bool]] = []
        var result: [CGRect] = []
        result.reserveCapacity(sizes.count)
        for size in sizes {
            let span = min(columns, size.columns)
            var row = 0
            var placement: (row: Int, column: Int)?
            while placement == nil {
                for column in 0...(columns - span) {
                    let fits = (row..<(row + size.rows)).allSatisfy { y in
                        y >= occupied.count || (column..<(column + span)).allSatisfy { !occupied[y][$0] }
                    }
                    if fits {
                        placement = (row, column)
                        break
                    }
                }
                if placement == nil { row += 1 }
            }
            let position = placement!
            while occupied.count < position.row + size.rows {
                occupied.append(Array(repeating: false, count: columns))
            }
            for y in position.row..<(position.row + size.rows) {
                for x in position.column..<(position.column + span) { occupied[y][x] = true }
            }
            result.append(CGRect(
                x: CGFloat(position.column) * (unit + spacing),
                y: CGFloat(position.row) * (unit + spacing),
                width: CGFloat(span) * unit + CGFloat(span - 1) * spacing,
                height: CGFloat(size.rows) * unit + CGFloat(size.rows - 1) * spacing
            ))
        }
        frames = result
        height = occupied.isEmpty ? 0 : CGFloat(occupied.count) * unit + CGFloat(occupied.count - 1) * spacing
    }
}

private struct TrayAppSizeKey: LayoutValueKey {
    static let defaultValue: TrayAppSize = .medium
}

extension View {
    func traySize(_ size: TrayAppSize) -> some View {
        layoutValue(key: TrayAppSizeKey.self, value: size)
    }
}

/// Four-column Control Center grid: small 1×1, medium 2×1, large 2×2.
struct TrayGridLayout: Layout {
    var columns: Int = 4
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 336
        let metrics = metrics(for: subviews, width: width)
        return CGSize(width: width, height: metrics.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let metrics = metrics(for: subviews, width: bounds.width)
        for (index, subview) in subviews.enumerated() {
            let frame = metrics.frames[index]
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func metrics(for subviews: Subviews, width: CGFloat) -> TrayGridMetrics {
        TrayGridMetrics(sizes: subviews.map { $0[TrayAppSizeKey.self] },
                        width: width, columns: columns, spacing: spacing)
    }
}
