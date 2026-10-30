import Foundation
import CoreGraphics

@main struct ClotheslineDynamicsProbe {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
    static func length(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }
    static func main() throws {
        var durations: [Double] = []
        var scenes = 0
        var largestLengthError: CGFloat = 0
        for size in [CGSize(width: 320, height: 440), CGSize(width: 1440, height: 900), CGSize(width: 3440, height: 1440)] {
            for count in [0, 1, 8, 30] {
                let layout = ClotheslineLayout(items: (0..<count).map { .init(id: "\($0)", size: .small) },
                                              bounds: CGRect(origin: CGPoint(x: -50, y: 28), size: size))
                let sim = ClotheslineDynamics(layout: layout, page: 0)
                let ropeLength = length(sim.frame().rope)
                func advance(_ duration: Double) {
                    for _ in 0..<Int(duration * 120) {
                        let start = CFAbsoluteTimeGetCurrent()
                        sim.advance(by: 1 / 120)
                        let frame = sim.frame()
                        durations.append(CFAbsoluteTimeGetCurrent() - start)
                        let points = frame.rope + frame.poses.map(\.center) + (frame.strands ?? []).flatMap(\.points)
                        require(points.allSatisfy { $0.x.isFinite && $0.y.isFinite }, "Non-finite physics output")
                        require(frame.rope.first == CGPoint(x: layout.left, y: layout.anchorY)
                                && frame.rope.last == CGPoint(x: layout.right, y: layout.anchorY), "A pin moved")
                        let error = abs(length(frame.rope) - ropeLength)
                        largestLengthError = max(largestLengthError, error)
                        require(error < max(1.0, ropeLength * 0.001), "Cable length drift: \(error), \(size), count \(count)")
                    }
                }
                advance(8)
                require(sim.isResting, "Entrance never sleeps: \(size), \(count)")
                guard let original = sim.frame().poses.first else { scenes += 1; continue }
                let before = sim.frame()
                require(sim.hitTest(original.center) == original.card.id, "Visible center misses card")
                require(sim.beginDrag(id: original.card.id, at: original.center), "Cannot start drag")
                let destination = CGPoint(x: layout.bounds.midX + min(99.37, size.width * 0.1),
                                          y: layout.bounds.minY + size.height * 0.62)
                for frame in 1...90 {
                    let t = CGFloat(frame) / 90
                    sim.moveDrag(to: CGPoint(x: original.center.x + (destination.x - original.center.x) * t,
                                            y: original.center.y + (destination.y - original.center.y) * t))
                    advance(1 / 120)
                }
                let detached = sim.frame()
                require(detached.poses[0].fastening == 0 && detached.strands![0].points.count > 2, "No broken, freely moving end")
                // The whole cable responds to the removed load, not just one rendered tie.
                let travel = zip(before.rope, detached.rope).map(distance)
                require(travel.filter { $0 > 0.05 * layout.scale }.count > 3, "Cable does not propagate the release")
                let placement = sim.endDrag()!
                require(abs(placement.position.x * layout.bounds.width + layout.bounds.minX - destination.x) < 0.001,
                        "Drop snaps to a horizontal slot")
                require(abs(placement.position.y * layout.bounds.height + layout.bounds.minY - destination.y) < 0.001,
                        "Drop snaps to a vertical slot")
                advance(0.55)
                require(sim.frame().poses[0].fastening > 0 && sim.frame().poses[0].fastening < 1, "Missing partial knot animation")
                advance(10)
                require(sim.isResting && sim.frame().poses[0].fastening == 1, "Retied scene never settles: \(size), \(count)")
                let settled = sim.frame().poses[0].center
                require(distance(settled, destination) < 22 * layout.scale, "Release drifts away from the chosen position: \(distance(settled, destination))")
                let restored = ClotheslineDynamics(layout: layout, page: 0, positions: [placement.id: placement.position])
                restored.settle()
                require(distance(restored.frame().poses[0].center, settled) < 14 * layout.scale,
                        "Saved location changes after reopening: \(distance(restored.frame().poses[0].center, settled))")
                let frozen = sim.frame().rope
                sim.advance(by: 100)
                require(sim.frame().rope == frozen, "Idle scene keeps animating")
                // Interrupted retying, fast diagonal drags, and out-of-bounds releases.
                for point in [CGPoint(x: 99999, y: -99999), CGPoint(x: -99999, y: 99999)] {
                    let pose = sim.frame().poses[0]
                    require(sim.beginDrag(id: pose.card.id, at: pose.center), "Cannot regrab during motion")
                    sim.moveDrag(to: point)
                    advance(0.2)
                    _ = sim.endDrag()
                    advance(0.1)
                }
                sim.cancelDrag()
                advance(12)
                require(sim.isResting, "Fast boundary drag never settles")
                scenes += 1
            }
        }
        // Identical elapsed time must produce identical trajectories at display rates.
        let layout = ClotheslineLayout(items: (0..<5).map { .init(id: "\($0)", size: .small) },
                                      bounds: CGRect(x: 0, y: 28, width: 1440, height: 872))
        var samples: [[CGPoint]] = []
        for hz in [30, 60, 120] {
            let sim = ClotheslineDynamics(layout: layout, page: 0)
            for _ in 0..<hz { sim.advance(by: 1 / Double(hz)) }
            samples.append(sim.frame().rope)
        }
        for sample in samples.dropFirst() {
            require(zip(samples[0], sample).allSatisfy { distance($0, $1) < 0.001 }, "Refresh rate changes physics")
        }
        durations.sort()
        print("PASS: \(scenes) live simulations; free X/Y placement, persistence, cable conservation, break/recoil/retie, repeated drag, sleep, 30/60/120 Hz equivalence")
        print(String(format: "Physics + frame p95 %.3f ms, p99 %.3f ms, max %.3f ms; max cable error %.4f pt", durations[Int(Double(durations.count) * 0.95)] * 1000,
                     durations[Int(Double(durations.count) * 0.99)] * 1000, durations.last! * 1000, largestLengthError))
    }
}
