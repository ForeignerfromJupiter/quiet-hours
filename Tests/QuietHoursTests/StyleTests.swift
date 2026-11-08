import XCTest
@testable import QuietHoursPreview

final class BreathTests: XCTestCase {
    func testBackOutEndpointsAndOvershoot() {
        XCTAssertEqual(BreathRenderer.backOut(0), 0, accuracy: 1e-9)
        XCTAssertEqual(BreathRenderer.backOut(1), 1, accuracy: 1e-9)
        let peak = stride(from: 0.0, through: 1.0, by: 0.001).map(BreathRenderer.backOut).max()!
        XCTAssertGreaterThan(peak, 1.05, "springs past the rest width before settling")
    }
}

final class StyleRegistryTests: XCTestCase {
    func testEveryStyleIsBuiltAndNamed() {
        let ctx = StyleContext(isPreview: false, showSeconds: false, uses24Hour: true, reduceMotion: false, appearance: .dark)
        XCTAssertTrue(ClockStyles.make(.hinge, context: ctx) is HingeRenderer)
        XCTAssertTrue(ClockStyles.make(.chorus, context: ctx) is ChorusRenderer)
        XCTAssertTrue(ClockStyles.make(.breath, context: ctx) is BreathRenderer)
        XCTAssertTrue(ClockStyles.make(.lumen, context: ctx) is LumenRenderer)
        XCTAssertTrue(ClockStyles.make(.prose, context: ctx) is ProseRenderer)
        for s in StyleID.allCases { XCTAssertTrue(s.isAvailable); XCTAssertFalse(s.finishNames.dark.isEmpty) }
    }
}
