import AppKit
import CoreText

/// A shaped word: one entry per glyph, so every letter can move on its own.
struct ProseWordShape {
    struct Glyph {
        let glyph: CGGlyph
        let font: CTFont
        let x: CGFloat          // pen position within the word
    }
    let token: ProseToken
    let glyphs: [Glyph]
    let width: CGFloat          // advance width including letter-spacing
}

/// Typography and line breaking for Prose, matching the prototype's CSS:
/// `.ps { font-size: 9.6cqw; line-height: 1.04; letter-spacing: -.012em; text-wrap: balance }`.
enum ProseLayout {
    static let fontSizeUnits: CGFloat = 9.6        // % of screen width
    static let lineHeight: CGFloat = 1.04          // em
    static let letterSpacing: CGFloat = -0.012     // em
    static let insetFraction: CGFloat = 0.09       // padding 0 9cqw
    static let maxWidthUnits: CGFloat = 80         // .ps-block max-width 80cqw
    static let captionGapUnits: CGFloat = 3.4      // .ps-block gap
    static let captionSizeUnits: CGFloat = 1.4
    static let ruleUnits: CGFloat = 3.2
    static let caretGap: CGFloat = 0.1, caretWidth: CGFloat = 0.05, caretHeight: CGFloat = 0.78, caretDrop: CGFloat = 0.04  // em

    /// Shapes one word with Core Text: kerning on, ligatures off (one glyph per letter).
    static func shape(_ token: ProseToken, fontSize fs: CGFloat) -> ProseWordShape {
        let font = Fonts.instrumentSerif(size: fs, italic: token.isHourWord)
        let attr = NSAttributedString(string: ProseSentence.display(token.text), attributes: [
            .font: font,
            .kern: letterSpacing * fs,
            .ligature: 0,
        ])
        let line = CTLineCreateWithAttributedString(attr)
        var glyphs: [ProseWordShape.Glyph] = []
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let n = CTRunGetGlyphCount(run)
            guard n > 0 else { continue }
            var ids = [CGGlyph](repeating: 0, count: n)
            var pos = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRange(location: 0, length: n), &ids)
            CTRunGetPositions(run, CFRange(location: 0, length: n), &pos)
            let attrs = CTRunGetAttributes(run) as NSDictionary
            let runFont = attrs[kCTFontAttributeName] as! CTFont   // swiftlint:disable:this force_cast
            for i in 0..<n { glyphs.append(.init(glyph: ids[i], font: runFont, x: pos[i].x)) }
        }
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        return ProseWordShape(token: token, glyphs: glyphs, width: width)
    }

    /// Width of the space between words (a regular-face space plus letter-spacing).
    static func spaceWidth(fontSize fs: CGFloat) -> CGFloat {
        let font = Fonts.instrumentSerif(size: fs, italic: false)
        var ch: UniChar = 0x20, g: CGGlyph = 0, adv = CGSize.zero
        CTFontGetGlyphsForCharacters(font, &ch, &g, 1)
        CTFontGetAdvancesForGlyphs(font, .horizontal, &g, &adv, 1)
        return adv.width + letterSpacing * fs
    }

    /// Greedy line filling: indices of the words on each line.
    static func greedy(_ widths: [CGFloat], space: CGFloat, maxWidth: CGFloat) -> [[Int]] {
        var lines: [[Int]] = []
        var current: [Int] = []
        var x: CGFloat = 0
        for (i, w) in widths.enumerated() {
            if current.isEmpty { current = [i]; x = w; continue }
            if x + space + w <= maxWidth + 0.01 { current.append(i); x += space + w }
            else { lines.append(current); current = [i]; x = w }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    /// `text-wrap: balance`: keep the greedy line count at full width, but use the narrowest
    /// width that still fits in that many lines, so the lines come out close to equal.
    static func balanced(_ widths: [CGFloat], space: CGFloat, maxWidth: CGFloat) -> [[Int]] {
        let target = greedy(widths, space: space, maxWidth: maxWidth)
        guard target.count > 1 else { return target }
        var lo = widths.max() ?? 0, hi = maxWidth
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if greedy(widths, space: space, maxWidth: mid).count <= target.count { hi = mid } else { lo = mid }
        }
        return greedy(widths, space: space, maxWidth: hi)
    }
}
