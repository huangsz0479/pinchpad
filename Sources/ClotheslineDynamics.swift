import Foundation
import CoreGraphics

/// A live, fixed-step cable/rigid-body simulation. Rendering never runs a whole
/// trajectory in advance. Every constraint applies equal and opposite impulses
/// to the cable and card, including the torque of each corner fastening.
final class ClotheslineDynamics {
    private struct Particle {
        var p: CGPoint
        var previous: CGPoint
        var inverseMass: CGFloat
    }
    private struct Support {
        var u: CGFloat
        var length: CGFloat
    }
    private struct LooseEnd {
        var particles: [Particle]
        var length: CGFloat
    }
    private struct Body {
        let card: ClotheslineLayout.Card
        var center: CGPoint
        var previous: CGPoint
        var angle: CGFloat = 0
        var previousAngle: CGFloat = 0
        var supports: [Support]
        var loose: [LooseEnd] = []
        var detached = false
        var tying: CGFloat? = nil
        var tyingFrom: [Support] = []
        var tyingTo: [Support] = []
        var heldCenter: CGPoint? = nil
        var inertia: CGFloat { (card.size.width * card.size.width + card.size.height * card.size.height) / 12 }
        func arm(_ side: Int) -> CGPoint {
            let hole = card.holes[side]
            let x = hole.x - card.size.width / 2, y = hole.y - card.size.height / 2
            return CGPoint(x: x * cos(angle) - y * sin(angle), y: x * sin(angle) + y * cos(angle))
        }
        func hole(_ side: Int) -> CGPoint { center + arm(side) }
    }
    private struct Drag {
        let body: Int
        let offset: CGPoint
        let start: CGPoint
        var target: CGPoint
    }

    let layout: ClotheslineLayout
    private var nodes: [Particle] = []
    private var lengths: [CGFloat] = []
    private var coordinates: [CGFloat] = []
    private var baseCoordinates: [CGFloat] = []
    private var cableLength: CGFloat = 1
    private var bodies: [Body] = []
    private var drag: Drag?
    private var accumulator: TimeInterval = 0
    private var priorFrame: ClotheslineLayout.Frame?
    private var quietTime: CGFloat = 0
    private var quietMin: [CGPoint] = []
    private var quietMax: [CGPoint] = []
    private var age: CGFloat = 0
    private let dt: CGFloat = 1 / 120
    private(set) var isResting = false
    var draggedID: String? { drag.map { bodies[$0.body].card.id } }
    var isInteracting: Bool { drag != nil || bodies.contains { $0.tying != nil } }
    private var gravity: CGFloat { 980 * layout.scale }

    init(layout: ClotheslineLayout, page: Int, positions: [String: ClotheslinePosition] = [:]) {
        self.layout = layout
        let segments = max(24, min(64, Int((layout.right - layout.left) / 32)))
        let span = layout.right - layout.left
        let depth = min(layout.bounds.height * 0.13, span * 0.07)
        nodes = (0...segments).map { i in
            let t = CGFloat(i) / CGFloat(segments)
            let p = CGPoint(x: layout.left + span * t, y: layout.anchorY + 4 * depth * t * (1 - t))
            return Particle(p: p, previous: p, inverseMass: i == 0 || i == segments ? 0 : CGFloat(segments - 1) / 1.4)
        }
        lengths = zip(nodes, nodes.dropFirst()).map { ($1.p - $0.p).length }
        cableLength = lengths.reduce(0, +)
        coordinates = [0]
        for length in lengths { coordinates.append(coordinates.last! + length / cableLength) }
        coordinates[coordinates.count - 1] = 1
        baseCoordinates = coordinates
        for card in layout.cards(on: page) {
            let saved = positions[card.id].flatMap { $0.isValid ? $0 : nil }
            let x = saved.map { layout.bounds.minX + $0.x * layout.bounds.width } ?? card.centerX
            let halfHoleSpan = card.size.width / 2 - card.hole.x
            let supports = [-halfHoleSpan, halfHoleSpan].map { dx -> Support in
                Support(u: coordinate(atX: x + dx), length: layout.hanger)
            }
            let a = attachment(supports[0].u), b = attachment(supports[1].u)
            let y = saved.map { layout.bounds.minY + $0.y * layout.bounds.height }
                ?? (max(a.y, b.y) + layout.hanger + card.size.height / 2 - card.hole.y)
            let center = clamped(CGPoint(x: x, y: y), card: card)
            var body = Body(card: card, center: center, previous: center, supports: supports)
            for side in 0..<2 {
                body.supports[side].length = (body.hole(side) - attachment(supports[side].u)).length
            }
            // A small initial horizontal velocity, then only gravity/constraints.
            body.previous.x -= (bodies.count.isMultiple(of: 2) ? 20 : -20) * layout.scale * dt
            bodies.append(body)
        }
        remesh()
    }

    func frame() -> ClotheslineLayout.Frame {
        let current = snapshot()
        guard !isResting, let priorFrame, priorFrame.rope.count == current.rope.count else { return current }
        let t = CGFloat(min(1, max(0, accumulator / Double(dt))))
        func blend(_ a: CGPoint, _ b: CGPoint) -> CGPoint { a * (1 - t) + b * t }
        let poses = zip(priorFrame.poses, current.poses).map { a, b in
            ClotheslineLayout.Pose(card: b.card, attachments: zip(a.attachments, b.attachments).map(blend),
                pivot: blend(a.pivot, b.pivot), angle: a.angle + (b.angle - a.angle) * Double(t),
                opacity: b.opacity, fastening: b.fastening)
        }
        let strands: [ClotheslineLayout.Strand]?
        if let a = priorFrame.strands, let b = current.strands, a.count == b.count {
            strands = zip(a, b).map { a, b in
                .init(points: a.points.count == b.points.count ? zip(a.points, b.points).map(blend) : b.points, knot: b.knot)
            }
        } else { strands = current.strands }
        return .init(rope: zip(priorFrame.rope, current.rope).map(blend), poses: poses,
                     strands: strands, draggedID: current.draggedID)
    }

    private func snapshot() -> ClotheslineLayout.Frame {
        let poses = bodies.map { body in
            ClotheslineLayout.Pose(card: body.card, attachments: body.supports.map { attachment($0.u) },
                pivot: body.hole(0), angle: Double(body.angle * 180 / .pi), opacity: 1,
                fastening: body.detached ? Double(body.tying.map { min(1, max(0, ($0 - 0.35) / 0.45)) } ?? 0) : 1)
        }
        var strands: [ClotheslineLayout.Strand] = []
        for body in bodies {
            for side in 0..<2 {
                let top = attachment(body.supports[side].u)
                if body.detached {
                    strands.append(.init(points: body.loose[side].particles.map(\.p), knot: 1))
                    if body.tying == nil {
                        // The card keeps a short frayed tail at the severed eyelet.
                        let hole = body.hole(side)
                        strands.append(.init(points: [hole, hole + CGPoint(x: sin(body.angle) * 4 * layout.scale,
                                                                           y: -5 * layout.scale)], knot: 0))
                    }
                } else {
                    strands.append(.init(points: [top, body.hole(side)], knot: 1))
                }
            }
        }
        return .init(rope: nodes.map(\.p), poses: poses, strands: strands, draggedID: draggedID)
    }

    /// Inverse rotation means only the visible card, not its bounding box, is hit.
    func hitTest(_ point: CGPoint) -> String? {
        for body in bodies.reversed() {
            let delta = point - body.center
            let p = CGPoint(x: delta.x * cos(body.angle) + delta.y * sin(body.angle),
                            y: -delta.x * sin(body.angle) + delta.y * cos(body.angle))
            if abs(p.x) <= body.card.size.width / 2 && abs(p.y) <= body.card.size.height / 2 { return body.card.id }
        }
        return nil
    }

    @discardableResult
    func beginDrag(id: String, at point: CGPoint) -> Bool {
        guard drag == nil, let i = bodies.firstIndex(where: { $0.card.id == id }) else { return false }
        if bodies[i].tying != nil { bodies[i].tying = nil; bodies[i].heldCenter = nil }
        drag = Drag(body: i, offset: point - bodies[i].center, start: bodies[i].center, target: bodies[i].center)
        wake()
        return true
    }

    func moveDrag(to point: CGPoint) {
        guard var drag else { return }
        drag.target = clamped(point - drag.offset, card: bodies[drag.body].card)
        self.drag = drag
        // Pulling loads the whole rope first. A short, finite break strain then
        // releases that load, so the rebound propagates through the actual cable.
        if !bodies[drag.body].detached, (drag.target - drag.start).length > 22 * layout.scale {
            detach(drag.body)
        }
        wake()
    }

    @discardableResult
    func endDrag() -> (id: String, position: ClotheslinePosition)? {
        guard let drag else { return nil }
        let i = drag.body
        self.drag = nil
        // Even a short rearrangement gets a new pair of continuously positioned
        // supports; no slot, grid rounding or app-order exchange is involved.
        if !bodies[i].detached { detach(i) }
        let center = clamped(drag.target, card: bodies[i].card)
        bodies[i].heldCenter = center
        bodies[i].tying = 0
        bodies[i].tyingFrom = bodies[i].supports
        let half = bodies[i].card.size.width / 2 - bodies[i].card.hole.x
        bodies[i].tyingTo = [-half, half].map { dx in
            let u = coordinate(atX: center.x + dx)
            let hole = CGPoint(x: center.x + dx, y: center.y - bodies[i].card.size.height / 2 + bodies[i].card.hole.y)
            return Support(u: u, length: max(10 * layout.scale, (hole - attachment(u)).length))
        }
        remesh()
        wake()
        return (bodies[i].card.id, normalized(center))
    }

    func cancelDrag() { _ = endDrag() }

    /// Accumulate true display time; a bounded catch-up avoids a spiral after
    /// sleep/debugger stalls. The solver always uses the same 120 Hz time step.
    func advance(by elapsed: TimeInterval) {
        guard elapsed.isFinite, elapsed > 0, !isResting else { return }
        accumulator += min(elapsed, 1 / 15)
        while accumulator >= Double(dt) {
            priorFrame = snapshot()
            step()
            accumulator -= Double(dt)
        }
    }

    func settle() {
        cancelDrag()
        for _ in 0..<1200 where !isResting { step() }
    }

    private func wake() { quietTime = 0; isResting = false }

    private func normalized(_ center: CGPoint) -> ClotheslinePosition {
        .init(x: min(1, max(0, (center.x - layout.bounds.minX) / layout.bounds.width)),
              y: min(1, max(0, (center.y - layout.bounds.minY) / layout.bounds.height)))
    }

    private func clamped(_ proposed: CGPoint, card: ClotheslineLayout.Card) -> CGPoint {
        let half = card.size.width / 2 + 6 * layout.scale
        let x = min(layout.right - half, max(layout.left + half, proposed.x))
        let supportY = max(attachment(coordinate(atX: x - half)).y, attachment(coordinate(atX: x + half)).y)
        let bottom = layout.pagerY - card.size.height / 2 - 18 * layout.scale
        let top = min(bottom, supportY + card.size.height / 2 + 10 * layout.scale)
        return CGPoint(x: x, y: min(bottom, max(top, proposed.y)))
    }

    private func coordinate(atX x: CGFloat) -> CGFloat {
        for i in 0..<(nodes.count - 1) where x <= nodes[i + 1].p.x {
            let t = min(1, max(0, (x - nodes[i].p.x) / max(0.0001, nodes[i + 1].p.x - nodes[i].p.x)))
            return coordinates[i] + (coordinates[i + 1] - coordinates[i]) * t
        }
        return 1
    }

    private func segment(_ u: CGFloat) -> (Int, CGFloat) {
        var low = 0, high = coordinates.count - 1
        while low + 1 < high {
            let mid = (low + high) / 2
            if coordinates[mid] <= u { low = mid } else { high = mid }
        }
        return (low, min(1, max(0, (u - coordinates[low]) / max(1e-10, coordinates[low + 1] - coordinates[low]))))
    }

    /// Knots must be real cable vertices: a load midway along a straight rigid
    /// segment would imply bending stiffness and produce nonphysical flutter.
    /// Rebuild only when tying changes topology, preserving arc length/velocity.
    private func remesh() {
        let knots = bodies.flatMap { body in
            body.supports.map(\.u) + (body.tying != nil ? body.tyingTo.map(\.u) : [])
        }
        var values = baseCoordinates.filter { u in
            u == 0 || u == 1 || knots.allSatisfy { abs($0 - u) * cableLength > 8 * layout.scale }
        } + knots
        values.sort()
        var unique: [CGFloat] = []
        for value in values where unique.last.map({ abs($0 - value) > 1e-7 }) ?? true { unique.append(value) }
        let replacement = unique.map { u -> Particle in
            let (i, t) = segment(u)
            return Particle(p: nodes[i].p * (1 - t) + nodes[i + 1].p * t,
                            previous: nodes[i].previous * (1 - t) + nodes[i + 1].previous * t, inverseMass: 0)
        }
        coordinates = unique
        nodes = replacement
        lengths = zip(unique, unique.dropFirst()).map { ($1 - $0) * cableLength }
        for i in 1..<(nodes.count - 1) {
            let mass = (lengths[i - 1] + lengths[i]) / (2 * cableLength) * 1.4
            nodes[i].inverseMass = 1 / mass
        }
        priorFrame = nil
    }

    private func attachment(_ u: CGFloat) -> CGPoint {
        let (i, t) = segment(u)
        return nodes[i].p * (1 - t) + nodes[i + 1].p * t
    }

    private func detach(_ i: Int) {
        bodies[i].detached = true
        bodies[i].loose = (0..<2).map { side in
            let support = bodies[i].supports[side]
            let start = attachment(support.u), end = bodies[i].hole(side)
            let particles = (0...8).map { j -> Particle in
                let t = CGFloat(j) / 8
                let point = start * (1 - t) + end * t
                return Particle(p: point, previous: point, inverseMass: j == 0 ? 0 : 1)
            }
            return LooseEnd(particles: particles, length: support.length)
        }
    }

    private func step() {
        age += dt
        let cableDamping = exp(-10 * dt), cardDamping = exp(-3.4 * dt)
        for i in nodes.indices where nodes[i].inverseMass > 0 {
            let p = nodes[i].p
            nodes[i].p += (p - nodes[i].previous) * cableDamping + CGPoint(x: 0, y: gravity * dt * dt)
            nodes[i].previous = p
        }
        for i in bodies.indices {
            var body = bodies[i]
            let p = body.center, angle = body.angle
            var acceleration = CGPoint(x: 0, y: gravity)
            let target = drag?.body == i ? drag?.target : body.heldCenter
            if let target {
                // A damped hand spring avoids teleporting the rigid body on fast
                // pointer updates. Gravity is balanced by the hand while held.
                let velocity = (p - body.previous) / dt
                acceleration = (target - p) * 1600 - velocity * 64
            }
            body.center += (p - body.previous) * cardDamping + acceleration * (dt * dt)
            body.previous = p
            body.angle += (angle - body.previousAngle) * cardDamping
            if target != nil { body.angle += (-body.angle * 100 - (angle - body.previousAngle) / dt * 16) * dt * dt }
            body.previousAngle = angle
            if let time = body.tying {
                let t = time + dt
                body.tying = t
                // Critically damped reel: zero initial speed, no easing overshoot.
                let progress = 1 - (1 + 14 * t) * exp(-14 * t)
                for side in 0..<2 {
                    let a = body.tyingFrom[side], b = body.tyingTo[side]
                    body.supports[side] = Support(u: a.u + (b.u - a.u) * progress,
                                                 length: a.length + (b.length - a.length) * progress)
                }
            }
            bodies[i] = body
        }
        let constraints = constraintOrder()
        for _ in 0..<24 {
            if project(constraints) < 0.0001 * layout.scale { break }
        }
        var retied = false
        for i in bodies.indices where bodies[i].detached {
            advanceLooseEnds(i)
            if let time = bodies[i].tying, time >= 0.8 {
                // The reel reaches the actual holes before a load-bearing knot
                // replaces the hand. Lengths come from this exact coupled pose.
                for side in 0..<2 {
                    bodies[i].supports[side].length = (bodies[i].hole(side) - attachment(bodies[i].supports[side].u)).length
                }
                bodies[i].detached = false
                bodies[i].tying = nil
                bodies[i].heldCenter = nil
                bodies[i].loose.removeAll(keepingCapacity: true)
                retied = true
            }
        }
        if retied { remesh() }
        updateRestingState()
    }

    private func updateRestingState() {
        guard !isInteracting, age > 1 else { quietTime = 0; return }
        let points = nodes.map(\.p) + bodies.flatMap { [$0.center, CGPoint(x: $0.angle * $0.card.size.width, y: 0)] }
        if quietTime == 0 || quietMin.count != points.count { quietMin = points; quietMax = points }
        for i in points.indices {
            quietMin[i].x = min(quietMin[i].x, points[i].x); quietMin[i].y = min(quietMin[i].y, points[i].y)
            quietMax[i].x = max(quietMax[i].x, points[i].x); quietMax[i].y = max(quietMax[i].y, points[i].y)
        }
        quietTime += dt
        guard quietTime >= 0.45 else { return }
        // Sleep only after the entire cable and every rotational DOF stay below
        // a subpixel travel threshold for a sustained interval, not a deadline.
        isResting = zip(quietMin, quietMax).allSatisfy { ($1 - $0).length < 0.35 * layout.scale }
        quietTime = 0
        if isResting {
            for i in nodes.indices { nodes[i].previous = nodes[i].p }
            for i in bodies.indices { bodies[i].previous = bodies[i].center; bodies[i].previousAngle = bodies[i].angle }
        }
    }

    private enum Constraint { case cable(Int), hanger(Int, Int) }

    private func constraintOrder() -> [Constraint] {
        var ordered = lengths.indices.map { (CGFloat($0) + 0.5, Constraint.cable($0)) }
        for i in bodies.indices where !bodies[i].detached {
            for side in 0..<2 {
                let support = bodies[i].supports[side]
                if drag?.body != i || (bodies[i].hole(side) - attachment(support.u)).length >= support.length {
                    let (node, t) = segment(support.u)
                    ordered.append((CGFloat(node) + t, .hanger(i, side)))
                }
            }
        }
        return ordered.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// Solve J M⁻¹ Jᵀ λ = C in one coupled projection. Unlike an iteration-
    /// dependent chain of springs, this preserves cable length under heavy loads.
    /// Spatial row ordering keeps the Cholesky factor narrow after free placement.
    private func project(_ constraints: [Constraint]) -> CGFloat {
        let count = constraints.count, base = nodes.count * 2, dofs = base + bodies.count * 3
        var jacobian = Array(repeating: [(row: Int, value: CGFloat)](), count: dofs)
        var inverseMass = Array(repeating: CGFloat.zero, count: dofs)
        var error = Array(repeating: CGFloat.zero, count: count)
        for i in nodes.indices {
            inverseMass[i * 2] = nodes[i].inverseMass
            inverseMass[i * 2 + 1] = nodes[i].inverseMass
        }
        for i in bodies.indices {
            inverseMass[base + i * 3] = 1
            inverseMass[base + i * 3 + 1] = 1
            inverseMass[base + i * 3 + 2] = 1 / bodies[i].inertia
        }
        for (row, constraint) in constraints.enumerated() {
            switch constraint {
            case .cable(let i):
                let delta = nodes[i + 1].p - nodes[i].p
                let distance = max(0.00001, delta.length), n = delta / distance
                error[row] = distance - lengths[i]
                jacobian[i * 2].append((row, -n.x)); jacobian[i * 2 + 1].append((row, -n.y))
                jacobian[(i + 1) * 2].append((row, n.x)); jacobian[(i + 1) * 2 + 1].append((row, n.y))
            case .hanger(let i, let side):
                let body = bodies[i], support = body.supports[side]
                let (node, t) = segment(support.u)
                let delta = body.hole(side) - attachment(support.u)
                let distance = max(0.00001, delta.length), n = delta / distance
                // The active set is fixed for this Newton solve. Dropping a row
                // on tiny projection overshoots would inject energy every step.
                error[row] = distance - support.length
                jacobian[node * 2].append((row, -n.x * (1 - t)))
                jacobian[node * 2 + 1].append((row, -n.y * (1 - t)))
                jacobian[(node + 1) * 2].append((row, -n.x * t))
                jacobian[(node + 1) * 2 + 1].append((row, -n.y * t))
                jacobian[base + i * 3].append((row, n.x))
                jacobian[base + i * 3 + 1].append((row, n.y))
                let arm = body.arm(side)
                jacobian[base + i * 3 + 2].append((row, arm.x * n.y - arm.y * n.x))
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
        for i in 0..<count {
            for j in max(0, i - bandwidth)...i {
                var value = matrix[i * count + j]
                for k in max(0, i - bandwidth)..<j { value -= matrix[i * count + k] * matrix[j * count + k] }
                matrix[i * count + j] = i == j ? sqrt(max(1e-9, value)) : value / matrix[j * count + j]
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
        for dof in 0..<dofs where inverseMass[dof] > 0 {
            let correction = inverseMass[dof] * jacobian[dof].reduce(CGFloat.zero) { $0 + $1.value * force[$1.row] }
            if dof < base {
                if dof.isMultiple(of: 2) { nodes[dof / 2].p.x -= correction }
                else { nodes[dof / 2].p.y -= correction }
            } else {
                let i = (dof - base) / 3
                switch (dof - base) % 3 {
                case 0: bodies[i].center.x -= correction
                case 1: bodies[i].center.y -= correction
                default: bodies[i].angle -= correction
                }
            }
        }
        return error.reduce(0) { max($0, abs($1)) }
    }

    private func advanceLooseEnds(_ i: Int) {
        for side in 0..<2 {
            var loose = bodies[i].loose[side]
            let time = bodies[i].tying
            let targetLength = bodies[i].supports[side].length * (time == nil ? 0.92 : 1)
            loose.length += (targetLength - loose.length) * min(1, dt * 18)
            let top = attachment(bodies[i].supports[side].u)
            loose.particles[0].p = top
            loose.particles[0].previous = top
            for j in 1..<loose.particles.count {
                let p = loose.particles[j].p
                loose.particles[j].p += (p - loose.particles[j].previous) * exp(-4 * dt)
                    + CGPoint(x: 0, y: gravity * dt * dt)
                loose.particles[j].previous = p
            }
            let last = loose.particles.count - 1
            let hole = bodies[i].hole(side)
            for _ in 0..<12 {
                for j in 0..<last {
                    let delta = loose.particles[j + 1].p - loose.particles[j].p
                    let distance = max(0.00001, delta.length)
                    let mass = loose.particles[j].inverseMass + loose.particles[j + 1].inverseMass
                    let correction = delta * ((distance - loose.length / CGFloat(last)) / (distance * mass))
                    loose.particles[j].p += correction * loose.particles[j].inverseMass
                    loose.particles[j + 1].p -= correction * loose.particles[j + 1].inverseMass
                }
                if let time {
                    let strength = min(1, time / 0.4)
                    loose.particles[last].p += (hole - loose.particles[last].p) * strength
                }
            }
            bodies[i].loose[side] = loose
        }
    }
}

private extension CGPoint {
    var length: CGFloat { hypot(x, y) }
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, b: CGFloat) -> CGPoint { CGPoint(x: a.x * b, y: a.y * b) }
    static func / (a: CGPoint, b: CGFloat) -> CGPoint { a * (1 / b) }
    static func += (a: inout CGPoint, b: CGPoint) { a = a + b }
    static func -= (a: inout CGPoint, b: CGPoint) { a = a - b }
}
