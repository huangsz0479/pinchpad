import Foundation
import CoreGraphics

@main struct ClotheslineLayoutProbe {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func arcLength(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }
    static func main() {
        var scenes = 0
        for size in [CGSize(width: 320, height: 440), CGSize(width: 640, height: 480),
                     CGSize(width: 1440, height: 900), CGSize(width: 3440, height: 1440)] {
            for origin in [CGPoint(x: 0, y: 28), CGPoint(x: -1920, y: -1080)] {
                for count in [0, 1, 4, 25] {
                    let items = (0..<count).map { ClotheslineLayout.Item(id: "app-\($0)", size: TrayAppSize.allCases[$0 % 3]) }
                    let layout = ClotheslineLayout(items: items, bounds: CGRect(origin: origin, size: size))
                    require(layout.pages.flatMap { $0.map(\.item) } == items, "Pagination drops or reorders apps")
                    require(layout.anchorY == origin.y + 15, "Pins are not 15pt below menu bar")
                    require(layout.hanger >= 15 && layout.hanger <= 25, "Hanger outside requested length")
                    for page in layout.pages.indices {
                        let initialLength = arcLength(layout.rope(page: page, elapsed: 0))
                        for t in [0.0, 0.08, 0.275, 0.5, 0.8, 1, 1.5, 2, 3, 4, 8] {
                            let frame = layout.frame(page: page, elapsed: t)
                            require(frame.rope.allSatisfy { $0.x.isFinite && $0.y.isFinite }, "Non-finite rope")
                            require(frame.rope.first == CGPoint(x: layout.left, y: layout.anchorY)
                                    && frame.rope.last == CGPoint(x: layout.right, y: layout.anchorY), "Pins move during swing")
                            require(abs(arcLength(frame.rope) - initialLength) < 0.05, "Cable length changes: \(size), count \(count), page \(page), t \(t), delta \(arcLength(frame.rope) - initialLength)")
                            for pose in frame.poses {
                                require(pose.card.size.width == ClotheslineLayout.iconSide + 8, "Card does not have 4pt padding")
                                require(pose.hangers.count == 2, "Card must have two working suspension points")
                                require(pose.card.holes[0].x + pose.card.holes[1].x == pose.card.size.width
                                        && pose.card.holes[0].y == pose.card.holes[1].y, "Holes are not mirrored")
                                for hanger in pose.hangers {
                                    require(abs(hypot(hanger.hole.x - hanger.attachment.x, hanger.hole.y - hanger.attachment.y) - layout.hanger) < 0.03,
                                            "A corner tie stretches or detaches during rotation")
                                    require(abs(hanger.attachment.y - layout.ropeY(at: hanger.attachment.x, page: page, elapsed: t)) < 0.001,
                                            "A suspension point leaves the main cable")
                                    require(hanger.hole.y > hanger.attachment.y, "A card flips above its support")
                                }
                                require(pose.cardPoint(pose.card.hole) == pose.pivot, "Hole is not the rotation pivot")
                                require(pose.rotatedBounds.minX >= layout.bounds.minX && pose.rotatedBounds.maxX <= layout.bounds.maxX,
                                        "Card leaves display horizontally")
                                require(pose.rotatedBounds.minY >= layout.bounds.minY && pose.rotatedBounds.maxY < layout.pagerY - 20,
                                        "Card leaves display or collides with pager")
                                require((0...1).contains(pose.opacity), "Invalid opacity")
                            }
                            for pair in zip(frame.poses, frame.poses.dropFirst()) {
                                require(!pair.0.rotatedBounds.intersects(pair.1.rotatedBounds), "Swinging cards collide")
                            }
                        }
                        let settled = layout.frame(page: page, elapsed: ClotheslineMotion.duration)
                        for pose in settled.poses {
                            require(pose.center.x > pose.hangers[0].hole.x && pose.center.x < pose.hangers[1].hole.x,
                                    "Card centre of mass is outside its two supports")
                            require(pose.center.y > pose.hangers.map { $0.hole.y }.max()! && abs(pose.angle) < 35,
                                    "Two-point suspension retains the old diagonal tilt")
                            // Vertical force and moment balance determine both
                            // tensions. They must be positive, with no net side force.
                            let supports = pose.hangers.map { hanger -> (x: CGFloat, y: CGFloat, torque: CGFloat) in
                                let dx = hanger.attachment.x - hanger.hole.x, dy = hanger.attachment.y - hanger.hole.y
                                let distance = hypot(dx, dy), x = dx / distance, y = dy / distance
                                return (x, y, (hanger.hole.x - pose.center.x) * y - (hanger.hole.y - pose.center.y) * x)
                            }
                            let a = supports[0], b = supports[1]
                            let determinant = a.y * b.torque - b.y * a.torque
                            let leftTension = -b.torque / determinant, rightTension = a.torque / determinant
                            require(leftTension > 0 && rightTension > 0, "Both strings must carry load")
                            require(abs(leftTension * a.x + rightTension * b.x) < 0.03, "Two-hanger force balance has not settled")
                        }
                        let rope = settled.rope
                        for i in 1..<(rope.count - 1) {
                            let fraction = (rope[i].x - rope[i-1].x) / (rope[i+1].x - rope[i-1].x)
                            let chordY = rope[i-1].y + (rope[i+1].y - rope[i-1].y) * fraction
                            require(rope[i].y >= chordY - 0.15 * layout.scale,
                                    "Equilibrium bows upward beyond the subpixel settling tolerance")
                        }
                        require(rope == layout.rope(page: page, elapsed: 100), "Animation keeps moving while idle")
                        require(layout.settlingDuration(page: page) < ClotheslineMotion.duration, "Motion only stops at forced deadline: \(size) count \(count) page \(page)")
                    }
                    scenes += 1
                }
            }
        }
        let bounds = CGRect(x: 0, y: 28, width: 1440, height: 872)
        let single = ClotheslineLayout(items: [.init(id: "one", size: .small)], bounds: bounds)
        let unloaded = ClotheslineLayout(items: [], bounds: bounds)
        require(single.ropeY(at: bounds.midX, page: 0, elapsed: 8) > unloaded.ropeY(at: bounds.midX, page: 0, elapsed: 8) + 8,
                "A central point load does not change the rope shape")
        let rope = single.rope(page: 0, elapsed: 8)
        let settledCard = single.poses(page: 0, elapsed: 8)[0]
        for hanger in settledCard.hangers {
            let i = rope.firstIndex { hypot($0.x - hanger.attachment.x, $0.y - hanger.attachment.y) < 0.001 }!
            let slopeBefore = (rope[i].y - rope[i-1].y) / (rope[i].x - rope[i-1].x)
            let slopeAfter = (rope[i+1].y - rope[i].y) / (rope[i+1].x - rope[i].x)
            require(slopeBefore - slopeAfter > 0.07, "One of the two ties does not transfer load to the cable")
        }
        require(abs(settledCard.angle) < 0.2, "Symmetric two-point suspension must settle level")
        let early = single.poses(page: 0, elapsed: 0.1)[0]
        require(abs(early.center.x - settledCard.center.x) > 1, "Two-point hanging card has no entrance sway")
        var session = ClotheslineSession()
        require(session.open() && !session.open(), "Repeated opening is not idempotent")
        let token = session.select(2, count: 4)
        session.close()
        require(!session.accepts(token), "Delayed callbacks survive closing")
        require(session.open() && session.page == 0 && !session.accepts(token), "Reopening preserves old callbacks/page")
        session.select(9, count: 0)
        require(session.page == 0, "Empty list leaves invalid page")
        print("PASS: \(scenes) layouts, pagination, display bounds, 15pt pins, 22pt ties and icon-sized cards")
        print("PASS: conserved cable length, two mirrored holes, two load-bearing ties, load-dependent tension, rigid-body torque, damped rest and no collisions")
    }
}
