import Foundation
import CoreGraphics

/// Screen-local, top-left coordinates. No window, accessibility or process queries.
struct ClotheslineLayout: Equatable {
    struct Item: Equatable, Identifiable {
        let id: String
        let size: TrayAppSize
    }

    struct Card: Equatable, Identifiable {
        let item: Item
        /// Nominal attachment position; the cable may move horizontally under load.
        let centerX: CGFloat
        let size: CGSize
        var id: String { item.id }
        var hole: CGPoint { CGPoint(x: 6 * size.width / 64, y: 6 * size.height / 64) }
        var holes: [CGPoint] { [hole, CGPoint(x: size.width - hole.x, y: hole.y)] }
    }

    struct Pose {
        let card: Card
        let attachments: [CGPoint]
        let pivot: CGPoint
        let angle: Double
        let opacity: Double
        var fastening: Double = 1

        struct Hanger {
            let attachment: CGPoint
            let hole: CGPoint
        }
        var hangers: [Hanger] {
            zip(attachments, card.holes).map { Hanger(attachment: $0, hole: cardPoint($1)) }
        }

        func cardPoint(_ point: CGPoint) -> CGPoint {
            let radians = angle * .pi / 180
            let dx = point.x - card.hole.x, dy = point.y - card.hole.y
            return CGPoint(x: pivot.x + dx * cos(radians) - dy * sin(radians),
                           y: pivot.y + dx * sin(radians) + dy * cos(radians))
        }
        var center: CGPoint { cardPoint(CGPoint(x: card.size.width / 2, y: card.size.height / 2)) }
        var frame: CGRect {
            CGRect(x: pivot.x - card.hole.x, y: pivot.y - card.hole.y,
                   width: card.size.width, height: card.size.height)
        }
        var rotatedBounds: CGRect {
            let corners = [CGPoint.zero, CGPoint(x: card.size.width, y: 0),
                           CGPoint(x: 0, y: card.size.height),
                           CGPoint(x: card.size.width, y: card.size.height)].map(cardPoint)
            let xs = corners.map(\.x), ys = corners.map(\.y)
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }
    }

    struct Strand {
        let points: [CGPoint]
        var knot: Double = 1
    }

    struct Frame {
        let rope: [CGPoint]
        let poses: [Pose]
        var strands: [Strand]? = nil
        var draggedID: String? = nil
    }

    let bounds: CGRect
    let pages: [[Card]]
    let left: CGFloat
    let right: CGFloat
    let anchorY: CGFloat
    let hanger: CGFloat
    let scale: CGFloat
    let pagerY: CGFloat
    private let cache = ClotheslineSimulationCache()

    static let iconSide: CGFloat = 56
    static let cardPadding: CGFloat = 4

    init(items: [Item], bounds proposed: CGRect) {
        let width = proposed.width.isFinite ? max(1, proposed.width) : 1
        let height = proposed.height.isFinite ? max(1, proposed.height) : 1
        bounds = CGRect(x: proposed.minX.isFinite ? proposed.minX : 0,
                        y: proposed.minY.isFinite ? proposed.minY : 0, width: width, height: height)
        scale = min(1, width / 320, height / 440)
        let margin = max(20 * scale, width * 0.03)
        left = bounds.minX + margin
        right = bounds.maxX - margin
        // bounds starts at the lower edge of the menu bar (including the notch).
        anchorY = bounds.minY + 15 * scale
        hanger = 22 * scale
        pagerY = bounds.maxY - 48 * scale
        let span = right - left
        let side = (Self.iconSide + Self.cardPadding * 2) * scale
        // Reserve the full diagonal plus pendulum travel, including at the pins.
        let slot = 128 * scale
        let perPage = max(1, Int(span / slot))
        let startX = left
        var result: [[Card]] = []
        for start in stride(from: 0, to: items.count, by: perPage) {
            let batch = Array(items[start..<min(items.count, start + perPage)])
            let spacing = span / CGFloat(batch.count + 1)
            result.append(batch.enumerated().map { index, item in
                Card(item: item, centerX: startX + spacing * CGFloat(index + 1),
                     size: CGSize(width: side, height: side))
            })
        }
        pages = result
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.bounds == rhs.bounds && lhs.pages == rhs.pages }

    static func cardSize(_ size: TrayAppSize) -> CGSize {
        // Organizer size preferences do not change the hanging icon cards.
        CGSize(width: iconSide + 2 * cardPadding, height: iconSide + 2 * cardPadding)
    }

    func cards(on page: Int) -> [Card] {
        guard pages.indices.contains(page) else { return [] }
        return pages[page]
    }

    func frame(page: Int, elapsed: TimeInterval) -> Frame {
        let frames = trajectory(page: page)
        let time = elapsed.isFinite ? max(0, elapsed) : ClotheslineMotion.duration
        let position = min(Double(frames.count - 1), min(time, ClotheslineMotion.duration) * 60)
        let index = Int(position)
        guard index + 1 < frames.count else { return frames[index] }
        let a = frames[index], b = frames[index + 1], t = CGFloat(position - Double(index))
        func blend(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        return Frame(rope: zip(a.rope, b.rope).map(blend), poses: zip(a.poses, b.poses).map { a, b in
            Pose(card: a.card, attachments: zip(a.attachments, b.attachments).map(blend), pivot: blend(a.pivot, b.pivot),
                 angle: a.angle + (b.angle - a.angle) * Double(t), opacity: a.opacity + (b.opacity - a.opacity) * Double(t))
        })
    }

    func settlingDuration(page: Int) -> TimeInterval { Double(trajectory(page: page).count - 1) / 60 }

    private func trajectory(page: Int) -> [Frame] {
        if let frames = cache.pages[page] { return frames }
        let frames = ClotheslinePhysics(layout: self, cards: cards(on: page)).run()
        cache.pages[page] = frames
        return frames
    }

    func rope(page: Int, elapsed: TimeInterval) -> [CGPoint] { frame(page: page, elapsed: elapsed).rope }
    func poses(page: Int, elapsed: TimeInterval) -> [Pose] { frame(page: page, elapsed: elapsed).poses }

    func ropeY(at x: CGFloat, page: Int, elapsed: TimeInterval) -> CGFloat {
        let points = rope(page: page, elapsed: elapsed)
        for (a, b) in zip(points, points.dropFirst()) where x <= b.x {
            let t = min(1, max(0, (x - a.x) / max(0.0001, b.x - a.x)))
            return a.y + (b.y - a.y) * t
        }
        return anchorY
    }
}

private final class ClotheslineSimulationCache {
    var pages: [Int: [ClotheslineLayout.Frame]] = [:]
}

/// Inextensible cable and rigid cards, solved together at 120 Hz. Both corner
/// ties transfer tension to the cable and torque to the card. No angle is fixed.
private struct ClotheslinePhysics {
    struct Node {
        var point: CGPoint
        var previous: CGPoint
        let inverseMass: CGFloat
    }
    struct Body {
        let card: ClotheslineLayout.Card
        let nodes: [Int]
        var center: CGPoint
        var previous: CGPoint
        var angle: CGFloat
        var previousAngle: CGFloat
        var inertia: CGFloat { (card.size.width * card.size.width + card.size.height * card.size.height) / 12 }
        func arm(_ side: Int) -> CGPoint {
            let hole = card.holes[side]
            let x = hole.x - card.size.width / 2, y = hole.y - card.size.height / 2
            return CGPoint(x: x * cos(angle) - y * sin(angle), y: x * sin(angle) + y * cos(angle))
        }
        func hole(_ side: Int) -> CGPoint {
            let arm = arm(side)
            return CGPoint(x: center.x + arm.x, y: center.y + arm.y)
        }
    }
    enum Constraint {
        case cable(Int)
        case hanger(body: Int, side: Int)
    }

    let layout: ClotheslineLayout
    let cards: [ClotheslineLayout.Card]
    private let dt: CGFloat = 1 / 120

    func run() -> [ClotheslineLayout.Frame] {
        let span = layout.right - layout.left
        let depth = min(layout.bounds.height * 0.16, span * 0.075)
        let length = span * (1 + 8 * pow(depth / span, 2) / 3)
        // Insert both attachment points into the cable instead of rounding them
        // onto a coarse grid, which could put two short ties too far apart.
        let tiePositions: [[CGFloat]] = cards.map { card in
            card.holes.map { (card.centerX + $0.x - card.size.width / 2 - layout.left) / span }
        }
        var positions: [CGFloat] = [0, 1] + tiePositions.flatMap { $0 }
        for i in 1..<24 {
            let position = CGFloat(i) / 24
            if positions.allSatisfy({ abs($0 - position) * span > 8 * layout.scale }) { positions.append(position) }
        }
        positions.sort()
        let lengths = zip(positions, positions.dropFirst()).map { ($1 - $0) * length }
        let segments = lengths.count
        let indices = tiePositions.map { pair in pair.map { positions.firstIndex(of: $0)! } }
        let weights = (1..<segments).map { (lengths[$0 - 1] + lengths[$0]) / 2 }
        let massScale = 0.55 / weights.reduce(0, +)
        let masses = weights.map { $0 * massScale }
        let unloaded = equilibrium(loads: masses, lengths: lengths)
        var nodes = unloaded.enumerated().map { index, point in
            Node(point: point, previous: point, inverseMass: index == 0 || index == segments ? 0 : 1 / masses[index - 1])
        }
        var bodies = zip(cards, indices).enumerated().map { index, pair -> Body in
            let (card, indices) = pair
            let a = nodes[indices[0]].point, b = nodes[indices[1]].point
            let angle = atan2(b.y - a.y, b.x - a.x)
            let sway = (index.isMultiple(of: 2) ? -6.0 : 6.0) * layout.scale
            let drop = sqrt(layout.hanger * layout.hanger - sway * sway)
            let inset = card.size.height / 2 - card.hole.y
            let center = CGPoint(x: (a.x + b.x) / 2 - sin(angle) * inset + sway,
                                 y: (a.y + b.y) / 2 + cos(angle) * inset + drop)
            return Body(card: card, nodes: indices, center: center, previous: center, angle: angle, previousAngle: angle)
        }
        // Spatial ordering keeps the coupled constraint matrix narrow even when
        // every card adds a second tie. Factor only that nonzero band below.
        var constraints: [Constraint] = []
        for node in nodes.indices {
            if node < segments { constraints.append(.cable(node)) }
            for body in bodies.indices {
                for side in 0..<2 where bodies[body].nodes[side] == node {
                    constraints.append(.hanger(body: body, side: side))
                }
            }
        }
        for _ in 0..<24 {
            if constrain(nodes: &nodes, bodies: &bodies, lengths: lengths, constraints: constraints) < 0.0001 * layout.scale { break }
        }
        for i in nodes.indices { nodes[i].previous = nodes[i].point }
        for i in bodies.indices { bodies[i].previous = bodies[i].center; bodies[i].previousAngle = bodies[i].angle }
        func snapshot(_ time: Double) -> ClotheslineLayout.Frame {
            .init(rope: nodes.map(\.point), poses: bodies.map { body in
                .init(card: body.card, attachments: body.nodes.map { nodes[$0].point }, pivot: body.hole(0),
                      angle: Double(body.angle * 180 / .pi), opacity: min(1, time / 0.16))
            })
        }
        var frames = [snapshot(0)]
        if cards.isEmpty { return frames }
        var quietSteps = 0
        let gravity = 980 * layout.scale
        let damping = exp(-3.2 * dt), cableDamping = exp(-10 * dt)
        for step in 1...Int(ClotheslineMotion.duration * 120) {
            for i in 1..<segments {
                let point = nodes[i].point
                nodes[i].point.x += (point.x - nodes[i].previous.x) * cableDamping
                nodes[i].point.y += (point.y - nodes[i].previous.y) * cableDamping + gravity * dt * dt
                nodes[i].previous = point
            }
            for i in bodies.indices {
                let center = bodies[i].center, angle = bodies[i].angle
                bodies[i].center.x += (center.x - bodies[i].previous.x) * damping
                bodies[i].center.y += (center.y - bodies[i].previous.y) * damping + gravity * dt * dt
                bodies[i].angle += (angle - bodies[i].previousAngle) * damping
                bodies[i].previous = center
                bodies[i].previousAngle = angle
            }
            for _ in 0..<24 {
                if constrain(nodes: &nodes, bodies: &bodies, lengths: lengths, constraints: constraints) < 0.0001 * layout.scale { break }
            }
            if step.isMultiple(of: 2) { frames.append(snapshot(Double(step) / 120)) }
            if step > 240 && step.isMultiple(of: 2) {
                let recent = frames.suffix(19)
                let bodyTravel = bodies.indices.map { i -> CGFloat in
                    let poses = recent.map { $0.poses[i] }
                    let centers = poses.map(\.center)
                    let xs = centers.map(\.x), ys = centers.map(\.y), angles = poses.map(\.angle)
                    return max(hypot(xs.max()! - xs.min()!, ys.max()! - ys.min()!),
                               CGFloat(angles.max()! - angles.min()!) * .pi / 180 * bodies[i].card.size.width)
                }.max() ?? 0
                let travel = nodes.indices.map { i -> CGFloat in
                    let xs = recent.map { $0.rope[i].x }, ys = recent.map { $0.rope[i].y }
                    return hypot(xs.max()! - xs.min()!, ys.max()! - ys.min()!)
                }.max() ?? 0
                // Two ties can exert horizontal as well as vertical forces.
                // Let their full coupled simulation find rest rather than
                // imposing the old single-point, vertical-load equilibrium.
                let quiet = travel < 0.2 * layout.scale && bodyTravel < 0.15 * layout.scale
                quietSteps = quiet ? quietSteps + 1 : 0
                if quietSteps >= 18 { break }
            }
        }
        return frames
    }

    /// Newton projection with the mass-weighted constraint Jacobian, including
    /// both forces on each rigid card and their independent torque arms.
    private func constrain(nodes: inout [Node], bodies: inout [Body], lengths: [CGFloat], constraints: [Constraint]) -> CGFloat {
        let count = constraints.count
        let nodeDOFs = nodes.count * 2
        let dofs = nodeDOFs + bodies.count * 3
        var jacobian = Array(repeating: [(row: Int, value: CGFloat)](), count: dofs)
        var inverseMass = Array(repeating: CGFloat.zero, count: dofs)
        var error = Array(repeating: CGFloat.zero, count: count)
        for i in nodes.indices {
            inverseMass[i * 2] = nodes[i].inverseMass
            inverseMass[i * 2 + 1] = nodes[i].inverseMass
        }
        for i in bodies.indices {
            let base = nodeDOFs + i * 3
            inverseMass[base] = 1; inverseMass[base + 1] = 1; inverseMass[base + 2] = 1 / bodies[i].inertia
        }
        for (row, constraint) in constraints.enumerated() {
            switch constraint {
            case .cable(let i):
                let dx = nodes[i + 1].point.x - nodes[i].point.x
                let dy = nodes[i + 1].point.y - nodes[i].point.y
                let distance = max(0.00001, hypot(dx, dy))
                let nx = dx / distance, ny = dy / distance
                error[row] = distance - lengths[i]
                jacobian[i * 2].append((row, -nx))
                jacobian[i * 2 + 1].append((row, -ny))
                jacobian[(i + 1) * 2].append((row, nx))
                jacobian[(i + 1) * 2 + 1].append((row, ny))
            case .hanger(let i, let side):
                let body = bodies[i], node = body.nodes[side], base = nodeDOFs + i * 3
                let hole = body.hole(side), arm = body.arm(side)
                let dx = hole.x - nodes[node].point.x, dy = hole.y - nodes[node].point.y
                let distance = max(0.00001, hypot(dx, dy))
                let nx = dx / distance, ny = dy / distance
                error[row] = distance - layout.hanger
                jacobian[node * 2].append((row, -nx))
                jacobian[node * 2 + 1].append((row, -ny))
                jacobian[base].append((row, nx))
                jacobian[base + 1].append((row, ny))
                jacobian[base + 2].append((row, arm.x * ny - arm.y * nx))
            }
        }
        var matrix = Array(repeating: CGFloat.zero, count: count * count)
        var bandwidth = 0
        for dof in 0..<dofs where inverseMass[dof] > 0 {
            for a in jacobian[dof] {
                for b in jacobian[dof] where a.row >= b.row {
                    matrix[a.row * count + b.row] += a.value * b.value * inverseMass[dof]
                    bandwidth = max(bandwidth, a.row - b.row)
                }
            }
        }
        // Banded Cholesky factorization, then forward/back substitution.
        for i in 0..<count {
            for j in max(0, i - bandwidth)...i {
                var value = matrix[i * count + j]
                for k in max(0, i - bandwidth)..<j { value -= matrix[i * count + k] * matrix[j * count + k] }
                matrix[i * count + j] = i == j ? sqrt(max(1e-10, value)) : value / matrix[j * count + j]
            }
        }
        var force = error
        for i in 0..<count {
            for j in max(0, i - bandwidth)..<i { force[i] -= matrix[i * count + j] * force[j] }
            force[i] /= matrix[i * count + i]
        }
        for i in (0..<count).reversed() {
            for j in (i + 1)..<min(count, i + bandwidth + 1) { force[i] -= matrix[j * count + i] * force[j] }
            force[i] /= matrix[i * count + i]
        }
        let correction = (0..<dofs).map { dof in
            inverseMass[dof] * jacobian[dof].reduce(CGFloat.zero) { $0 + $1.value * force[$1.row] }
        }
        for i in nodes.indices {
            nodes[i].point.x -= correction[i * 2]
            nodes[i].point.y -= correction[i * 2 + 1]
        }
        for i in bodies.indices {
            let base = nodeDOFs + i * 3
            bodies[i].center.x -= correction[base]
            bodies[i].center.y -= correction[base + 1]
            bodies[i].angle -= correction[base + 2]
        }
        return error.reduce(0) { max($0, abs($1)) }
    }

    /// Initialize the unloaded cable under its own weight. Each span has the
    /// same horizontal tension, and
    /// vertical tension changes by exactly the weight at each suspension node.
    /// Solve both endpoint closure equations for reaction and tension while
    /// preserving every segment's length. No fixed parabola or Gaussian dents.
    private func equilibrium(loads: [CGFloat], lengths: [CGFloat]) -> [CGPoint] {
        let total = loads.reduce(0, +)
        var accumulated: CGFloat = 0
        var cumulative: [CGFloat] = [0]
        for load in loads { accumulated += load; cumulative.append(accumulated) }
        func spans(_ tension: CGFloat) -> [CGPoint] {
            var low: CGFloat = 0, high = total
            for _ in 0..<36 {
                let reaction = (low + high) / 2
                let drop = zip(cumulative, lengths).reduce(CGFloat.zero) { result, span in
                    let (weight, segmentLength) = span
                    let vertical = reaction - weight
                    return result + segmentLength * vertical / hypot(tension, vertical)
                }
                if drop > 0 { high = reaction } else { low = reaction }
            }
            let reaction = (low + high) / 2
            return zip(cumulative, lengths).map { weight, segmentLength in
                let vertical = reaction - weight, force = hypot(tension, vertical)
                return CGPoint(x: segmentLength * tension / force, y: segmentLength * vertical / force)
            }
        }
        var low: CGFloat = 0.0001, high = max(1, total * 1000)
        for _ in 0..<40 {
            let tension = (low + high) / 2
            if spans(tension).reduce(0, { $0 + $1.x }) > layout.right - layout.left { high = tension }
            else { low = tension }
        }
        var point = CGPoint(x: layout.left, y: layout.anchorY)
        var points = [point]
        for delta in spans((low + high) / 2) {
            point.x += delta.x; point.y += delta.y
            points.append(point)
        }
        points[points.count - 1] = CGPoint(x: layout.right, y: layout.anchorY)
        return points
    }
}

enum ClotheslineMotion {
    static let duration: TimeInterval = 8
    static let pageFadeDuration: TimeInterval = 0.12
}

/// Tokens invalidate delayed transitions when closing/reopening or refreshing a page.
struct ClotheslineSession {
    private(set) var isShown = false
    private(set) var page = 0
    private(set) var generation: UInt = 0

    @discardableResult mutating func open() -> Bool {
        guard !isShown else { return false }
        isShown = true
        page = 0
        generation &+= 1
        return true
    }

    mutating func close() {
        isShown = false
        generation &+= 1
    }

    @discardableResult mutating func select(_ requested: Int, count: Int) -> UInt {
        page = min(max(0, requested), max(0, count - 1))
        generation &+= 1
        return generation
    }

    func accepts(_ token: UInt) -> Bool { isShown && generation == token }
}
