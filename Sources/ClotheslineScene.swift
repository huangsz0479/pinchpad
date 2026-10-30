import SwiftUI

/// The production composition is also rendered offscreen with fixture cards.
/// Card pivots and the rope are sampled together, so attachments cannot drift apart.
struct ClotheslineScene<CardContent: View>: View {
    let layout: ClotheslineLayout
    let page: Int
    let elapsed: TimeInterval
    var selectedID: String? = nil
    var liveFrame: ClotheslineLayout.Frame? = nil
    @ViewBuilder var card: (ClotheslineLayout.Card) -> CardContent

    var body: some View {
        let frame = liveFrame ?? layout.frame(page: page, elapsed: elapsed)
        let poses = frame.poses
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                HempRope.draw(frame.rope, width: 3.2 * layout.scale, in: context)
                if let strands = frame.strands {
                    for strand in strands {
                        HempRope.draw(strand.points, width: 1.5 * layout.scale, in: context)
                        if let point = strand.points.first, strand.knot > 0 {
                            HempRope.knot(at: point, radius: 2.2 * layout.scale, in: context)
                        }
                    }
                } else {
                    for pose in poses {
                        var hangerContext = context
                        hangerContext.opacity *= pose.opacity
                        for hanger in pose.hangers {
                            HempRope.draw([hanger.attachment, hanger.hole], width: 1.5 * layout.scale, in: hangerContext)
                            HempRope.knot(at: hanger.attachment, radius: 2.2 * layout.scale, in: hangerContext)
                        }
                    }
                }
                let anchors = [CGPoint(x: layout.left, y: layout.anchorY),
                               CGPoint(x: layout.right, y: layout.anchorY)]
                for point in anchors {
                    HempRope.knot(at: point, radius: 4 * layout.scale, in: context)
                    ClotheslineFastenings.nail(at: point, scale: layout.scale, in: context)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            ForEach(poses, id: \.card.id) { pose in
                card(pose.card)
                    .frame(width: 64, height: 64)
                    .scaleEffect(layout.scale)
                    .frame(width: pose.card.size.width, height: pose.card.size.height)
                    .overlay {
                        if selectedID == pose.card.id {
                            RoundedRectangle(cornerRadius: 10 * layout.scale)
                                .strokeBorder(Color.accentColor, lineWidth: 3 * layout.scale)
                        }
                    }
                    .mask(HangingCardShape().fill(style: FillStyle(eoFill: true)))
                    .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 2)
                    .rotationEffect(.degrees(pose.angle), anchor: UnitPoint(
                        x: pose.card.hole.x / pose.card.size.width, y: pose.card.hole.y / pose.card.size.height))
                    .position(x: pose.frame.midX, y: pose.frame.midY)
                    .opacity(pose.opacity)
                    .zIndex(frame.draggedID == pose.card.id ? 1 : 0)
                    .accessibilityAddTraits(selectedID == pose.card.id ? .isSelected : [])
            }

            Canvas { context, _ in
                for pose in poses { ClotheslineFastenings.eyelet(pose, scale: layout.scale, in: context) }
            }
            .zIndex(2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

struct ClotheslinePager: View {
    let page: Int
    let count: Int
    var turnPage: (Int) -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button { turnPage(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 28, height: 28)
            }
            .disabled(page == 0)
            .accessibilityLabel("上一页")
            Text("\(page + 1) / \(count)")
                .font(.system(size: 13, weight: .medium)).monospacedDigit()
                .accessibilityLabel("第 \(page + 1) 页，共 \(count) 页")
            Button { turnPage(1) } label: {
                Image(systemName: "chevron.right").frame(width: 28, height: 28)
            }
            .disabled(page >= count - 1)
            .accessibilityLabel("下一页")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 1))
    }
}
