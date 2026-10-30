import SwiftUI

/// Vector fibres follow arc length, so the twist stays the same size on curves,
/// vertical hangers and Retina displays. It is drawn only while the scene moves.
enum HempRope {
    private static let edge = Color(red: 0.36, green: 0.25, blue: 0.13)
    private static let body = Color(red: 0.69, green: 0.52, blue: 0.31)
    private static let light = Color(red: 0.91, green: 0.77, blue: 0.53)
    private static let groove = Color(red: 0.48, green: 0.34, blue: 0.19)

    private struct Sample {
        let point: CGPoint
        let normal: CGVector
        let distance: CGFloat
        func offset(_ amount: CGFloat) -> CGPoint {
            CGPoint(x: point.x + normal.dx * amount, y: point.y + normal.dy * amount)
        }
    }

    static func draw(_ points: [CGPoint], width: CGFloat, in context: GraphicsContext) {
        guard points.count > 1 else { return }
        var center = Path()
        center.addLines(points)
        let stroke = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        var shaded = context
        shaded.translateBy(x: 0, y: 0.7)
        shaded.stroke(center, with: .color(edge), style: stroke)
        context.stroke(center, with: .color(body),
                       style: StrokeStyle(lineWidth: width - 0.8, lineCap: .round, lineJoin: .round))

        let samples = resample(points)
        let pitch = width * 2.1
        // Three twisted bundles cross alternately on the front of the rope.
        // Fine parallel fibres break up the otherwise plastic-looking bands.
        for strand in 0..<3 {
            let phase = CGFloat(strand) * 2 * .pi / 3
            for fibre in [0] {
                var path = Path()
                var connected = false
                for sample in samples {
                    let angle = sample.distance / pitch * 2 * .pi + phase
                    guard cos(angle) > -0.1 else { connected = false; continue }
                    let offset = sin(angle) * width * 0.31 + CGFloat(fibre) * width * 0.10
                    let point = sample.offset(offset)
                    if connected { path.addLine(to: point) } else { path.move(to: point) }
                    connected = true
                }
                context.stroke(path, with: .color(fibre == 0 ? light : groove.opacity(0.75)),
                               style: StrokeStyle(lineWidth: fibre == 0 ? width * 0.19 : width * 0.075,
                                                  lineCap: .round, lineJoin: .round))
            }
        }
        var fuzz = Path()
        for (index, sample) in samples.enumerated() where index.isMultiple(of: 23) {
            let side: CGFloat = (index / 23).isMultiple(of: 2) ? 1 : -1
            fuzz.move(to: sample.offset(side * width * 0.42))
            fuzz.addLine(to: sample.offset(side * (width * 0.5 + 0.7)))
        }
        context.stroke(fuzz, with: .color(light.opacity(0.6)), lineWidth: 0.45)
    }

    static func knot(at point: CGPoint, radius: CGFloat, in context: GraphicsContext) {
        let ellipse = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius * 0.7,
                                            width: radius * 2, height: radius * 1.4))
        context.fill(ellipse, with: .color(body))
        context.stroke(ellipse, with: .color(edge.opacity(0.85)), lineWidth: 0.7)
        var wraps = Path()
        for x in [-0.45, 0.0, 0.45] {
            wraps.move(to: CGPoint(x: point.x + radius * x - 0.7, y: point.y + radius * 0.45))
            wraps.addLine(to: CGPoint(x: point.x + radius * x + 0.7, y: point.y - radius * 0.45))
        }
        context.stroke(wraps, with: .color(light), style: StrokeStyle(lineWidth: 0.65, lineCap: .round))
    }

    private static func resample(_ points: [CGPoint]) -> [Sample] {
        var samples: [Sample] = []
        var traversed: CGFloat = 0
        var next: CGFloat = 0
        for (a, b) in zip(points, points.dropFirst()) {
            let dx = b.x - a.x, dy = b.y - a.y
            let length = hypot(dx, dy)
            guard length > 0 else { continue }
            while next <= traversed + length {
                let t = (next - traversed) / length
                samples.append(Sample(point: CGPoint(x: a.x + dx * t, y: a.y + dy * t),
                                      normal: CGVector(dx: -dy / length, dy: dx / length), distance: next))
                next += 1.4
            }
            traversed += length
        }
        return samples
    }
}
