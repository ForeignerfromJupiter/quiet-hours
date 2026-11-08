import XCTest
@testable import QuietHoursPreview

final class ProseSentenceTests: XCTestCase {
    private func say(_ h: Int, _ m: Int) -> String { ProseSentence.markdown(ProseSentence.tokens(hour: h, minute: m)) }

    /// Every row of the Prose table in docs/PRD.md, verbatim.
    func testPRDTable() {
        let table: [(Int, Int, String)] = [
            (20, 0, "It's *eight* o'clock in the evening."),
            (20, 6, "It's just after five past *eight* in the evening."),
            (20, 8, "It's nearly ten past *eight* in the evening."),
            (20, 30, "It's half past *eight* in the evening."),
            (20, 58, "It's nearly *nine* o'clock at night."),
            (23, 58, "It's nearly *midnight*."),
            (0, 7, "It's just after five past *midnight*."),
            (12, 0, "It's *noon*."),
            (12, 30, "It's half past *twelve* in the afternoon."),
            (11, 35, "It's twenty-five to *noon*."),
        ]
        for (h, m, expected) in table {
            XCTAssertEqual(say(h, m), expected, String(format: "%02d:%02d", h, m))
        }
    }

    func testRoundingAroundEveryMark() {
        XCTAssertEqual(say(9, 0), "It's *nine* o'clock in the morning.")
        XCTAssertEqual(say(9, 1), "It's just after *nine* o'clock in the morning.")
        XCTAssertEqual(say(9, 2), "It's just after *nine* o'clock in the morning.")
        XCTAssertEqual(say(9, 3), "It's nearly five past *nine* in the morning.")
        XCTAssertEqual(say(9, 15), "It's a quarter past *nine* in the morning.")
        XCTAssertEqual(say(9, 25), "It's twenty-five past *nine* in the morning.")
        XCTAssertEqual(say(9, 33), "It's nearly twenty-five to *ten* in the morning.")
        XCTAssertEqual(say(9, 45), "It's a quarter to *ten* in the morning.")
        XCTAssertEqual(say(9, 55), "It's five to *ten* in the morning.")
        XCTAssertEqual(say(9, 57), "It's just after five to *ten* in the morning.")
        XCTAssertEqual(say(9, 58), "It's nearly *ten* o'clock in the morning.")
    }

    func testMidnightAndNoon() {
        XCTAssertEqual(say(0, 0), "It's *midnight*.")
        XCTAssertEqual(say(23, 45), "It's a quarter to *midnight*.")
        XCTAssertEqual(say(0, 30), "It's half past *midnight*.")
        XCTAssertEqual(say(0, 40), "It's twenty to *one* at night.")
        XCTAssertEqual(say(11, 58), "It's nearly *noon*.")
        XCTAssertEqual(say(11, 33), "It's nearly twenty-five to *noon*.")
        XCTAssertEqual(say(11, 30), "It's half past *eleven* in the morning.")
        XCTAssertEqual(say(12, 2), "It's just after *noon*.")
        XCTAssertEqual(say(12, 5), "It's five past *twelve* in the afternoon.")
    }

    func testPartOfDayFollowsTheNamedHour() {
        XCTAssertEqual(say(4, 58), "It's nearly *five* o'clock in the morning.")
        XCTAssertEqual(say(4, 30), "It's half past *four* at night.")
        XCTAssertEqual(say(16, 50), "It's ten to *five* in the evening.")
        XCTAssertEqual(say(20, 40), "It's twenty to *nine* at night.")
    }

    func testEveryMinuteOfTheDayIsWellFormed() {
        for h in 0..<24 {
            for m in 0..<60 {
                let t = ProseSentence.tokens(hour: h, minute: m)
                XCTAssertEqual(t.first?.text, "It's")
                XCTAssertTrue(t.last!.text.hasSuffix("."))
                XCTAssertEqual(t.filter(\.isHourWord).count, 1, "\(h):\(m)")
                XCTAssertFalse(t.contains { $0.text.isEmpty })
                XCTAssertFalse(ProseSentence.markdown(t).contains("afternoon") && h < 12, "\(h):\(m) morning called afternoon")
            }
        }
    }

    func testDisplayUsesCurlyApostrophes() {
        XCTAssertEqual(ProseSentence.display("It's"), "It\u{2019}s")
        XCTAssertEqual(ProseSentence.display("o'clock"), "o\u{2019}clock")
    }

    func testDiffKeepsSharedStartAndEnd() {
        let a = ProseSentence.tokens(hour: 20, minute: 6), b = ProseSentence.tokens(hour: 20, minute: 8)
        // "It's | just after five | past eight in the evening." → "It's | nearly ten | past eight in the evening."
        let d = ProseDiff.sharedEnds(a, b)
        XCTAssertEqual(d.prefix, 1)
        XCTAssertEqual(d.suffix, 5)
        let same = ProseSentence.tokens(hour: 20, minute: 7)
        XCTAssertEqual(ProseDiff.sharedEnds(a, same).prefix, a.count)
    }
}

final class FontTests: XCTestCase {
    func testBundledFontsLoadFromFile() {
        XCTAssertEqual(CTFontCopyPostScriptName(Fonts.instrumentSerif(size: 20, italic: false)) as String, "InstrumentSerif-Regular")
        XCTAssertEqual(CTFontCopyPostScriptName(Fonts.instrumentSerif(size: 20, italic: true)) as String, "InstrumentSerif-Italic")
        XCTAssertTrue((CTFontCopyPostScriptName(Fonts.anybody(size: 20, weight: 680, width: 74)) as String).hasPrefix("Anybody"))
    }
}

final class ProseLayoutTests: XCTestCase {
    func testGreedyFillsLines() {
        XCTAssertEqual(ProseLayout.greedy([10, 10, 10, 10], space: 1, maxWidth: 21), [[0, 1], [2, 3]])
        XCTAssertEqual(ProseLayout.greedy([50], space: 1, maxWidth: 20), [[0]], "an over-long word gets its own line")
    }

    func testBalanceKeepsLineCountButEvensLines() {
        // Greedy at 35 gives [0,1,2] [3] (31 / 10). Balanced keeps two lines but splits 2/2 (21 / 21).
        let w: [CGFloat] = [10, 10, 10, 10]
        XCTAssertEqual(ProseLayout.greedy(w, space: 0.5, maxWidth: 35), [[0, 1, 2], [3]])
        XCTAssertEqual(ProseLayout.balanced(w, space: 0.5, maxWidth: 35), [[0, 1], [2, 3]])
        XCTAssertEqual(ProseLayout.balanced(w, space: 0.5, maxWidth: 100), [[0, 1, 2, 3]])
    }

    func testShapingGivesOneGlyphPerLetter() {
        let s = ProseLayout.shape(ProseToken(text: "o'clock"), fontSize: 100)
        XCTAssertEqual(s.glyphs.count, 7)
        XCTAssertGreaterThan(s.width, 100)
        let italic = ProseLayout.shape(ProseToken(text: "eight", isHourWord: true), fontSize: 100)
        XCTAssertEqual(CTFontCopyPostScriptName(italic.glyphs[0].font) as String, "InstrumentSerif-Italic")
    }

    /// Three box passes stand in for the soft glyphs' Gaussian: odd widths, and the summed box
    /// variance ((w² − 1) / 12 each) within 10% of σ².
    func testSoftBlurBoxSizesMatchGaussian() {
        for sigma in [0.8, 1.5, 2.6, 4.0, 7.3] {
            let sizes = ProseRenderer.boxSizes(sigma: sigma, passes: 3)
            XCTAssertEqual(sizes.count, 3)
            XCTAssertTrue(sizes.allSatisfy { $0 % 2 == 1 && $0 >= 1 })
            let variance = sizes.map { Double($0 * $0 - 1) / 12 }.reduce(0, +)
            XCTAssertEqual(variance, sigma * sigma, accuracy: sigma * sigma * 0.1 + 0.35, "σ = \(sigma)")
        }
    }

    /// The blur spreads a single opaque pixel into a smooth, symmetric, energy-preserving bump.
    func testSoftBlurSpreadsAPixel() throws {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 41, height: 41, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 20, y: 20, width: 1, height: 1))
        let image = try XCTUnwrap(ProseRenderer.gaussianBlurred(ctx, sigma: 3))
        let data = try XCTUnwrap(image.dataProvider?.data) as Data
        let row = image.bytesPerRow
        func alpha(_ x: Int, _ y: Int) -> Int { Int(data[y * row + x * 4 + 3]) }
        XCTAssertLessThan(alpha(20, 20), 255)
        XCTAssertGreaterThan(alpha(20, 20), alpha(23, 20))
        XCTAssertGreaterThan(alpha(23, 20), 0)
        XCTAssertEqual(alpha(17, 20), alpha(23, 20), accuracy: 1)
        XCTAssertEqual(alpha(0, 0), 0)
    }
}
