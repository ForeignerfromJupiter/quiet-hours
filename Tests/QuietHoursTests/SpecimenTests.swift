import CoreText
import XCTest
@testable import QuietHoursPreview

final class SpecimenTests: XCTestCase {
    /// The bundled Anybody must expose both axes Specimen sets per cell, with the ranges it uses.
    func testBundledAnybodyExposesWidthAndWeight() throws {
        let font = Fonts.anybody(size: 40, weight: 400, width: 100)
        let axes = try XCTUnwrap(CTFontCopyVariationAxes(font) as? [[CFString: Any]])
        func axis(_ tag: NSNumber) -> [CFString: Any]? {
            axes.first { ($0[kCTFontVariationAxisIdentifierKey] as? NSNumber) == tag }
        }
        let wdth = try XCTUnwrap(axis(Fonts.widthAxis), "no wdth axis")
        let wght = try XCTUnwrap(axis(Fonts.weightAxis), "no wght axis")
        XCTAssertEqual(wdth[kCTFontVariationAxisMinimumValueKey] as? Double, 50)
        XCTAssertEqual(wdth[kCTFontVariationAxisMaximumValueKey] as? Double, 150)
        XCTAssertEqual(wght[kCTFontVariationAxisMinimumValueKey] as? Double, 100)
        XCTAssertEqual(wght[kCTFontVariationAxisMaximumValueKey] as? Double, 900)
        // Every column width and the full wave range fit inside the axes.
        XCTAssertTrue(SpecimenSheet.widths.allSatisfy { (50...150).contains($0) })

        // An instance actually takes the requested values (Core Text omits axes at their default).
        let cell = Fonts.anybody(size: 40, weight: 531, width: 84)
        let v = try XCTUnwrap(CTFontCopyVariation(cell) as? [NSNumber: NSNumber])
        XCTAssertEqual(v[Fonts.widthAxis]?.doubleValue ?? 0, 84, accuracy: 0.01)
        XCTAssertEqual(v[Fonts.weightAxis]?.doubleValue ?? 0, 531, accuracy: 0.01)
    }

    /// Wider and heavier cells really draw wider: the axes visibly change across the sheet.
    func testAxesChangeAdvance() {
        func advance(_ weight: CGFloat, _ width: CGFloat) -> Double {
            let font = Fonts.anybody(size: 100, weight: weight, width: width)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "10:09", attributes: [.font: font]))
            return CTLineGetTypographicBounds(line, nil, nil, nil)
        }
        let narrow = advance(520, 55), wide = advance(520, 144)
        XCTAssertGreaterThan(wide, narrow * 1.6)
        XCTAssertGreaterThan(advance(820, 84), advance(220, 84))
    }

    /// `WG[r] + 150·sin(t/1100 − (r+c)·.6)`, clamped to 100…900 and whole (prototype `toFixed(0)`).
    func testWeightWave() {
        let t = 2.0
        for r in 0..<3 {
            for c in 0..<4 {
                let expected = min(max(SpecimenSheet.weights[r] + 150 * sin(t / 1.1 - Double(r + c) * 0.6), 100), 900).rounded()
                XCTAssertEqual(SpecimenSheet.weight(row: r, column: c, time: t, reduceMotion: false), expected)
            }
        }
        // t = 0: the top-left cell sits on its base weight; the wave travels diagonally.
        XCTAssertEqual(SpecimenSheet.weight(row: 0, column: 0, time: 0, reduceMotion: false), 220)
        XCTAssertEqual(SpecimenSheet.weight(row: 1, column: 1, time: 0, reduceMotion: false), (520 + 150 * sin(-1.2)).rounded())
        // One diagonal step later in the sheet is 0.66 s earlier in the wave.
        XCTAssertEqual(SpecimenSheet.weight(row: 0, column: 1, time: 1, reduceMotion: false),
                       SpecimenSheet.weight(row: 0, column: 0, time: 1 - 0.66, reduceMotion: false))
        XCTAssertEqual(SpecimenSheet.weight(row: 1, column: 0, time: 1, reduceMotion: false) - 300,
                       SpecimenSheet.weight(row: 0, column: 1, time: 1, reduceMotion: false))
        // Clamping at both ends of the weight axis.
        let peak = 1.1 * (Double.pi / 2)   // sin = 1 at the top-left cell
        XCTAssertEqual(SpecimenSheet.weight(row: 2, column: 0, time: peak + 1.1 * 1.2, reduceMotion: false), 900)
        XCTAssertEqual(SpecimenSheet.weight(row: 0, column: 0, time: -peak, reduceMotion: false), 100)
        // Reduce motion: no wave, the base weights.
        for r in 0..<3 {
            XCTAssertEqual(SpecimenSheet.weight(row: r, column: 2, time: 3.3, reduceMotion: true), SpecimenSheet.weights[r])
        }
    }

    func testLabelMatchesAxes() {
        XCTAssertEqual(SpecimenSheet.label(width: 84, weight: 531), "WDTH 84 · WGHT 531")
        XCTAssertEqual(SpecimenSheet.label(width: SpecimenSheet.width(column: 3),
                                           weight: SpecimenSheet.weight(row: 2, column: 3, time: 0, reduceMotion: true)),
                       "WDTH 144 · WGHT 820")
    }

    /// `floor((s + ms/1000)/60 · 12)`: one cell per 5 s, reading order.
    func testSecondsCell() {
        XCTAssertEqual(SpecimenSheet.hotCell(second: 0, millisecond: 0), 0)
        XCTAssertEqual(SpecimenSheet.hotCell(second: 4, millisecond: 999), 0)
        XCTAssertEqual(SpecimenSheet.hotCell(second: 5, millisecond: 0), 1)
        XCTAssertEqual(SpecimenSheet.hotCell(second: 32, millisecond: 500), 6)
        XCTAssertEqual(SpecimenSheet.hotCell(second: 55, millisecond: 0), 11)
        XCTAssertEqual(SpecimenSheet.hotCell(second: 59, millisecond: 999), 11)
        XCTAssertEqual(Set((0..<60).map { SpecimenSheet.hotCell(second: $0, millisecond: 0) }).count, 12)
    }

    /// Cascade: 75 ms per cell in reading order; out over the first 230 ms, swap, in over the rest.
    func testCascade() {
        XCTAssertEqual(SpecimenSheet.delay(index: 0), 0)
        XCTAssertEqual(SpecimenSheet.delay(index: 11), 0.825, accuracy: 1e-9)
        var s = SpecimenSheet.swap(-0.1)
        XCTAssertEqual(s.opacity, 1); XCTAssertEqual(s.dy, 0); XCTAssertFalse(s.swapped)
        s = SpecimenSheet.swap(0.25)
        XCTAssertEqual(s.opacity, 0.5, accuracy: 1e-9); XCTAssertEqual(s.dy, -0.125, accuracy: 1e-9); XCTAssertFalse(s.swapped)
        s = SpecimenSheet.swap(0.5)
        XCTAssertEqual(s.opacity, 0, accuracy: 1e-9); XCTAssertEqual(s.dy, 0.125, accuracy: 1e-9); XCTAssertTrue(s.swapped)
        s = SpecimenSheet.swap(0.75)
        XCTAssertEqual(s.opacity, 0.5, accuracy: 1e-9); XCTAssertEqual(s.dy, 0.0625, accuracy: 1e-9); XCTAssertFalse(s.done)
        s = SpecimenSheet.swap(1)
        XCTAssertEqual(s.opacity, 1); XCTAssertEqual(s.dy, 0); XCTAssertTrue(s.done)
    }

    func testTimeText() {
        XCTAssertEqual(SpecimenSheet.text(ClockTime(hour24: 9, minute: 5, second: 0, uses24Hour: true)), "09:05")
        XCTAssertEqual(SpecimenSheet.text(ClockTime(hour24: 9, minute: 5, second: 0, uses24Hour: false)), "9:05")
        XCTAssertEqual(SpecimenSheet.text(ClockTime(hour24: 13, minute: 45, second: 0, uses24Hour: false)), "1:45")
        XCTAssertEqual(SpecimenSheet.text(ClockTime(hour24: 0, minute: 0, second: 0, uses24Hour: false)), "12:00")
        XCTAssertEqual(SpecimenSheet.text(ClockTime(hour24: 22, minute: 9, second: 0, uses24Hour: true)), "22:09")
    }

    func testDateLine() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let date = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 22, minute: 9, second: 5)))
        let t12 = ClockTime(date: date, calendar: cal, uses24Hour: false)
        XCTAssertEqual(SpecimenSheet.dateLine(t12, showSeconds: true, calendar: cal), "SUNDAY 08 NOV PM :05")
        let t24 = ClockTime(date: date, calendar: cal, uses24Hour: true)
        XCTAssertEqual(SpecimenSheet.dateLine(t24, showSeconds: false, calendar: cal), "SUNDAY 08 NOV")
    }
}
