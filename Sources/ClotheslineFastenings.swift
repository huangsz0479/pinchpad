import SwiftUI

/// A real cutout, shared by the card mask and its metal eyelet.
struct HangingCardShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = rect.width / 64
        var path = Path(roundedRect: rect, cornerRadius: 10 * scale)
        path.addEllipse(in: CGRect(x: rect.minX + 3.5 * scale, y: rect.minY + 3.5 * scale,
                                   width: 5 * scale, height: 5 * scale))
        path.addEllipse(in: CGRect(x: rect.maxX - 8.5 * scale, y: rect.minY + 3.5 * scale,
                                   width: 5 * scale, height: 5 * scale))
        return path
    }
}

enum ClotheslineFastenings {
    static func nail(at point: CGPoint, scale: CGFloat, in context: GraphicsContext) {
        var shaded = context
        shaded.addFilter(.shadow(color: .black.opacity(0.45), radius: 1.5 * scale, x: 0, y: 2 * scale))
        let head = Path(ellipseIn: CGRect(x: point.x - 4 * scale, y: point.y - 4 * scale,
                                         width: 8 * scale, height: 8 * scale))
        shaded.fill(head, with: .linearGradient(Gradient(colors: [.white, Color(white: 0.55), Color(white: 0.28)]),
            startPoint: CGPoint(x: point.x - 3 * scale, y: point.y - 4 * scale),
            endPoint: CGPoint(x: point.x + 3 * scale, y: point.y + 4 * scale)))
        context.stroke(head, with: .color(.black.opacity(0.65)), lineWidth: 0.7 * scale)
        var slot = Path()
        slot.move(to: CGPoint(x: point.x - 2 * scale, y: point.y + scale))
        slot.addLine(to: CGPoint(x: point.x + 2 * scale, y: point.y - scale))
        context.stroke(slot, with: .color(.black.opacity(0.55)), lineWidth: 0.8 * scale)
    }

    static func eyelet(_ pose: ClotheslineLayout.Pose, scale: CGFloat, in context: GraphicsContext) {
        for hole in pose.card.holes { eyelet(pose, hole: hole, scale: scale, in: context) }
    }

    private static func eyelet(_ pose: ClotheslineLayout.Pose, hole: CGPoint, scale: CGFloat, in context: GraphicsContext) {
        var context = context
        context.opacity *= pose.opacity
        let point = pose.cardPoint(hole)
        let ring = Path(ellipseIn: CGRect(x: point.x - 2.7 * scale, y: point.y - 2.7 * scale,
                                         width: 5.4 * scale, height: 5.4 * scale))
        context.stroke(ring, with: .color(.black.opacity(0.6)), lineWidth: 1.4 * scale)
        context.stroke(ring, with: .color(Color(white: 0.85)), lineWidth: 0.7 * scale)
        // The front loop emerges from the hole and wraps the upper card edge.
        let top = pose.cardPoint(CGPoint(x: hole.x, y: 0))
        let side: CGFloat = hole.x < pose.card.size.width / 2 ? -1 : 1
        var tie = Path()
        tie.move(to: point)
        tie.addQuadCurve(to: top, control: CGPoint(x: top.x + side * 3 * scale, y: point.y - 2 * scale))
        guard pose.fastening > 0 else { return }
        // The loop winds through the eyelet before the final knot takes load.
        let loop = tie.trimmedPath(from: 0, to: pose.fastening)
        context.stroke(loop, with: .color(Color(red: 0.78, green: 0.62, blue: 0.39)),
                       style: StrokeStyle(lineWidth: 1.4 * scale, lineCap: .round))
        HempRope.knot(at: top, radius: 1.5 * scale * pose.fastening, in: context)
    }
}
