import XCTest
@testable import QuietHoursPreview

final class ModuleGlyphTests: XCTestCase {
    /// Every digit maps to 15 tiles exactly as in the PRD's pattern block.
    func testPatternsMatchPRD() {
        let prd = """
        0 a#b #.# #.# #.# d#c      5 ### #.. ##b ..# ##c
        1 a#. .#. .#. .#. ###      6 a## #.. ##b #.# d#c
        2 a#b ..# a#c #.. ###      7 ### ..# ..# ..# ..#
        3 ##b ..# .## ..# ##c      8 a#b #.# ### #.# d#c
        4 #.# #.# d## ..# ..#      9 a#b #.# d## ..# ##c
        """
        var seen = 0
        for line in prd.split(separator: "\n") {
            let words = line.split(separator: " ")
            for chunk in [Array(words.prefix(6)), Array(words.suffix(6))] {
                let digit = Character(String(chunk[0]))
                XCTAssertEqual(ModuleGlyphs.patterns[digit], chunk.dropFirst().map(String.init), "digit \(digit)")
                seen += 1
            }
        }
        XCTAssertEqual(seen, 10)
    }

    func testTilesAndCurves() {
        let zero = ModuleGlyphs.tiles(for: "0")
        XCTAssertEqual(zero.count, 15)
        XCTAssertEqual(zero[0], .init(scale: 1, radii: [1, 0, 0, 0]))   // a: top-left quarter circle
        XCTAssertEqual(zero[4], .empty)                                  // centre of the 0
        XCTAssertEqual(zero[14].radii, [0, 0, 1, 0])                     // c: bottom-right
        XCTAssertEqual(zero[0].curve, 1)
        XCTAssertEqual(zero[1].curve, 0)
        XCTAssertTrue(ModuleGlyphs.tiles(for: nil).allSatisfy { $0 == .empty })
        for d in "0123456789" { XCTAssertTrue(ModuleGlyphs.tiles(for: d).contains { $0.scale == 1 }) }
    }
}

final class R3EasingTests: XCTestCase {
    func testExpoInOut() {
        XCTAssertEqual(R3Easing.expoInOut(0), 0)
        XCTAssertEqual(R3Easing.expoInOut(1), 1)
        XCTAssertEqual(R3Easing.expoInOut(0.5), 0.5, accuracy: 1e-9)
        XCTAssertLessThan(R3Easing.expoInOut(0.2), 0.01)
    }

    func testBackOutOvershoots() {
        XCTAssertEqual(R3Easing.backOut(0), 0, accuracy: 1e-9)
        XCTAssertEqual(R3Easing.backOut(1), 1, accuracy: 1e-9)
        XCTAssertGreaterThan(stride(from: 0.0, through: 1, by: 0.01).map(R3Easing.backOut).max()!, 1.05)
    }
}
