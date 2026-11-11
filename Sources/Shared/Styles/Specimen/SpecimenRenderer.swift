import AppKit
import QuartzCore

/// Specimen's pure numbers (prototype `Specimen`): the axis grid, the weight wave, the seconds
/// cell and the swap cascade. No layers, so it is unit-tested directly.
enum SpecimenSheet {
    static let columns = 4, rows = 3
    /// `WD`: width axis per column.
    static let widths: [Double] = [55, 84, 114, 144]
    /// `WG`: weight axis per row.
    static let weights: [Double] = [220, 520, 820]
    /// `150*Math.sin(t/1100-(c.r+c.col)*.6)`, clamped to 100…900 (t in ms).
    static let waveAmplitude = 150.0
    static let waveTime = 1.1          // s: the sine's time constant (period 2π·1.1 ≈ 6.9 s)
    static let wavePhase = 0.6         // per diagonal step (row + column)
    /// Cascade: cells start 75 ms apart in reading order, each swap takes 460 ms.
    static let stagger = 0.075
    static let swapDuration = 0.46
    /// `.sp-cell .t{transition:color .5s}` (CSS `ease`).
    static let hotFade = 0.5
    static let hotEase = CubicBezier(0.25, 0.1, 0.25, 1)

    /// Weight drawn in a cell at time `t` (seconds, slow-motion already applied). The prototype
    /// sets `"wght" w.toFixed(0)`, so the drawn value is a whole number, and the label shows the same.
    static func weight(row: Int, column: Int, time t: Double, reduceMotion: Bool) -> Double {
        let wave = reduceMotion ? 0 : waveAmplitude * sin(t / waveTime - Double(row + column) * wavePhase)
        return min(max(weights[row] + wave, 100), 900).rounded()
    }

    static func width(column: Int) -> Double { widths[column] }

    /// `hot=Math.floor(((p.s+p.ms/1000)/60)*12)`: one cell per 5 s, in reading order.
    static func hotCell(second: Int, millisecond: Int) -> Int {
        let f = (Double(second) + Double(millisecond) / 1000) / 60
        return min(columns * rows - 1, max(0, Int((f * 12).rounded(.down))))
    }

    /// Delay of cell `index` (reading order) after a time change.
    static func delay(index: Int) -> Double { Double(index) * stagger }

    /// One cell's swap at progress `k` = elapsed / 460 ms: fade and rise out (up to −0.25 em) for
    /// the first half, then swap and fade and rise in from +0.125 em. `dy` is in em.
    static func swap(_ k: Double) -> (opacity: Double, dy: Double, swapped: Bool, done: Bool) {
        if k < 0 { return (1, 0, false, false) }
        if k < 0.5 { return (1 - k * 2, -k * 0.5, false, false) }
        return (min(1, (k - 0.5) * 2), (1 - min(1, k)) * 0.25, true, k >= 1)
    }

    /// `trimTime`: "09:05" in 24h, "9:05" in 12h.
    static func text(_ time: ClockTime) -> String {
        let d = time.digits.compactMap { $0 }
        return String(d.dropLast(2)) + ":" + String(d.suffix(2))
    }

    /// `WDTH 84  ·  WGHT 531` (the spaces collapse in the prototype's HTML, so they're single here).
    static func label(width: Double, weight: Double) -> String {
        "WDTH \(Int(width.rounded())) · WGHT \(Int(weight.rounded()))"
    }

    static let title = "QUIET HOURS / SPECIMEN / ANYBODY VARIABLE"

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_GB")
        df.dateFormat = "EEEE dd MMM"
        return df
    }()

    /// `toLocaleDateString('en-GB',{weekday:'long',day:'2-digit',month:'short'})`, upper-cased,
    /// then AM/PM and seconds (the prototype's double spaces collapse to one in HTML).
    static func dateLine(_ time: ClockTime, showSeconds: Bool, calendar: Calendar = .current) -> String {
        // One formatter, reconfigured only when the calendar changes: building or reconfiguring
        // a DateFormatter costs about a millisecond (ICU setup).
        let df = dateFormatter
        if df.calendar != calendar { df.calendar = calendar }
        if df.timeZone != calendar.timeZone { df.timeZone = calendar.timeZone }
        var parts = [df.string(from: time.date).uppercased().replacingOccurrences(of: ".", with: "")]
        if let m = time.meridiem { parts.append(m) }
        if showSeconds { parts.append(time.secondsMark) }
        return parts.joined(separator: " ")
    }
}

/// Specimen: the time set twelve times as a type specimen sheet, each cell a different width and
/// weight of Anybody, with live axis values, a weight wave rippling diagonally and a cell-by-cell
/// cascade on each change. Ported from the prototype's `Specimen` (1 u = 1% of screen width, `cqw`).
///
/// Every frame each cell builds its glyph paths from a Core Text instance of the bundled variable
/// font at that cell's (wdth, wght), like Breath. Weights are whole numbers (as in the prototype),
/// and a cell only rebuilds its path when its text, weight or size changed. The weight wave moves
/// every cell almost every frame, so that rebuild skips Core Text shaping (Anybody doesn't kern
/// digits or the colon, so glyph advances give the same positions) and the live axis labels are
/// shape paths from cached glyph outlines rather than text layers re-rasterised every frame.
final class SpecimenRenderer: ClockStyle {
    private final class Cell {
        let row: Int, column: Int
        let clip = CALayer()             // `.sp-cell{overflow:hidden}`: clips to the padding box
        let glyphs = CAShapeLayer()      // `.t`
        let label = CAShapeLayer()       // `.c`, from cached glyph outlines
        var shown: String?               // `v`
        var next: String?                // `next`
        var start: Double = 0            // `t0` (seconds)
        var pathKey = ""
        var labelText = ""
        var labelBaseline: CGFloat = 0
        var hot = false
        var hotFrom = 0.0, hotStart = -1e9
        var hotLevel = 0.0
        var fill: Double = -1
        init(row: Int, column: Int) { self.row = row; self.column = column }
        var index: Int { row * SpecimenSheet.columns + column }
    }

    private let context: StyleContext
    private var appearance: Appearance
    private var palette: R3Palette
    private let chrome = R3Chrome()
    private let rules = (0..<9).map { _ in CALayer() }   // 5 vertical, 4 horizontal hairlines
    private let title = CATextLayer()
    private let date = CATextLayer()
    private let cells: [Cell]

    private var bounds = CGRect.zero, scale: CGFloat = 2
    private var unit: CGFloat = 1
    /// Numeral size: 5.2 u as in the prototype, smaller if the widest cell would not fit its
    /// column or the cells are too short (ultrawide screens).
    private var fontSize: CGFloat = 5.2
    private var dateText = ""
    private var dateSecond = Int.min
    private var labelGlyphs = GlyphStrip(font: Fonts.label(size: 1), kern: 0.14)
    private var speed: Double { max(context.timeScale, 0.01) }

    init(context: StyleContext) {
        self.context = context
        self.appearance = context.appearance
        self.palette = .forAppearance(context.appearance)
        var cs: [Cell] = []
        for r in 0..<SpecimenSheet.rows { for c in 0..<SpecimenSheet.columns { cs.append(Cell(row: r, column: c)) } }
        cells = cs
    }

    // MARK: Lifecycle

    func start(in root: CALayer) {
        chrome.install(in: root)
        for l in rules { root.addSublayer(l) }
        for l in [title, date] {
            l.isWrapped = false
            root.addSublayer(l)
        }
        title.alignmentMode = .left
        date.alignmentMode = .right
        // Text layers redraw in the commit's display pass, outside the render transaction: without
        // this their `contents` would cross-fade (ghosted digits on the live axis labels).
        let still: [String: CAAction] = ["contents": NSNull(), "string": NSNull(), "bounds": NSNull(), "position": NSNull()]
        for l in [title, date] { l.actions = still }
        for c in cells {
            c.clip.masksToBounds = true
            c.clip.addSublayer(c.glyphs)
            c.clip.addSublayer(c.label)
            root.addSublayer(c.clip)
        }
        applyPalette()
    }

    func layout(bounds: CGRect, scale: CGFloat) {
        self.bounds = bounds
        self.scale = scale
        chrome.layout(bounds: bounds, scale: scale)
        // The sheet is a page: on ultrawide screens it keeps to a centred stage at most 16:9.
        let stage = Room.stage(bounds)
        let u = stage.width / 100
        unit = u
        let px = 1 / max(scale, 1)
        let snap: (CGFloat) -> CGFloat = { ($0 * scale).rounded() / scale }

        // .spec{padding:4.5cqw 5cqw; grid-template-rows:auto 1fr; gap:2cqw}; header line box 1.1 u.
        let gx = stage.minX + 5 * u, gw = stage.width - 10 * u
        let headTop = 4.5 * u, headH = 1.1 * u
        let gy = headTop + headH + 2 * u
        let gh = max(1, bounds.height - 4.5 * u - gy)

        // .sp-head: 500 1.1cqw/1 mono, letter-spacing .22em
        let hf = Fonts.label(size: max(1, headH))
        let hBox = textBox(font: hf, lineTop: headTop, lineHeight: headH)
        title.frame = CGRect(x: gx, y: hBox.y, width: gw * 0.7, height: hBox.h)
        date.frame = CGRect(x: gx + gw * 0.3, y: hBox.y, width: gw * 0.7, height: hBox.h)
        title.string = attributed(SpecimenSheet.title, font: hf, kern: 0.22)

        // .sp-grid: border-top/left 1px; cells carry border-right/bottom 1px (content-box tracks).
        let cw = (gw - 1) / CGFloat(SpecimenSheet.columns)
        let ch = (gh - 1) / CGFloat(SpecimenSheet.rows)
        let line = max(px, 1)   // CSS 1px = 1 pt
        for i in 0...SpecimenSheet.columns {
            let x = i == 0 ? gx : gx + 1 + CGFloat(i) * cw - 1
            rules[i].frame = CGRect(x: snap(x), y: snap(gy), width: line, height: snap(gh))
        }
        for j in 0...SpecimenSheet.rows {
            let y = j == 0 ? gy : gy + 1 + CGFloat(j) * ch - 1
            rules[SpecimenSheet.columns + 1 + j].frame = CGRect(x: snap(gx), y: snap(y), width: snap(gw), height: line)
        }

        // The widest instance (last column at weight 900) must fit inside the cell's padding, and
        // the numerals plus the axis label must fit its height.
        let fitWidth = (cw - 1 - 2.8 * u) / Self.widestText
        let fitHeight = ch - 1 - (1.3 + 1.1 + 0.95 + 0.8) * u
        fontSize = max(1, min(5.2 * u, fitWidth, fitHeight))

        // .sp-cell .c: 500 .95cqw/1 mono, letter-spacing .14em, padding-bottom 1.1 u
        let lf = Fonts.label(size: max(1, 0.95 * u))
        labelGlyphs = GlyphStrip(font: lf, kern: 0.14)
        for c in cells {
            let x = gx + 1 + CGFloat(c.column) * cw, y = gy + 1 + CGFloat(c.row) * ch
            c.clip.frame = CGRect(x: x, y: y, width: max(0, cw - 1), height: max(0, ch - 1))
            c.glyphs.frame = c.clip.bounds
            c.glyphs.contentsScale = scale
            let lBox = textBox(font: lf, lineTop: ch - 1 - 1.1 * u - 0.95 * u, lineHeight: 0.95 * u)
            c.label.frame = CGRect(x: 1.4 * u, y: lBox.y, width: max(0, cw - 1 - 2.8 * u), height: lBox.h)
            c.label.contentsScale = scale
            c.labelBaseline = lf.ascender
            c.pathKey = ""
            c.labelText = ""
        }
        for l in [title, date] { l.contentsScale = scale }
        dateText = ""
        dateSecond = Int.min
    }

    func render(time: ClockTime, frameTime: CFTimeInterval) {
        let T = frameTime / speed
        let reduce = context.reduceMotion
        let txt = SpecimenSheet.text(time)
        let hot = SpecimenSheet.hotCell(second: time.second, millisecond: time.millisecond)
        let fs = fontSize                     // .sp-cell .t{font-size:5.2cqw;line-height:1}

        for c in cells {
            // Text change → cascade (prototype frame(): c.v / c.next / c.t0 / c.sw)
            if c.shown == nil {
                c.shown = txt
            } else if txt != c.shown && txt != c.next {
                if reduce { c.shown = txt; c.next = nil }
                else { c.next = txt; c.start = T + SpecimenSheet.delay(index: c.index) }
            }
            var opacity = 1.0, dy = 0.0
            if let next = c.next {
                let s = SpecimenSheet.swap((T - c.start) / SpecimenSheet.swapDuration)
                opacity = s.opacity; dy = s.dy
                if s.swapped { c.shown = next }
                if s.done { c.next = nil }
            }

            let wd = SpecimenSheet.width(column: c.column)
            let wg = SpecimenSheet.weight(row: c.row, column: c.column, time: T, reduceMotion: reduce)
            updateGlyphs(c, text: c.shown ?? txt, width: wd, weight: wg, size: fs)
            let op = Float(opacity)
            if c.glyphs.opacity != op { c.glyphs.opacity = op }
            let ty = CGFloat(dy) * fs
            if c.glyphs.affineTransform().ty != ty { c.glyphs.setAffineTransform(CGAffineTransform(translationX: 0, y: ty)) }

            // Seconds cell: `.hot .t{color:var(--acc)}` with a 0.5 s colour transition.
            let isHot = c.index == hot
            if isHot != c.hot {
                c.hotFrom = c.hotLevel
                c.hotStart = T
                c.hot = isHot
            }
            let target = c.hot ? 1.0 : 0.0
            if reduce { c.hotLevel = target }
            else {
                let k = (T - c.hotStart) / SpecimenSheet.hotFade
                c.hotLevel = k >= 1 ? target : c.hotFrom + (target - c.hotFrom) * SpecimenSheet.hotEase(k)
            }
            if c.hotLevel != c.fill { c.fill = c.hotLevel; c.glyphs.fillColor = palette.blend(c.hotLevel) }

            let lt = SpecimenSheet.label(width: wd, weight: wg)
            if lt != c.labelText {
                c.labelText = lt
                c.label.path = labelGlyphs.path(lt, baseline: c.labelBaseline)
            }
        }

        // The date line changes at most once a second.
        let second = Int(time.date.timeIntervalSince1970.rounded(.down))
        guard second != dateSecond else { return }
        dateSecond = second
        let dl = SpecimenSheet.dateLine(time, showSeconds: context.showSeconds)
        if dl != dateText {
            dateText = dl
            date.string = attributed(dl, font: Fonts.label(size: max(1, 1.1 * unit)), kern: 0.22)
        }
    }

    /// Width of the widest possible time ("88:88" in its widest digits) at the widest instance
    /// (wdth 144, wght 900), per point of font size.
    static let widestText: CGFloat = {
        let size: CGFloat = 100
        let font = Fonts.anybody(size: size, weight: 900, width: CGFloat(SpecimenSheet.widths.max() ?? 144))
        func advance(_ c: Character) -> CGFloat {
            var u = UniChar(c.unicodeScalars.first!.value), g: CGGlyph = 0, adv = CGSize.zero
            guard CTFontGetGlyphsForCharacters(font, &u, &g, 1) else { return size * 0.6 }
            CTFontGetAdvancesForGlyphs(font, .horizontal, &g, &adv, 1)
            return adv.width
        }
        let digit = "0123456789".map(advance).max() ?? size * 0.6
        return (4 * digit + advance(":")) / size
    }()

    /// Reduce motion: nothing moves between changes, so the view can tick once per second.
    var wantsContinuousFrames: Bool { !context.reduceMotion }

    func appearanceDidChange(_ appearance: Appearance) {
        self.appearance = appearance
        palette = .forAppearance(appearance)
        applyPalette()
    }

    func stop() {
        chrome.remove()
        for l in rules + [title, date] { l.removeFromSuperlayer() }
        for c in cells { c.clip.removeFromSuperlayer() }
    }

    // MARK: Drawing

    /// Glyph paths for one cell at its live (wdth, wght), set like the CSS line box: line-height 1,
    /// baseline centred by ascent/descent, 1.3 u from the cell top and 1.4 u from its left.
    private func updateGlyphs(_ c: Cell, text: String, width: Double, weight: Double, size: CGFloat) {
        let key = "\(text)|\(Int(width))|\(Int(weight))|\(Int((size * 64).rounded()))"
        guard key != c.pathKey else { return }
        c.pathKey = key
        let font = Fonts.anybody(size: size, weight: CGFloat(weight), width: CGFloat(width))
        let a = CTFontGetAscent(font), d = CTFontGetDescent(font)
        let baseline = 1.3 * unit + (size - (a + d)) / 2 + a
        let x0 = 1.4 * unit
        let path = CGMutablePath()
        // Fast path: glyphs by character, positions from advances (no shaping, no kerning to lose).
        let chars = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        if CTFontGetGlyphsForCharacters(font, chars, &glyphs, chars.count) {
            var advances = [CGSize](repeating: .zero, count: glyphs.count)
            CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)
            var x = x0
            for i in glyphs.indices {
                var t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: x, ty: baseline)
                if let g = CTFontCreatePathForGlyph(font, glyphs[i], &t) { path.addPath(g) }
                x += advances[i].width
            }
            c.glyphs.path = path
            return
        }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let n = CTRunGetGlyphCount(run)
            guard n > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: n), pos = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: n), &pos)
            for i in 0..<n {
                var t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: x0 + pos[i].x, ty: baseline - pos[i].y)
                if let g = CTFontCreatePathForGlyph(font, glyphs[i], &t) { path.addPath(g) }
            }
        }
        c.glyphs.path = path
    }

    /// Frame for a CATextLayer so its first baseline sits where a CSS line box of `lineHeight`
    /// starting at `lineTop` would put it (half-leading split above and below).
    private func textBox(font: NSFont, lineTop: CGFloat, lineHeight: CGFloat) -> (y: CGFloat, h: CGFloat) {
        let a = font.ascender, d = -font.descender
        return (lineTop + (lineHeight - (a + d)) / 2, ceil(a + d + font.leading + 1))
    }

    private func attributed(_ s: String, font: NSFont, kern: CGFloat) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [
            .font: font, .kern: kern * font.pointSize,
            .foregroundColor: NSColor(cgColor: muted) ?? .gray,
        ])
    }

    // MARK: Palette

    /// `--muted`: ink at 45% (Night) / 50% (Paper).
    private var muted: CGColor { palette.ink(appearance == .dark ? 0.45 : 0.5) }
    /// `--rule`: ink at 14% (Night) / 16% (Paper).
    private var rule: CGColor { palette.ink(appearance == .dark ? 0.14 : 0.16) }

    private func applyPalette() {
        chrome.apply(palette, pureBlack: context.pureBlack && appearance == .dark)
        for l in rules { l.backgroundColor = rule }
        for c in cells {
            c.label.fillColor = muted
            c.fill = -1
            c.labelText = ""
        }
        if !bounds.isEmpty {
            title.string = attributed(SpecimenSheet.title, font: Fonts.label(size: max(1, 1.1 * unit)), kern: 0.22)
        }
        dateText = ""
        dateSecond = Int.min
    }
}

/// A single-line string drawn as one path from cached per-character glyph outlines, laid out by
/// advance plus tracking (`letter-spacing`), for short labels that change every frame. Characters
/// the font lacks fall back to a shaped line for that character.
struct GlyphStrip {
    let font: NSFont
    let kern: CGFloat                       // em
    private var cache: [Character: (path: CGPath?, advance: CGFloat)] = [:]

    init(font: NSFont, kern: CGFloat) { self.font = font; self.kern = kern }

    /// The path for `text` with its first baseline at `baseline` (y down), starting at x = 0.
    mutating func path(_ text: String, baseline: CGFloat) -> CGPath {
        let out = CGMutablePath()
        var x: CGFloat = 0
        let track = kern * font.pointSize
        for ch in text {
            let g = glyph(ch)
            if let p = g.path { out.addPath(p, transform: CGAffineTransform(translationX: x, y: baseline)) }
            x += g.advance + track
        }
        return out
    }

    private mutating func glyph(_ ch: Character) -> (path: CGPath?, advance: CGFloat) {
        if let hit = cache[ch] { return hit }
        let ct = font as CTFont
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(ch), attributes: [.font: font]))
        let path = CGMutablePath()
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let n = CTRunGetGlyphCount(run)
            guard n > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: n), pos = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: n), &pos)
            let attrs = CTRunGetAttributes(run) as NSDictionary
            let runFont: CTFont = attrs[kCTFontAttributeName].map { $0 as! CTFont } ?? ct
            for i in 0..<n {
                var t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: pos[i].x, ty: -pos[i].y)
                if let g = CTFontCreatePathForGlyph(runFont, glyphs[i], &t) { path.addPath(g) }
            }
        }
        let entry = (path: path.isEmpty ? nil : path as CGPath?, advance: CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
        cache[ch] = entry
        return entry
    }
}
