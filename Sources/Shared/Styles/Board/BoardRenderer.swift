import AppKit
import QuartzCore

/// Anybody at one size and variation with tabular figures. Lays strings out with Core Text and
/// returns their outlines (y down, baseline at 0), so a scramble can swap any digit's glyph in
/// without re-shaping the line.
private final class BoardFace {
    struct Slot { let index: Int; let glyph: CGGlyph; let x: CGFloat; let advance: CGFloat }
    struct Line { let slots: [Slot]; let width: CGFloat }

    let font: CTFont
    let ascent: CGFloat, descent: CGFloat
    private let tracking: CGFloat
    private var outlines: [CGGlyph: CGPath] = [:]
    private var lines: [String: Line] = [:]
    private var digits: [Slot] = []

    /// `tracking` in em (CSS letter-spacing).
    init(size: CGFloat, weight: CGFloat, width: CGFloat, tracking: CGFloat = 0) {
        let base = Fonts.anybody(size: size, weight: weight, width: width)
        let tnum: [CFString: Any] = [kCTFontOpenTypeFeatureTag: "tnum", kCTFontOpenTypeFeatureValue: 1]   // "tnum"
        let extra = CTFontDescriptorCreateWithAttributes([kCTFontFeatureSettingsAttribute: [tnum]] as CFDictionary)
        font = CTFontCreateCopyWithAttributes(base, size, nil, extra)
        ascent = CTFontGetAscent(font)
        descent = CTFontGetDescent(font)
        self.tracking = tracking * size
        digits = line("0123456789").slots
    }

    func line(_ text: String) -> Line {
        if let hit = lines[text] { return hit }
        let attr = NSAttributedString(string: text, attributes: [.font: font, .kern: tracking])
        let ct = CTLineCreateWithAttributedString(attr)
        var slots: [Slot] = []
        for run in (CTLineGetGlyphRuns(ct) as? [CTRun]) ?? [] {
            let n = CTRunGetGlyphCount(run)
            let all = CFRange(location: 0, length: n)
            var glyphs = [CGGlyph](repeating: 0, count: n), pos = [CGPoint](repeating: .zero, count: n)
            var adv = [CGSize](repeating: .zero, count: n), idx = [CFIndex](repeating: 0, count: n)
            CTRunGetGlyphs(run, all, &glyphs)
            CTRunGetPositions(run, all, &pos)
            CTRunGetAdvances(run, all, &adv)
            CTRunGetStringIndices(run, all, &idx)
            for i in 0..<n { slots.append(Slot(index: idx[i], glyph: glyphs[i], x: pos[i].x, advance: adv[i].width)) }
        }
        let result = Line(slots: slots, width: CGFloat(CTLineGetTypographicBounds(ct, nil, nil, nil)))
        if lines.count > 256 { lines.removeAll() }
        lines[text] = result
        return result
    }

    /// The outline of `line` with `display` drawn into its slots (a scrambled copy of the line's
    /// text: replaced digits are centred in the slot of the digit they stand in for).
    func path(_ line: Line, display: [Character], origin: CGPoint, into path: CGMutablePath) {
        for s in line.slots {
            var glyph = s.glyph, x = s.x
            if s.index < display.count, let v = display[s.index].wholeNumberValue, v < digits.count,
               digits[v].glyph != glyph {
                glyph = digits[v].glyph
                x += (s.advance - digits[v].advance) / 2
            }
            path.addPath(outline(glyph), transform: CGAffineTransform(translationX: origin.x + x, y: origin.y))
        }
    }

    private func outline(_ glyph: CGGlyph) -> CGPath {
        if let hit = outlines[glyph] { return hit }
        var flip = CGAffineTransform(scaleX: 1, y: -1)
        let p = CTFontCreatePathForGlyph(font, glyph, &flip) ?? CGMutablePath()
        outlines[glyph] = p
        return p
    }

    /// Baseline for a CSS line box of height `lineHeight` starting at `top` (half-leading model).
    func baseline(top: CGFloat, lineHeight: CGFloat) -> CGFloat {
        top + (lineHeight - (ascent + descent)) / 2 + ascent
    }
}

/// Board: a Swiss timetable of world time. Ported from the prototype's `Board`.
///
/// Local time very large at the top with the city, date, AM/PM and UTC offset in mono on the
/// right; an accent seconds bar; six ruled city rows with a working-hours dot, offset from local,
/// day relative to local and time. On each minute the header and then each row (90 ms apart)
/// scramble their digits and settle left to right. All the world-time data comes from
/// `BoardModel` (Calendar + TimeZone, so daylight saving is always right).
///
/// Idle between minutes: the seconds bar steps once a second with a short ease, so the display
/// link only runs for that ease and during a scramble.
final class BoardRenderer: ClockStyle {
    /// A line of Anybody digits that can scramble: the header time and each row's time.
    private final class TimeLine {
        let layer = CAShapeLayer()
        var shown = ""            // settled text on screen
        var target: String?       // text being scrambled in
        var start: Double = 0     // scramble start, scaled seconds
        var drawn = "\u{0}"       // what the path currently shows
        var origin = CGPoint.zero // left (header) or right (rows) edge, baseline
        var alignRight = false
    }

    private struct RowLayers {
        let dot = CALayer()
        let offset = CATextLayer()
        let day = CATextLayer()
        let rule = CALayer()
    }

    /// Prototype `.bd-*` CSS, in `u` (1% of the width, the CSS cqw).
    private enum M {
        static let padTop: CGFloat = 5, padSide: CGFloat = 6.5, padBottom: CGFloat = 4.5
        static let bigSize: CGFloat = 15, bigLine: CGFloat = 0.78      // .bd-big 15cqw / .78
        static let headPadBottom: CGFloat = 1.6
        static let metaSize: CGFloat = 1.15, metaGap: CGFloat = 0.9, metaTrack: CGFloat = 0.2
        static let barHeight: CGFloat = 0.35, barGap: CGFloat = 1
        static let dotCol: CGFloat = 1.6, offCol: CGFloat = 9, dayCol: CGFloat = 11, timeCol: CGFloat = 20, gap: CGFloat = 1.4
        static let dot: CGFloat = 0.9
        static let citySize: CGFloat = 3, timeSize: CGFloat = 3.6
        static let rowLabelSize: CGFloat = 1.05, rowLabelTrack: CGFloat = 0.16
        /// Height cap in u, so six rows always fit (ultrawides): rows keep ≥ 5u each.
        static let minHeightUnits: CGFloat = 54
    }

    private static let barEase = 0.3

    private let context: StyleContext
    private var appearance: Appearance
    private var palette: R3Palette
    private let chrome = R3Chrome()

    private let header = TimeLine()
    private let rowTimes = (0..<BoardModel.rowCount).map { _ in TimeLine() }
    private let rows = (0..<BoardModel.rowCount).map { _ in RowLayers() }
    private let cityNames = CAShapeLayer()
    private let meta = [CATextLayer(), CATextLayer(), CATextLayer()]   // city, date, sub
    private let barTrack = CALayer(), barFill = CALayer()

    private var bounds = CGRect.zero, scale: CGFloat = 2
    private var u: CGFloat = 0, side: CGFloat = 0, contentW: CGFloat = 0
    private var rowCenters: [CGFloat] = []
    private var bigFace: BoardFace?, cityFace: BoardFace?, timeFace: BoardFace?

    private var local = TimeZone.autoupdatingCurrent
    private var localID = ""
    private var cities: [BoardModel.City] = []
    private var minuteKey = ""
    private var lastSecond = -1
    private var metaText = ["", "", ""], metaDrawn = ["", "", ""]
    private var rowData: [BoardModel.Row] = []
    private var rowDrawn: [BoardModel.Row?] = Array(repeating: nil, count: BoardModel.rowCount)
    private var scrambling = false

    private var barSecond = -1
    private var barFrom = 0.0, barTo = 0.0, barStart = -Double.infinity
    private var barDrawn: CGFloat = -1
    private var barAnimating = false

    private var speed: Double { max(context.timeScale, 0.01) }

    init(context: StyleContext) {
        self.context = context
        self.palette = .forAppearance(context.appearance)
        self.appearance = context.appearance
    }

    var wantsContinuousFrames: Bool { scrambling || barAnimating }

    func start(in root: CALayer) {
        chrome.install(in: root)
        root.addSublayer(barTrack)
        root.addSublayer(barFill)
        barFill.anchorPoint = .zero
        for r in rows {
            for l in [r.rule, r.dot, r.offset, r.day] as [CALayer] { root.addSublayer(l) }
            r.dot.borderWidth = 1
            for t in [r.offset, r.day] { t.alignmentMode = .left; t.isWrapped = false }
        }
        root.addSublayer(cityNames)
        for t in [header] + rowTimes { root.addSublayer(t.layer) }
        for m in meta { m.alignmentMode = .right; m.isWrapped = false; root.addSublayer(m) }
        header.alignRight = false
        for t in rowTimes { t.alignRight = true }
        applyPalette()
    }

    // MARK: Layout

    func layout(bounds: CGRect, scale: CGFloat) {
        self.bounds = bounds
        self.scale = scale
        chrome.layout(bounds: bounds, scale: scale)
        let stage = Room.stage(bounds), W = stage.width, H = bounds.height
        u = max(min(W / 100, H / M.minHeightUnits), 0.01)
        side = stage.minX + M.padSide * u
        contentW = W - 2 * M.padSide * u

        bigFace = BoardFace(size: M.bigSize * u, weight: 800, width: 78, tracking: -0.01)
        cityFace = BoardFace(size: M.citySize * u, weight: 620, width: 100)
        timeFace = BoardFace(size: M.timeSize * u, weight: 760, width: 82)

        // Header: .bd-big line box, meta block bottom-aligned with it on the right.
        let top = M.padTop * u
        let bigLine = M.bigSize * M.bigLine * u
        header.origin = CGPoint(x: side, y: bigFace?.baseline(top: top, lineHeight: bigLine) ?? 0)
        let headBottom = top + bigLine
        let metaFont = Fonts.label(size: M.metaSize * u)
        for (i, m) in meta.enumerated() {
            let boxTop = headBottom - CGFloat(3 - i) * M.metaSize * u - CGFloat(2 - i) * M.metaGap * u
            m.frame = textFrame(metaFont, boxTop: boxTop, boxHeight: M.metaSize * u,
                                x: side + contentW * 0.4, width: contentW * 0.6)
            m.contentsScale = scale
        }

        // Seconds bar.
        let barY = headBottom + M.headPadBottom * u
        barTrack.frame = CGRect(x: side, y: barY, width: contentW, height: M.barHeight * u)
        barFill.frame = CGRect(x: side, y: barY, width: 0, height: M.barHeight * u)
        barDrawn = -1

        // Rows: six equal tracks down to the bottom padding, ruled underneath, items centred.
        let rowsTop = barY + (M.barHeight + M.barGap) * u
        let rowH = (H - M.padBottom * u - rowsTop) / CGFloat(BoardModel.rowCount)
        let rule: CGFloat = 1
        rowCenters = (0..<BoardModel.rowCount).map { rowsTop + CGFloat($0) * rowH + (rowH - rule) / 2 }
        let labelFont = Fonts.label(size: M.rowLabelSize * u)
        let offX = side + contentW - (M.timeCol + M.gap + M.dayCol + M.gap + M.offCol) * u
        let dayX = side + contentW - (M.timeCol + M.gap + M.dayCol) * u
        for (i, r) in rows.enumerated() {
            let cy = rowCenters[i]
            r.rule.frame = CGRect(x: side, y: rowsTop + CGFloat(i + 1) * rowH - rule, width: contentW, height: rule)
            let d = M.dot * u + 2   // content-box: .9cqw plus a 1px border each side
            r.dot.frame = CGRect(x: side, y: cy - d / 2, width: d, height: d)
            r.dot.cornerRadius = d / 2
            r.offset.frame = textFrame(labelFont, boxTop: cy - M.rowLabelSize * u / 2, boxHeight: M.rowLabelSize * u,
                                       x: offX, width: (M.offCol + M.gap) * u)
            r.day.frame = textFrame(labelFont, boxTop: cy - M.rowLabelSize * u / 2, boxHeight: M.rowLabelSize * u,
                                    x: dayX, width: (M.dayCol + M.gap) * u)
            for t in [r.offset, r.day] { t.contentsScale = scale }
            rowTimes[i].origin = CGPoint(x: side + contentW,
                                         y: timeFace?.baseline(top: cy - M.timeSize * u / 2, lineHeight: M.timeSize * u) ?? 0)
        }
        for l in [cityNames] + ([header] + rowTimes).map(\.layer) { l.frame = bounds; l.contentsScale = scale }

        drawCityNames()
        for t in [header] + rowTimes { t.drawn = "\u{0}" }
        metaDrawn = ["", "", ""]
        rowDrawn = Array(repeating: nil, count: BoardModel.rowCount)
    }

    /// A one-line text layer whose glyphs sit centred in a CSS line box (line-height 1).
    private func textFrame(_ font: NSFont, boxTop: CGFloat, boxHeight: CGFloat, x: CGFloat, width: CGFloat) -> CGRect {
        let a = font.ascender, d = -font.descender
        let y = boxTop + (boxHeight - (a + d)) / 2
        return CGRect(x: x, y: y, width: width, height: a + d + font.leading + 2)
    }

    private func drawCityNames() {
        guard let face = cityFace, !rowCenters.isEmpty else { return }
        let path = CGMutablePath()
        let x = side + (M.dotCol + M.gap) * u
        for (i, c) in cities.enumerated() where i < rowCenters.count {
            let line = face.line(c.name)
            let base = face.baseline(top: rowCenters[i] - M.citySize * u / 2, lineHeight: M.citySize * u)
            face.path(line, display: [], origin: CGPoint(x: x, y: base), into: path)
        }
        cityNames.path = path
    }

    // MARK: Frame

    func render(time: ClockTime, frameTime: CFTimeInterval) {
        let T = frameTime / speed
        let date = time.date

        if time.second != lastSecond {
            lastSecond = time.second
            let id = TimeZone.autoupdatingCurrent.identifier
            if id != localID {
                localID = id
                local = TimeZone(identifier: id) ?? .current
                cities = BoardModel.cities(local: local)
                drawCityNames()
                minuteKey = ""
            }
            let h = BoardModel.header(local: local, at: date, uses24Hour: time.uses24Hour, showSeconds: context.showSeconds)
            metaText = [h.city, h.date, h.sub]
        }

        let key = "\(time.hour24):\(time.minute):\(time.uses24Hour)"
        if key != minuteKey {
            let first = minuteKey.isEmpty
            minuteKey = key
            let h = BoardModel.header(local: local, at: date, uses24Hour: time.uses24Hour, showSeconds: context.showSeconds)
            metaText = [h.city, h.date, h.sub]
            rowData = BoardModel.rows(local: local, at: date, uses24Hour: time.uses24Hour)
            let instant = first || context.reduceMotion
            begin(header, h.time, at: T, instant: instant)
            for (i, r) in rowData.enumerated() where i < rowTimes.count {
                begin(rowTimes[i], r.time, at: T + BoardModel.rowLead + Double(i) * BoardModel.rowStep, instant: instant)
            }
        }

        updateLabels()

        scrambling = false
        let seed = time.hour24 * 60 + time.minute
        if let face = bigFace { step(header, face, T, seed: seed * 8) }
        if let face = timeFace {
            for (i, t) in rowTimes.enumerated() { step(t, face, T, seed: seed * 8 + i + 1) }
        }

        updateBar(time, T)
    }

    private func begin(_ line: TimeLine, _ text: String, at start: Double, instant: Bool) {
        if let pending = line.target { line.shown = pending }
        if instant {
            line.shown = text
            line.target = nil
        } else {
            line.target = text
            line.start = start
        }
    }

    /// Advances one line's scramble and redraws its path when the visible text changed.
    private func step(_ line: TimeLine, _ face: BoardFace, _ T: Double, seed: Int) {
        var display = line.shown, layoutText = line.shown
        if let target = line.target {
            let e = T - line.start
            if e < 0 {
                scrambling = true
            } else if let s = BoardModel.scrambled(target, elapsed: e, seed: seed) {
                scrambling = true
                display = s
                layoutText = target
            } else {
                line.shown = target
                line.target = nil
                display = target
                layoutText = target
            }
        }
        let token = layoutText + "\u{1}" + display
        guard token != line.drawn else { return }
        line.drawn = token
        let l = face.line(layoutText)
        let x = line.alignRight ? line.origin.x - l.width : line.origin.x
        let path = CGMutablePath()
        face.path(l, display: Array(display), origin: CGPoint(x: x, y: line.origin.y), into: path)
        line.layer.path = path
    }

    private func updateLabels() {
        let metaFont = Fonts.label(size: M.metaSize * u)
        for i in meta.indices where metaText[i] != metaDrawn[i] {
            metaDrawn[i] = metaText[i]
            meta[i].string = label(metaText[i], font: metaFont, tracking: M.metaTrack, color: i == 0 ? palette.ink : muted)
        }
        let rowFont = Fonts.label(size: M.rowLabelSize * u)
        for (i, r) in rowData.enumerated() where i < rows.count && rowDrawn[i] != r {
            let old = rowDrawn[i]
            rowDrawn[i] = r
            let layers = rows[i]
            if old?.offset != r.offset {
                layers.offset.string = label(r.offset, font: rowFont, tracking: M.rowLabelTrack, color: muted)
            }
            if old?.day != r.day {
                layers.day.string = label(r.day.rawValue, font: rowFont, tracking: M.rowLabelTrack, color: muted)
            }
            if old?.working != r.working { paintDot(layers.dot, on: r.working) }
        }
    }

    private func label(_ s: String, font: NSFont, tracking: CGFloat, color: CGColor) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [
            .font: font, .kern: tracking * font.pointSize,
            .foregroundColor: NSColor(cgColor: color) ?? .gray,
        ])
    }

    private func paintDot(_ dot: CALayer, on: Bool) {
        dot.backgroundColor = on ? palette.accent : CGColor(gray: 0, alpha: 0)
        dot.borderColor = on ? palette.accent : rule
    }

    /// The bar steps once a second (so the view can idle between seconds) with a short ease out;
    /// it empties at once on the minute, like the prototype's bar.
    private func updateBar(_ time: ClockTime, _ T: Double) {
        if time.second != barSecond {
            let to = Double(time.second) / 60
            if barSecond < 0 || context.reduceMotion || to < barTo {
                barFrom = to
                barStart = -.infinity
            } else {
                barFrom = barValue(T)
                barStart = T
            }
            barTo = to
            barSecond = time.second
        }
        let k = (T - barStart) / Self.barEase
        barAnimating = k < 1
        let v = CGFloat(barValue(T))
        guard v != barDrawn else { return }
        barDrawn = v
        barFill.bounds.size.width = contentW * v
    }

    private func barValue(_ T: Double) -> Double {
        let k = min(max((T - barStart) / Self.barEase, 0), 1)
        let e = 1 - pow(1 - k, 3)
        return barFrom + (barTo - barFrom) * e
    }

    // MARK: Appearance

    private var muted: CGColor { palette.ink(appearance == .dark ? 0.45 : 0.5) }   // --muted
    private var rule: CGColor { palette.ink(appearance == .dark ? 0.14 : 0.16) }   // --rule

    func appearanceDidChange(_ appearance: Appearance) {
        self.appearance = appearance
        palette = .forAppearance(appearance)
        applyPalette()
    }

    func stop() {
        chrome.remove()
        var all: [CALayer] = [barTrack, barFill, cityNames] + meta + ([header] + rowTimes).map(\.layer)
        for r in rows { all += [r.rule, r.dot, r.offset, r.day] }
        for l in all { l.removeFromSuperlayer() }
    }

    private func applyPalette() {
        chrome.apply(palette, pureBlack: context.pureBlack && appearance == .dark)
        barTrack.backgroundColor = rule
        barFill.backgroundColor = palette.accent
        cityNames.fillColor = palette.ink
        for t in [header] + rowTimes { t.layer.fillColor = palette.ink }
        for r in rows { r.rule.backgroundColor = rule }
        metaDrawn = ["", "", ""]
        rowDrawn = Array(repeating: nil, count: BoardModel.rowCount)
    }
}
