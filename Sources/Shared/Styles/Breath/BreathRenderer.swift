import AppKit
import QuartzCore

/// Breath: one large set of numerals whose weight is the clock.
/// Ported from the prototype's `Breath` (units: 1 u = 1% of screen width, height-capped).
final class BreathRenderer: ClockStyle {
    private struct Palette {
        let roomCenter, roomEdge, ink, muted, tick: CGColor
        /// Prototype: --bgA #16161a, --bgB #08080a, --tick #2b2b30 (deepened: room edge to true black).
        static let graphite = Palette(roomCenter: srgb(0x0e0e11), roomEdge: srgb(0x000000),
                                      ink: srgb(0xf2eee6), muted: srgb(0x6f6d68), tick: srgb(0x232327))
        static let paper = Palette(roomCenter: srgb(0xf2efe8), roomEdge: srgb(0xe2ddd2),
                                   ink: srgb(0x151515), muted: srgb(0x8e887d), tick: srgb(0xcdc6b8))
    }

    /// A digit's squeeze → swap → spring animation (prototype `set()` / `_a`).
    private struct DigitAnim {
        var start: CFTimeInterval
        var newValue: Character?
        var swapped = false
    }

    private let context: StyleContext
    private var palette: Palette
    private let background = CAGradientLayer()
    private let digitLayers = (0..<4).map { _ in CAShapeLayer() }
    private let dots = (0..<2).map { _ in CALayer() }
    private let ticks = (0..<60).map { _ in CALayer() }
    private let meta = CATextLayer()

    private var bounds = CGRect.zero
    private var scale: CGFloat = 2
    private var unit: CGFloat = 1
    private var shown: [Character?] = [nil, nil, nil, nil]   // what each slot currently draws
    private var target: [Character?]?                       // last digits from the clock
    private var anims: [DigitAnim?] = [nil, nil, nil, nil]
    private var weight: Double?
    private var lastFrame: CFTimeInterval?
    private var litTicks = -1
    private var metaText = ""

    // Prototype constants
    private static let fontSize: CGFloat = 28          // cqw
    private static let lineHeight: CGFloat = 0.8       // em
    private static let squeeze = 0.23, spring = 0.90   // seconds
    private static let restWidth = 92.0

    init(context: StyleContext) {
        self.context = context
        self.palette = context.appearance == .dark ? .graphite : .paper
    }

    func start(in root: CALayer) {
        // radial-gradient(ellipse 80% 70% at 50% 45%, --bgA, --bgB)
        background.type = .radial
        background.startPoint = CGPoint(x: 0.5, y: 0.45)
        background.endPoint = CGPoint(x: 1.3, y: 1.15)
        root.addSublayer(background)
        for l in digitLayers { root.addSublayer(l) }
        for d in dots { root.addSublayer(d) }
        for t in ticks { root.addSublayer(t) }
        meta.alignmentMode = .center
        root.addSublayer(meta)
        applyPalette()
    }

    func layout(bounds: CGRect, scale: CGFloat) {
        self.bounds = bounds
        self.scale = scale
        // Block: time .8em·28 + 2.6 + scale 2.2 + 2.6 + meta 1.6 = 31.4 u tall, ~80 u wide.
        unit = max(0.5, min(bounds.width / 100, 0.66 * bounds.height / 31.4, 0.94 * bounds.width / 82))
        background.frame = bounds
        for l in allLayers { l.contentsScale = scale }

        let top = (bounds.height - 31.4 * unit) / 2
        // Scale row: 60 ticks, .22 wide, .42 gap, 1.1 / 1.8 tall, bottom-aligned in 2.2.
        let scaleTop = top + 22.4 * unit + 2.6 * unit
        let tickW = 0.22 * unit, gap = 0.42 * unit
        let total = 60 * tickW + 59 * gap
        var x = (bounds.width - total) / 2
        for (i, t) in ticks.enumerated() {
            let h = (i % 5 == 0 ? 1.8 : 1.1) * unit
            t.frame = CGRect(x: x, y: scaleTop + 2.2 * unit - h, width: tickW, height: h)
            t.cornerRadius = 0.1 * unit
            x += tickW + gap
        }
        meta.frame = CGRect(x: 0, y: scaleTop + 2.2 * unit + 2.6 * unit, width: bounds.width, height: 2.2 * unit)
        updateMeta(force: true)
    }

    func render(time: ClockTime, frameTime t: CFTimeInterval) {
        let reduce = context.reduceMotion
        let first = target == nil
        let speed = max(context.timeScale, 0.01)

        // Weight fill: 110 → 900 across the minute, eased with a 220 ms time constant.
        let f = (Double(time.second) * 1000 + Double(time.millisecond)) / 60000
        let goal = 110 + 790 * f
        let dt = min(0.064, t - (lastFrame ?? t))
        lastFrame = t
        if let w = weight, !reduce { weight = w + (goal - w) * min(1, dt / (0.22 * speed)) } else { weight = goal }
        let wg = weight ?? goal

        // Digit changes
        let digits = time.digits
        for i in 0..<4 where target?[i] != digits[i] {
            if first || reduce { shown[i] = digits[i]; anims[i] = nil }
            else { anims[i] = DigitAnim(start: t, newValue: digits[i]) }
        }
        target = digits

        // Per-digit variation, opacity, advance
        let fs = Self.fontSize * unit
        var fonts: [CTFont?] = []
        var opacities: [Float] = []
        for i in 0..<4 {
            var wd = Self.restWidth, op = 1.0
            if var a = anims[i] {
                let e = (t - a.start) / speed
                if e < Self.squeeze {
                    let k = pow(e / Self.squeeze, 2)
                    wd = 92 - 42 * k; op = 1 - 0.92 * k
                } else {
                    if !a.swapped { shown[i] = a.newValue; a.swapped = true }
                    let k = min(max((e - Self.squeeze) / Self.spring, 0), 1)
                    wd = 50 + 42 * Self.backOut(k); op = min(1, 0.08 + k * 3)
                    anims[i] = k >= 1 ? nil : a
                }
                if anims[i] != nil { anims[i] = a }
            }
            let br = reduce ? 0 : sin(t * 1000 / 900 / speed - Double(i) * 0.32)
            let w = min(max(wg + 80 * br, 100), 900)
            fonts.append(shown[i] == nil ? nil : Fonts.anybody(size: fs, weight: CGFloat(w), width: CGFloat(wd + 5 * br)))
            opacities.append(Float(op))
        }

        // Lay out the row: [d][d] colon [d][d], centered, line box .8em, items vertically centered.
        let cd = (0.075 + 0.07 * ((wg - 110) / 790)) * Double(fs)       // dot diameter
        let cg = 0.13 * fs, colonMargin = 0.05 * fs, colonPad = 0.04 * fs
        var glyphs: [(CGGlyph, CGFloat)?] = []
        for i in 0..<4 {
            guard let font = fonts[i], let ch = shown[i] else { glyphs.append(nil); continue }
            var u = UniChar(ch.unicodeScalars.first!.value), g: CGGlyph = 0, adv = CGSize.zero
            CTFontGetGlyphsForCharacters(font, &u, &g, 1)
            CTFontGetAdvancesForGlyphs(font, .horizontal, &g, &adv, 1)
            glyphs.append((g, adv.width))
        }
        let colonW = CGFloat(cd) + 2 * colonMargin
        let rowW = glyphs.reduce(0) { $0 + ($1?.1 ?? 0) } + colonW
        let lineBox = Self.lineHeight * fs
        let rowTop = (bounds.height - 31.4 * unit) / 2
        var x = (bounds.width - rowW) / 2
        for i in 0..<4 {
            if i == 2 {
                let colonH = 2 * CGFloat(cd) + cg + colonPad
                let cy = rowTop + (lineBox - colonH) / 2 + colonPad
                for (j, d) in dots.enumerated() {
                    d.frame = CGRect(x: x + colonMargin, y: cy + CGFloat(j) * (CGFloat(cd) + cg), width: CGFloat(cd), height: CGFloat(cd))
                    d.cornerRadius = CGFloat(cd) / 2
                }
                x += colonW
            }
            let layer = digitLayers[i]
            guard let (g, adv) = glyphs[i], let font = fonts[i] else { layer.path = nil; continue }
            let a = CTFontGetAscent(font), d = CTFontGetDescent(font)
            let baseline = rowTop + (lineBox - (a + d)) / 2 + a
            var tr = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: x, ty: baseline)
            layer.path = CTFontCreatePathForGlyph(font, g, &tr)
            layer.opacity = opacities[i]
            x += adv
        }
        let pulse = reduce ? 1 : 0.35 + 0.65 * (0.5 + 0.5 * cos(Double(time.millisecond) / 1000 * 2 * .pi))
        for d in dots { d.opacity = Float(pulse) }

        // Scale ticks fill as seconds pass (0.4 s color transition, as in the CSS).
        if time.second != litTicks {
            litTicks = time.second
            CATransaction.begin()
            CATransaction.setDisableActions(reduce)
            CATransaction.setAnimationDuration(0.4)
            for (j, tk) in ticks.enumerated() { tk.backgroundColor = j <= time.second ? palette.ink : palette.tick }
            CATransaction.commit()
        }

        let text = [context.showSeconds ? String(time.secondDigits) : nil, time.meridiem].compactMap { $0 }.joined(separator: "   ")
        if text != metaText { metaText = text; updateMeta(force: true) }
    }

    func appearanceDidChange(_ appearance: Appearance) {
        palette = appearance == .dark ? .graphite : .paper
        applyPalette()
    }

    func stop() {
        for l in allLayers { l.removeFromSuperlayer() }
    }

    private var allLayers: [CALayer] {
        [background, meta] + digitLayers.map { $0 as CALayer } + dots + ticks
    }

    private func applyPalette() {
        background.colors = [palette.roomCenter, palette.roomEdge]
        for l in digitLayers { l.fillColor = palette.ink }
        for d in dots { d.backgroundColor = palette.ink }
        for (j, tk) in ticks.enumerated() { tk.backgroundColor = j <= litTicks ? palette.ink : palette.tick }
        updateMeta(force: true)
    }

    private func updateMeta(force: Bool) {
        let size = 1.4 * unit
        meta.string = NSAttributedString(string: metaText, attributes: [
            .font: Fonts.label(size: size), .kern: 0.24 * size,
            .foregroundColor: NSColor(cgColor: palette.muted) ?? .gray,
        ])
    }

    /// Prototype `back(k)`: ease-out-back with c1 = 3.2.
    static func backOut(_ k: Double) -> Double {
        let c1 = 3.2, c3 = c1 + 1
        return 1 + c3 * pow(k - 1, 3) + c1 * pow(k - 1, 2)
    }
}
