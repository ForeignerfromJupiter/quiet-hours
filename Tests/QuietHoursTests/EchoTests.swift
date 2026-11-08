import XCTest
@testable import QuietHoursPreview

final class EchoTests: XCTestCase {
    func testOrbitCompletesOnceAMinute() {
        let a0 = EchoModel.orbitAngle(second: 0, millisecond: 0, reduceMotion: false)
        XCTAssertEqual(a0, .pi * 0.75, accuracy: 1e-12)
        // A quarter minute turns the offset a quarter turn (angle decreasing, y down).
        XCTAssertEqual(EchoModel.orbitAngle(second: 15, millisecond: 0, reduceMotion: false), .pi * 0.25, accuracy: 1e-12)
        XCTAssertEqual(EchoModel.orbitAngle(second: 30, millisecond: 0, reduceMotion: false), -.pi * 0.25, accuracy: 1e-12)
        // Just before the minute it is back where it started, one full turn later.
        let end = EchoModel.orbitAngle(second: 59, millisecond: 999, reduceMotion: false)
        XCTAssertEqual(a0 - end, 2 * .pi, accuracy: 1e-3)
        // Continuous: milliseconds move it smoothly.
        let a1 = EchoModel.orbitAngle(second: 7, millisecond: 500, reduceMotion: false)
        XCTAssertEqual(a1, .pi * 0.75 - 7.5 / 60 * 2 * .pi, accuracy: 1e-12)
    }

    func testOrbitHoldsStillWithReducedMotion() {
        for s in [0, 17, 42] {
            XCTAssertEqual(EchoModel.orbitAngle(second: s, millisecond: 300, reduceMotion: true), .pi * 0.25)
        }
    }

    func testLayerDelaysCascadeFrontToBack() {
        // Each layer 70 ms after the one in front of it, each changing slot 110 ms after the previous.
        XCTAssertEqual(EchoModel.swapStart(now: 10, layer: 0, order: 0), 10, accuracy: 1e-12)
        XCTAssertEqual(EchoModel.swapStart(now: 10, layer: 1, order: 0), 10.07, accuracy: 1e-12)
        XCTAssertEqual(EchoModel.swapStart(now: 10, layer: 6, order: 0), 10.42, accuracy: 1e-12)
        XCTAssertEqual(EchoModel.swapStart(now: 10, layer: 0, order: 1), 10.11, accuracy: 1e-12)
        XCTAssertEqual(EchoModel.swapStart(now: 10, layer: 6, order: 3), 10 + 0.42 + 0.33, accuracy: 1e-12)
        for order in 0..<4 {
            let starts = (0..<EchoModel.layers).map { EchoModel.swapStart(now: 0, layer: $0, order: order) }
            XCTAssertEqual(starts, starts.sorted(), "front layer first")
        }
    }

    func testChangeOrdersCountChangingSlotsLeftToRight() {
        let a = EchoModel.slots(ClockTime(hour24: 10, minute: 59, second: 58, uses24Hour: true))
        let b = EchoModel.slots(ClockTime(hour24: 11, minute: 0, second: 0, uses24Hour: true))
        XCTAssertEqual(a, ["1", "0", ":", "5", "9"])
        XCTAssertEqual(EchoModel.changeOrders(from: a, to: b), [nil, 0, nil, 1, 2])
        // 12h, 12:59 → 1:00: the tens slot turns blank but still takes its turn.
        let c = EchoModel.slots(ClockTime(hour24: 12, minute: 59, second: 0, uses24Hour: false))
        let d = EchoModel.slots(ClockTime(hour24: 13, minute: 0, second: 0, uses24Hour: false))
        XCTAssertEqual(d, [" ", "1", ":", "0", "0"])
        XCTAssertEqual(EchoModel.changeOrders(from: c, to: d), [0, 1, nil, 2, 3])
        XCTAssertEqual(EchoModel.changeOrders(from: d, to: d), [nil, nil, nil, nil, nil])
    }

    func testSwapSlidesOldUpAndNewInFromBelow() {
        XCTAssertEqual(EchoModel.swap(at: 0), .init(oldAlpha: 1, oldDY: 0, newAlpha: 0, newDY: 0.35))
        XCTAssertEqual(EchoModel.swap(at: 1), .init(oldAlpha: 0, oldDY: -0.35, newAlpha: 1, newDY: 0))
        XCTAssertEqual(EchoModel.swap(at: -2), EchoModel.swap(at: 0), "waiting for its delay")
        let half = EchoModel.swap(at: 0.5)
        XCTAssertEqual(half.newAlpha, 0.5, accuracy: 1e-9)
        XCTAssertEqual(half.oldDY, -0.175, accuracy: 1e-9)
    }

    func testSizeAndOpacities() {
        // 24h "10:59": 4 × 0.66 + 0.32 = 2.96 units; width-limited on a 16:10 window.
        let all: [Character] = ["1", "0", ":", "5", "9"]
        XCTAssertEqual(EchoModel.numeralSize(visible: all, in: CGSize(width: 1240, height: 800)), 1240 * 0.8 / 2.96, accuracy: 1e-9)
        // Height-limited on a tall screen.
        XCTAssertEqual(EchoModel.numeralSize(visible: all, in: CGSize(width: 3000, height: 800)), 800 * 0.52, accuracy: 1e-9)
        XCTAssertEqual(EchoModel.layerOpacity(0), 1)
        XCTAssertEqual(EchoModel.layerOpacity(1), 0.875 * 0.95, accuracy: 1e-12)
        XCTAssertEqual(EchoModel.layerOpacity(6), 0.25 * 0.95, accuracy: 1e-12)
    }

    func testRegistered() {
        let ctx = StyleContext(isPreview: false, showSeconds: false, uses24Hour: true, reduceMotion: false, appearance: .dark)
        XCTAssertTrue(ClockStyles.make(.echo, context: ctx) is EchoRenderer)
        XCTAssertEqual(StyleID.echo.displayName, "Echo")
        XCTAssertEqual(StyleID.echo.finishNames.dark, "Night")
        XCTAssertEqual(StyleID.echo.finishNames.light, "Paper")
    }
}
