import AppKit
import QuartzCore

/// Poster layouts (PRD table, prototype `POSTER_LAYOUTS`), chosen by hour % 3.
enum PosterLayout {
    struct Text { let x: CGFloat, y: CGFloat, size: CGFloat, align: Align }
    enum Align { case left, right, center }
    struct Disc { let x: CGFloat, y: CGFloat, r: CGFloat }
    struct Caption { let x: CGFloat, y: CGFloat, align: Align, atTop: Bool }
    struct Spec { let hours: Text, minutes: Text, disc: Disc, caption: Caption }

    static let all: [Spec] = [
        Spec(hours: Text(x: -0.035, y: 0.79, size: 1.04, align: .left),
             minutes: Text(x: 1.03, y: 1.13, size: 1.04, align: .right),
             disc: Disc(x: 0.80, y: 0.27, r: 0.13),
             caption: Caption(x: 0.965, y: 0.05, align: .right, atTop: true)),
        Spec(hours: Text(x: 1.035, y: 0.74, size: 1.0, align: .right),
             minutes: Text(x: -0.03, y: 1.14, size: 1.06, align: .left),
             disc: Disc(x: 0.16, y: 0.22, r: 0.12),
             caption: Caption(x: 0.965, y: 0.94, align: .right, atTop: false)),
        Spec(hours: Text(x: 0.5, y: 0.60, size: 0.88, align: .center),
             minutes: Text(x: 0.5, y: 1.13, size: 0.88, align: .center),
             disc: Disc(x: 0.88, y: 0.52, r: 0.09),
             caption: Caption(x: 0.035, y: 0.94, align: .left, atTop: false)),
    ]

    static func index(forHour hour24: Int) -> Int { hour24 % 3 }

    /// Hours as shown on the poster: always two digits ("09" in 12h mode too, as in the prototype).
    static func hourText(_ t: ClockTime) -> String {
        String(format: "%02d", t.uses24Hour ? t.hour24 : t.displayHour)
    }
}

/// Poster: hours and minutes set enormous, cropped off the page, cutting through each other and
/// one accent disc. Ported from the prototype's `Poster`.
///
/// The canvas XOR composite becomes one even-odd fill: hours, minutes and disc go into a single
/// path, so a point covered by an odd number of shapes shows and an even number knocks out to the
/// background. Each number's outline is unioned first (`CGPath.normalized`) so overlapping
/// contours inside a glyph never punch holes. The accent layer is the same path masked to the
/// disc, so whatever survives inside the disc is accent.
final class PosterRenderer: ClockStyle {
    private struct State: Equatable { let hh: String, mm: String, layout: Int }

    private let context: StyleContext
    private var appearance: Appearance
    private var palette: R3Palette
    private let background = CAGradientLayer()
    private let grid = (0..<5).map { _ in CALayer() }
    private let ink = CAShapeLayer()
    private let accent = CAShapeLayer()
    private let accentMask = CAShapeLayer()
    private let captions = [CATextLayer(), CATextLayer()]
    private let secondsBar = CALayer()

    private var bounds = CGRect.zero, scale: CGFloat = 2
    private var current: State?
    private var previous: State?
    private var transitionStart: Double = 0
    private var hourChange = false
    private var pathCache: [String: (path: CGPath, width: CGFloat)] = [:]
    private var captionKey = ""
    private var speed: Double { max(context.timeScale, 0.01) }

    init(context: StyleContext) {
        self.context = context
        self.palette = .forAppearance(context.appearance)
        self.appearance = context.appearance
    }

    func start(in root: CALayer) {
        background.type = .radial
        root.addSublayer(background)
        for g in grid { root.addSublayer(g) }
        ink.fillRule = .evenOdd
        accent.fillRule = .evenOdd
        accent.mask = accentMask
        root.addSublayer(ink)
        root.addSublayer(accent)
        for c in captions { c.isWrapped = false; root.addSublayer(c) }
        root.addSublayer(secondsBar)
        applyPalette()
    }

    func layout(bounds: CGRect, scale: CGFloat) {
        self.bounds = bounds
        self.scale = scale
        background.frame = Room.frame(bounds)
        let r = 0.7 * max(bounds.width, bounds.height)
        background.startPoint = CGPoint(x: 0.5, y: 0.46)
        background.endPoint = CGPoint(x: 0.5 + r / max(bounds.width, 1), y: 0.46 + r / max(bounds.height, 1))
        for (i, g) in grid.enumerated() {
            g.frame = CGRect(x: bounds.width * CGFloat(i + 1) / 6, y: 0, width: 1 / scale, height: bounds.height)
        }
        for l in [ink, accent, accentMask] { l.frame = bounds; l.contentsScale = scale }
        for c in captions { c.contentsScale = scale }
        pathCache.removeAll()
        captionKey = ""
    }

    // MARK: Frame

    func render(time: ClockTime, frameTime: CFTimeInterval) {
        let T = frameTime / speed
        let next = State(hh: PosterLayout.hourText(time), mm: String(format: "%02d", time.minute),
                         layout: PosterLayout.index(forHour: time.hour24))
        if next != current {
            if let cur = current, !context.reduceMotion {
                previous = cur
                transitionStart = T
                hourChange = cur.hh != next.hh || cur.layout != next.layout
            }
            current = next
        }
        guard let cur = current else { return }

        let duration = hourChange ? 1.5 : 1.1
        let k = previous == nil ? 1 : min(max((T - transitionStart) / duration, 0), 1)
        let e = R3Easing.expoInOut(k)
        if previous != nil && k >= 1 { previous = nil }

        let W = bounds.width, H = bounds.height
        let drift: CGFloat = context.reduceMotion ? 0 : 1
        let dh = CGFloat(sin(T / 23)) * W * 0.008 * drift
        let dm = CGFloat(cos(T / 29)) * W * 0.008 * drift
        let dd = CGFloat(sin(T / 17)) * H * 0.02 * drift

        let combined = CGMutablePath()
        let discs = CGMutablePath()
        let LN = PosterLayout.all[cur.layout]

        if let old = previous, hourChange {
            let LO = PosterLayout.all[old.layout]
            add(old.hh, LO.hours, dx: dh - CGFloat(e) * W * 1.15, dy: 0, to: combined)
            add(old.mm, LO.minutes, dx: dm, dy: CGFloat(e) * H * 1.15, to: combined)
            addDisc(LO.disc, scale: 1 - e, dy: dd, to: combined, discs)
            add(cur.hh, LN.hours, dx: dh + CGFloat(1 - e) * W * 1.15, dy: 0, to: combined)
            add(cur.mm, LN.minutes, dx: dm, dy: CGFloat(1 - e) * H * 1.15, to: combined)
            addDisc(LN.disc, scale: R3Easing.backOut(min(max((k - 0.35) / 0.65, 0), 1)), dy: dd, to: combined, discs)
        } else {
            add(cur.hh, LN.hours, dx: dh, dy: 0, to: combined)
            if let old = previous {
                add(old.mm, LN.minutes, dx: dm, dy: -CGFloat(e) * H, to: combined)
                add(cur.mm, LN.minutes, dx: dm, dy: CGFloat(1 - e) * H, to: combined)
            } else {
                add(cur.mm, LN.minutes, dx: dm, dy: 0, to: combined)
            }
            addDisc(LN.disc, scale: 1, dy: dd, to: combined, discs)
        }
        ink.path = combined
        accent.path = combined
        accentMask.path = discs

        updateCaptions(time, layout: LN.caption, alpha: previous != nil && hourChange ? Float(e) : 1)

        // Accent seconds bar along the bottom edge.
        let barH = max(2, H * 0.004)
        let frac = (Double(time.second) + Double(time.millisecond) / 1000) / 60
        secondsBar.frame = CGRect(x: 0, y: H - barH, width: W * CGFloat(frac), height: barH)
    }

    /// Adds a number set in Anybody 800 condensed at `spec.size × H`, aligned on its baseline.
    private func add(_ text: String, _ spec: PosterLayout.Text, dx: CGFloat, dy: CGFloat, to path: CGMutablePath) {
        let H = bounds.height, W = bounds.width
        let (glyphs, width) = numberPath(text, size: spec.size * H)
        var x = spec.x * W + dx
        switch spec.align {
        case .left: break
        case .right: x -= width
        case .center: x -= width / 2
        }
        path.addPath(glyphs, transform: CGAffineTransform(translationX: x, y: spec.y * H + dy))
    }

    private func addDisc(_ d: PosterLayout.Disc, scale s: Double, dy: CGFloat, to path: CGMutablePath, _ discs: CGMutablePath) {
        guard s > 0.01 else { return }
        let H = bounds.height, W = bounds.width
        let r = d.r * H * CGFloat(s)
        let rect = CGRect(x: d.x * W - r, y: d.y * H + dy - r, width: 2 * r, height: 2 * r)
        path.addEllipse(in: rect)
        discs.addEllipse(in: rect)
    }

    /// The number's outline with its baseline at y = 0 (y down), overlaps unioned. Cached.
    private func numberPath(_ text: String, size: CGFloat) -> (CGPath, CGFloat) {
        let key = "\(text)@\(Int(size * 4))"
        if let hit = pathCache[key] { return hit }
        let font = Fonts.anybody(size: size, weight: 800, width: 75)   // fontStretch: condensed
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let path = CGMutablePath()
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let n = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: n), pos = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: n), &pos)
            for i in 0..<n {
                var t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: pos[i].x, ty: 0)
                if let g = CTFontCreatePathForGlyph(font, glyphs[i], &t) { path.addPath(g) }
            }
        }
        let union: CGPath
        if #available(macOS 13.0, *) { union = path.normalized(using: .winding) } else { union = path }
        let result = (union, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
        pathCache[key] = result
        return result
    }

    /// Two letter-spaced mono lines in the layout's free corner: weekday and date, then
    /// "QUIET HOURS / NO. hh" with AM/PM and optional seconds.
    private func updateCaptions(_ time: ClockTime, layout c: PosterLayout.Caption, alpha: Float) {
        for l in captions where l.opacity != alpha { l.opacity = alpha }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_GB")
        df.dateFormat = "EEEE"
        let day = df.string(from: time.date).uppercased()
        let dm = Calendar.current.dateComponents([.day, .month], from: time.date)
        var l2 = "QUIET HOURS  /  NO. " + PosterLayout.hourText(time)
        if let m = time.meridiem { l2 += " " + m }
        if context.showSeconds { l2 += "  /  " + String(time.secondDigits) }
        let l1 = day + "  " + String(format: "%02d.%02d", dm.day ?? 1, dm.month ?? 1)
        let key = l1 + "|" + l2 + "|\(c.x),\(c.y)"
        guard key != captionKey else { return }
        captionKey = key

        let W = bounds.width, H = bounds.height
        let fs = max(9, W * 0.0118)
        let spaced: (String) -> String = { $0.map(String.init).joined(separator: " ") }
        let lines = c.atTop ? [l1, l2] : [l1, l2]
        let lineH = fs * 1.4
        let x = c.x * W
        for (i, l) in captions.enumerated() {
            let s = NSMutableAttributedString(string: spaced(lines[i]), attributes: [
                .font: Fonts.label(size: fs),
                .foregroundColor: NSColor(cgColor: palette.label) ?? .gray,
            ])
            l.string = s
            l.alignmentMode = c.align == .left ? .left : (c.align == .right ? .right : .center)
            let width = W * 0.6
            let lx = c.align == .left ? x : (c.align == .right ? x - width : x - width / 2)
            // top: first line at y, second 1.9 em lower; bottom: second line ends at y, first 1.9 em above.
            let top = c.atTop ? c.y * H + CGFloat(i) * fs * 1.9
                              : c.y * H - lineH - CGFloat(1 - i) * fs * 1.9
            l.frame = CGRect(x: lx, y: top, width: width, height: lineH)
        }
    }

    // MARK: Appearance

    func appearanceDidChange(_ appearance: Appearance) {
        self.appearance = appearance
        palette = .forAppearance(appearance)
        applyPalette()
    }

    func stop() {
        for l in [background, ink, accent, secondsBar] as [CALayer] + grid + captions { l.removeFromSuperlayer() }
        pathCache.removeAll()
    }

    private func applyPalette() {
        background.colors = Room.colors(center: palette.roomCenter, edge: palette.roomEdge,
                                        appearance: appearance, pureBlack: context.pureBlack)
        for g in grid { g.backgroundColor = palette.ink(0.05) }
        ink.fillColor = palette.ink
        accent.fillColor = palette.accent
        accentMask.fillColor = CGColor(gray: 0, alpha: 1)
        secondsBar.backgroundColor = palette.accent
        captionKey = ""
    }
}
