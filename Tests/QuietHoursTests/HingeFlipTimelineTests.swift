import XCTest
@testable import QuietHoursPreview

/// The flip must match the prototype's CSS keyframes and timings.
final class HingeFlipTimelineTests: XCTestCase {
    private func at(_ ms: Double) -> HingeFlipTimeline.State { HingeFlipTimeline.state(at: ms / 1000) }

    func testStart() {
        let s = at(0)
        XCTAssertTrue(s.frontVisible)
        XCTAssertEqual(s.frontAngle, 0, accuracy: 1e-9)
        XCTAssertEqual(s.frontShade, 0, accuracy: 1e-9)
        XCTAssertFalse(s.backVisible)
        XCTAssertFalse(s.finished)
    }

    func testFoldIsEaseInAndEndsFlatAt250ms() {
        XCTAssertGreaterThan(at(125).frontAngle, -45, "ease-in: less than half the angle at half the time")
        XCTAssertEqual(at(249.999).frontAngle, -90, accuracy: 0.1)
        XCTAssertFalse(at(250).frontVisible)
        XCTAssertEqual(at(250).bottomShade, 1, accuracy: 1e-9)
    }

    func testLandingStartsAt240msOverlappingTheFold() {
        XCTAssertFalse(at(239).backVisible)
        XCTAssertTrue(at(240).backVisible)
        XCTAssertTrue(at(245).frontVisible && at(245).backVisible)
        XCTAssertEqual(at(240).backAngle, 90, accuracy: 1e-9)
    }

    func testLandingOvershootsThenSettles() {
        // Peak of cubic-bezier(.18,1.65,.42,1) is ~171 ms into the 420 ms rise: ~11° past flat.
        let peak = stride(from: 240.0, through: 660, by: 1).map { at($0).backAngle }.min()!
        XCTAssertEqual(peak, -11.4, accuracy: 0.5)
        XCTAssertEqual(at(659.999).backAngle, 0, accuracy: 0.05)
        XCTAssertEqual(at(659.999).backShade, 0, accuracy: 0.01)
    }

    func testFinishesAt700ms() {
        XCTAssertFalse(at(699).finished)
        XCTAssertTrue(at(700).finished)
        XCTAssertFalse(at(700).backVisible)
    }
}

final class HingeLayoutTests: XCTestCase {
    func testFourCardRowFillsWidthOn16by10() {
        let u = HingeLayout.unit(width: 1600, height: 1000, leadingVisible: true, showSeconds: false)
        let row = HingeLayout.rowWidth(leadingVisible: true, showSeconds: false) * u
        XCTAssertEqual(row / 1600, HingeLayout.widthFill, accuracy: 0.001)
    }

    func testThreeCardRowIsBiggerButHeightCapped() {
        let four = HingeLayout.unit(width: 1600, height: 1000, leadingVisible: true, showSeconds: false)
        let three = HingeLayout.unit(width: 1600, height: 1000, leadingVisible: false, showSeconds: false)
        XCTAssertGreaterThan(three, four * 1.2)
        let block = (HingeLayout.cardSize(showSeconds: false).height + HingeLayout.labelRise) * three
        XCTAssertLessThanOrEqual(block / 1000, HingeLayout.heightFill + 0.001)
    }

    func testUltrawideIsHeightLimited() {
        let u = HingeLayout.unit(width: 5120, height: 1440, leadingVisible: true, showSeconds: false)
        let block = (HingeLayout.cardSize(showSeconds: false).height + HingeLayout.labelRise) * u
        XCTAssertEqual(block / 1440, HingeLayout.heightFill, accuracy: 0.001)
    }
}
