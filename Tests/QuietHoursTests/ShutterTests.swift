import XCTest
@testable import QuietHoursPreview

final class ShutterGeometryTests: XCTestCase {
    private func area(_ p: [CGPoint]) -> Double {
        var s = 0.0
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            s += Double(a.x * b.y - b.x * a.y)
        }
        return abs(s) / 2
    }

    /// Crossing-number test (boundary handled separately by the callers).
    private func contains(_ poly: [CGPoint], _ q: CGPoint) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in poly.indices {
            let a = poly[i], b = poly[j]
            if (a.y > q.y) != (b.y > q.y), q.x < (b.x - a.x) * (q.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    private func distance(_ q: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        let t = len2 == 0 ? 0 : max(0, min(1, ((q.x - a.x) * dx + (q.y - a.y) * dy) / len2))
        return hypot(q.x - (a.x + t * dx), q.y - (a.y + t * dy))
    }

    private func nearBoundary(_ q: CGPoint, _ polys: [[CGPoint]], tolerance: CGFloat) -> Bool {
        for p in polys {
            for i in p.indices where distance(q, p[i], p[(i + 1) % p.count]) < tolerance { return true }
        }
        return false
    }

    /// Apertures from shut to the breathing maximum, several rotations, three screen shapes.
    private let screens = [CGRect(x: 0, y: 0, width: 1240, height: 800),
                           CGRect(x: 0, y: 0, width: 3440, height: 1440),
                           CGRect(x: 0, y: 0, width: 800, height: 1240)]
    private let apertures: [(String, CGFloat)] = [("closed", 0), ("nearly closed", 0.004), ("half", 0.43),
                                                  ("rest", 0.86), ("rest, breathing out", 0.86 * 1.018)]
    private let angles = [0.0, 0.37, 1.1, 2.9, 1234.5]

    /// The blades and the aperture split the blade outline exactly: no gaps, no overlaps.
    func testBladesTileOutsideTheApertureByArea() {
        for b in screens {
            let c = CGPoint(x: b.midX, y: b.midY), hd = hypot(b.width, b.height) / 2
            for (name, f) in apertures {
                for th in angles {
                    let iris = ShutterGeometry.iris(center: c, radius: hd * f, angle: th,
                                                    reach: ShutterGeometry.reach(covering: Room.frame(b), center: c))
                    let blades = iris.blades.map(area).reduce(0, +)
                    let total = area(iris.outline)
                    XCTAssertEqual(blades + area(iris.aperture), total, accuracy: total * 1e-9, "\(name) θ=\(th) \(b.size)")
                }
            }
        }
    }

    /// Every sampled point of the oversized room is under exactly one blade, unless it is inside
    /// the aperture (then under none).
    func testEveryPointOfTheRoomIsCoveredOnce() {
        for b in screens {
            let room = Room.frame(b)
            let c = CGPoint(x: b.midX, y: b.midY), hd = hypot(b.width, b.height) / 2
            for (name, f) in apertures {
                for th in angles {
                    let iris = ShutterGeometry.iris(center: c, radius: hd * f, angle: th,
                                                    reach: ShutterGeometry.reach(covering: room, center: c))
                    var checked = 0
                    for iy in 0...48 {
                        for ix in 0...72 {
                            let q = CGPoint(x: room.minX + room.width * CGFloat(ix) / 72 + 0.013,
                                            y: room.minY + room.height * CGFloat(iy) / 48 + 0.017)
                            if nearBoundary(q, iris.blades + [iris.aperture], tolerance: 0.05) { continue }
                            let n = iris.blades.filter { contains($0, q) }.count
                            let open = f > 0 && contains(iris.aperture, q)
                            XCTAssertEqual(n, open ? 0 : 1, "\(name) θ=\(th) \(b.size) at \(q)")
                            checked += 1
                        }
                    }
                    XCTAssertGreaterThan(checked, 3000)
                }
            }
        }
    }

    func testOutlineCoversTheOversizedRoom() {
        let b = CGRect(x: 0, y: 0, width: 1240, height: 800), room = Room.frame(b)
        let c = CGPoint(x: b.midX, y: b.midY), hd = hypot(b.width, b.height) / 2
        for f: CGFloat in [0, 0.43, 0.88] {
            let iris = ShutterGeometry.iris(center: c, radius: hd * f, angle: 0.5,
                                            reach: ShutterGeometry.reach(covering: room, center: c))
            for q in [CGPoint(x: room.minX, y: room.minY), CGPoint(x: room.maxX, y: room.minY),
                      CGPoint(x: room.minX, y: room.maxY), CGPoint(x: room.maxX, y: room.maxY)] {
                XCTAssertTrue(contains(iris.outline, q))
            }
        }
    }

    /// At rest only the blade tips show: the aperture (apothem ≈ 0.77 × half-diagonal) clears
    /// most of the screen and every corner is covered.
    func testRestApertureShowsOnlyTheCorners() {
        let b = CGRect(x: 0, y: 0, width: 1240, height: 800)
        let c = CGPoint(x: b.midX, y: b.midY), hd = hypot(b.width, b.height) / 2
        let iris = ShutterGeometry.iris(center: c, radius: hd * 0.86, angle: 0, reach: 4 * hd)
        XCTAssertTrue(contains(iris.aperture, CGPoint(x: b.midX, y: 40)))
        XCTAssertTrue(contains(iris.aperture, CGPoint(x: 80, y: b.midY)))
        XCTAssertFalse(contains(iris.aperture, CGPoint(x: 2, y: 2)))
    }
}

final class ShutterTimelineTests: XCTestCase {
    func testCloseHoldReopen() {
        XCTAssertEqual(ShutterTimeline.closure(at: 0), 0)
        XCTAssertEqual(ShutterTimeline.closure(at: 190)!, 0.125, accuracy: 1e-12)   // (½)³
        XCTAssertEqual(ShutterTimeline.closure(at: 380), 1)
        XCTAssertEqual(ShutterTimeline.closure(at: 539.9), 1)
        XCTAssertEqual(ShutterTimeline.closure(at: 540), 1)
        XCTAssertEqual(ShutterTimeline.closure(at: 890)!, pow(2, -5), accuracy: 1e-12)
        XCTAssertNil(ShutterTimeline.closure(at: 1240))
        var last = -1.0
        for ms in stride(from: 0.0, to: 380, by: 1) {
            let c = ShutterTimeline.closure(at: ms)!
            XCTAssertGreaterThan(c, last)
            last = c
        }
    }

    /// The numerals may only change while the iris is fully shut.
    func testSwapIsHidden() {
        XCTAssertEqual(ShutterTimeline.closure(at: ShutterTimeline.swapAt), 1)
        for ms in stride(from: 0.0, to: 1240, by: 0.5) {
            guard let c = ShutterTimeline.closure(at: ms), c < 1 else { continue }
            XCTAssertEqual(ShutterTimeline.hasSwapped(at: ms), ms >= ShutterTimeline.reopenStart, "\(ms) ms")
        }
    }

    func testTimeText() {
        XCTAssertEqual(ShutterRenderer.timeText(ClockTime(hour24: 9, minute: 41, second: 0, uses24Hour: true)), "09:41")
        XCTAssertEqual(ShutterRenderer.timeText(ClockTime(hour24: 9, minute: 41, second: 0, uses24Hour: false)), "9:41")
        XCTAssertEqual(ShutterRenderer.timeText(ClockTime(hour24: 22, minute: 5, second: 0, uses24Hour: false)), "10:05")
        XCTAssertEqual(ShutterRenderer.timeText(ClockTime(hour24: 0, minute: 5, second: 0, uses24Hour: false)), "12:05")
    }

    func testRegistered() {
        let ctx = StyleContext(isPreview: false, showSeconds: true, uses24Hour: true, reduceMotion: false, appearance: .light)
        XCTAssertTrue(ClockStyles.make(.shutter, context: ctx) is ShutterRenderer)
        XCTAssertEqual(StyleID.shutter.displayName, "Shutter")
        XCTAssertEqual(StyleID.shutter.finishNames.dark, "Night")
        XCTAssertEqual(StyleID.shutter.finishNames.light, "Paper")
    }
}
