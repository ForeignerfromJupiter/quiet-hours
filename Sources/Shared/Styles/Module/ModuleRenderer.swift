import AppKit
import QuartzCore

/// Module's digit patterns (PRD table, prototype `MOD_DIG`). Pure data, unit-tested.
enum ModuleGlyphs {
    /// A tile: scale (0 = empty) and per-corner radii as fractions of the tile size,
    /// in the order top-left, top-right, bottom-right, bottom-left.
    struct Tile: Equatable {
        var scale: Double
        var radii: [Double]
        static let empty = Tile(scale: 0, radii: [0, 0, 0, 0])
        /// Curve tiles are accent; the tint follows the largest corner radius during a morph.
        var curve: Double { radii.max() ?? 0 }
    }

    /// Rows top to bottom. `#` square, `.` empty, `a`/`b`/`c`/`d` rounded TL/TR/BR/BL.
    static let patterns: [Character: [String]] = [
        "0": ["a#b", "#.#", "#.#", "#.#", "d#c"],
        "1": ["a#.", ".#.", ".#.", ".#.", "###"],
        "2": ["a#b", "..#", "a#c", "#..", "###"],
        "3": ["##b", "..#", ".##", "..#", "##c"],
        "4": ["#.#", "#.#", "d##", "..#", "..#"],
        "5": ["###", "#..", "##b", "..#", "##c"],
        "6": ["a##", "#..", "##b", "#.#", "d#c"],
        "7": ["###", "..#", "..#", "..#", "..#"],
        "8": ["a#b", "#.#", "###", "#.#", "d#c"],
        "9": ["a#b", "#.#", "d##", "..#", "##c"],
    ]

    static func tile(_ code: Character) -> Tile {
        switch code {
        case "#": return Tile(scale: 1, radii: [0, 0, 0, 0])
        case "a": return Tile(scale: 1, radii: [1, 0, 0, 0])
        case "b": return Tile(scale: 1, radii: [0, 1, 0, 0])
        case "c": return Tile(scale: 1, radii: [0, 0, 1, 0])
        case "d": return Tile(scale: 1, radii: [0, 0, 0, 1])
        default: return .empty
        }
    }

    /// The 15 tiles of a digit, row-major. nil or unknown → all empty.
    static func tiles(for ch: Character?) -> [Tile] {
        guard let ch, let rows = patterns[ch] else { return Array(repeating: .empty, count: 15) }
        return rows.flatMap { $0.map(tile) }
    }
}

/// Module: numerals on a 3 × 5 grid of squares and quarter circles, Bauhaus style.
final class ModuleRenderer: ClockStyle {
    private struct TileAnim {
        var from = ModuleGlyphs.Tile.empty
        var to = ModuleGlyphs.Tile.empty
        var start: CFTimeInterval = -.infinity
    }
    private final class Slot {
        var ch: Character = " "
        var isSet = false
        var anims = Array(repeating: TileAnim(), count: 15)
        let layers = (0..<15).map { _ in CAShapeLayer() }
        var drawn = Array(repeating: ModuleGlyphs.Tile(scale: -1, radii: []), count: 15)
    }

    private static let morph = 0.82, stagger = 0.055

    private let context: StyleContext
    private var appearance: Appearance
    private var palette: R3Palette
    private let chrome = R3Chrome()
    private let slots = (0..<4).map { _ in Slot() }
    private let colon = [CALayer(), CALayer()]
    private let dashes = (0..<30).map { _ in CALayer() }
    private let gridY = CAReplicatorLayer(), gridX = CAReplicatorLayer(), dot = CALayer()

    private var bounds = CGRect.zero, scale: CGFloat = 2
    private var unit: CGFloat = 0
    private var visibleKey = ""
    /// 12h: whether the leading digit is showing, and its slot opening or closing.
    private var leadShown: Bool?
    private var leadChange: LeadingSlotChange?
    private var litDashes = -1
    private var animating = false
    private var speed: Double { max(context.timeScale, 0.01) }

    init(context: StyleContext) {
        self.context = context
        self.palette = .forAppearance(context.appearance)
        self.appearance = context.appearance
    }

    var wantsContinuousFrames: Bool { animating }

    func start(in root: CALayer) {
        chrome.install(in: root)
        gridX.addSublayer(dot)
        gridY.addSublayer(gridX)
        root.addSublayer(gridY)
        for s in slots { for l in s.layers { root.addSublayer(l) } }
        for c in colon { root.addSublayer(c) }
        for d in dashes { root.addSublayer(d) }
        root.addSublayer(chrome.label)
        applyPalette()
    }

    func layout(bounds: CGRect, scale: CGFloat) {
        self.bounds = bounds
        self.scale = scale
        chrome.layout(bounds: bounds, scale: scale)
        for s in slots { for l in s.layers { l.contentsScale = scale }; s.drawn = s.drawn.map { _ in .init(scale: -1, radii: []) } }
        visibleKey = ""
    }

    func render(time: ClockTime, frameTime t: CFTimeInterval) {
        let digits = time.digits
        let at = t / speed
        let lead = digits[0] != nil
        if lead != leadShown {
            if leadShown != nil, slots[0].isSet, !context.reduceMotion {
                // Longest morph: the bottom-right tile starts 6 staggers late.
                leadChange = LeadingSlotChange(start: at, opening: lead, settle: Self.morph + 6 * Self.stagger)
            }
            leadShown = lead
        }
        // While the leading slot opens, the digits wait for it.
        let delay = leadChange.map { max(0, $0.changeStart - at) * speed } ?? 0
        for (i, s) in slots.enumerated() {
            let ch = digits[i] ?? " "
            guard !s.isSet || ch != s.ch else { continue }
            let target = ModuleGlyphs.tiles(for: ch == " " ? nil : ch)
            for n in 0..<15 {
                let now = current(s.anims[n], t)
                s.anims[n].from = now
                s.anims[n].to = target[n]
                let (r, c) = (n / 3, n % 3)
                s.anims[n].start = (!s.isSet || context.reduceMotion) ? t - 10 : t + delay + Double(r + c) * Self.stagger * speed
            }
            s.ch = ch
            s.isSet = true
        }

        var lead0: CGFloat = lead ? 1 : 0
        if let change = leadChange {
            if change.isDone(at: at) { leadChange = nil } else { lead0 = CGFloat(change.presence(at: at)) }
        }
        let key = "\(lead0)"
        if key != visibleKey { visibleKey = key; place(leading: lead0) }

        animating = leadChange != nil
        for (i, s) in slots.enumerated() where i > 0 || lead0 > 0 {
            for n in 0..<15 {
                let a = s.anims[n]
                let tile = current(a, t)
                if t - a.start < Self.morph * speed { animating = true }
                if tile != s.drawn[n] { draw(s.layers[n], tile); s.drawn[n] = tile }
            }
        }

        // Seconds: 30 dashes fill with accent across the minute.
        let lit = Int(((Double(time.second) + Double(time.millisecond) / 1000) / 60 * 30).rounded())
        if lit != litDashes {
            litDashes = lit
            for (i, d) in dashes.enumerated() { d.backgroundColor = i < lit ? palette.accent : palette.ink(0.14) }
        }
        chrome.setLabel(R3Chrome.labelText(time, showSeconds: context.showSeconds))
        alignColonPulse(time)
    }

    private func current(_ a: TileAnim, _ t: CFTimeInterval) -> ModuleGlyphs.Tile {
        let k = min(max((t - a.start) / (Self.morph * speed), 0), 1)
        let s = context.reduceMotion ? 1 : R3Easing.backOut(k)
        let r = R3Easing.expoInOut(k)
        let radii = (0..<4).map { a.from.radii[$0] + (a.to.radii[$0] - a.from.radii[$0]) * r }
        return .init(scale: a.from.scale + (a.to.scale - a.from.scale) * s, radii: radii)
    }

    private func draw(_ layer: CAShapeLayer, _ tile: ModuleGlyphs.Tile) {
        guard tile.scale > 0.01 else { layer.isHidden = true; return }
        layer.isHidden = false
        let gap = unit * 0.05
        let side = (unit - gap) * CGFloat(tile.scale)
        let rect = CGRect(x: (layer.bounds.width - side) / 2, y: (layer.bounds.height - side) / 2, width: side, height: side)
        layer.path = Self.roundedRect(rect, radii: tile.radii.map { CGFloat($0) * side })
        layer.fillColor = palette.blend(tile.curve)
    }

    /// Lays out [H]H:MM: 3 tiles a digit, 0.7 between digits, 2.2 for the colon. `p` is how open
    /// the leading slot is (0…1); the row and its unit follow it, so the row glides.
    private func place(leading p: CGFloat) {
        let W = bounds.width, H = bounds.height
        let units = 3.7 * p + 11.9      // p = 1: 4 × 3 + 2 × 0.7 + 2.2; p = 0: 3 × 3 + 0.7 + 2.2
        unit = min(W * 0.82 / units, H * 0.6 / 5)
        let u = unit, gap = u * 0.05
        let left = (W - units * u) / 2
        let y = (H - 5 * u) / 2
        let lefts = [left - (1 - p) * 3.7 * u, left + p * 3.7 * u,
                     left + p * 3.7 * u + 5.2 * u, left + p * 3.7 * u + 8.9 * u]
        for (i, s) in slots.enumerated() {
            for (n, l) in s.layers.enumerated() {
                l.isHidden = i == 0 && p == 0
                l.frame = CGRect(x: lefts[i] + CGFloat(n % 3) * u, y: y + CGFloat(n / 3) * u, width: u, height: u)
            }
            s.drawn = s.drawn.map { _ in .init(scale: -1, radii: []) }
        }
        let cx = lefts[1] + 3 * u + 1.1 * u, r = (u - gap) * 0.42
        for (k, c) in colon.enumerated() {
            c.frame = CGRect(x: cx - r, y: y + CGFloat([1.5, 3.5][k]) * u - r, width: 2 * r, height: 2 * r)
            c.cornerRadius = r
        }

        let gx0 = left.truncatingRemainder(dividingBy: u) - u, gy0 = y - 2 * u
        dot.frame = CGRect(x: gx0 - 1, y: gy0 - 1, width: 2, height: 2)
        gridX.instanceCount = Int(ceil((W - gx0) / u)) + 1
        gridX.instanceTransform = CATransform3DMakeTranslation(u, 0, 0)
        gridY.instanceCount = Int(ceil((H - gy0) / u)) + 1
        gridY.instanceTransform = CATransform3DMakeTranslation(0, u, 0)
        gridX.frame = bounds; gridY.frame = bounds

        // Seconds dashes under the digits.
        let sy = y + 5 * u + 0.9 * u, sx0 = W / 2 - 15 * u * 0.32
        for (i, d) in dashes.enumerated() {
            d.frame = CGRect(x: sx0 + CGFloat(i) * u * 0.32, y: sy, width: u * 0.22, height: u * 0.08)
        }
    }

    /// Colon discs pulse to 85% every half second, in step with the clock: a render-server
    /// animation, so the view can sleep between morphs.
    private var colonPhase: Int?
    private func alignColonPulse(_ time: ClockTime) {
        guard !context.reduceMotion else { return }
        let phase = time.millisecond / 50
        guard colonPhase == nil || time.second == 0 && phase == 0 else { return }
        colonPhase = phase
        let a = CAKeyframeAnimation(keyPath: "transform.scale")
        a.values = [1.0, 0.85]
        a.keyTimes = [0, 0.5]
        a.calculationMode = .discrete
        a.duration = 1
        a.repeatCount = .infinity
        a.beginTime = CACurrentMediaTime() - Double(time.millisecond) / 1000
        for c in colon { c.add(a, forKey: "pulse") }
    }

    func appearanceDidChange(_ appearance: Appearance) {
        self.appearance = appearance
        palette = .forAppearance(appearance)
        applyPalette()
        for s in slots { s.drawn = s.drawn.map { _ in .init(scale: -1, radii: []) } }
        litDashes = -1
    }

    func stop() {
        chrome.remove()
        gridY.removeFromSuperlayer()
        for s in slots { for l in s.layers { l.removeFromSuperlayer() } }
        for c in colon { c.removeAllAnimations(); c.removeFromSuperlayer() }
        for d in dashes { d.removeFromSuperlayer() }
    }

    private func applyPalette() {
        chrome.apply(palette, pureBlack: context.pureBlack && appearance == .dark)
        dot.backgroundColor = palette.ink(0.07)
        for c in colon { c.backgroundColor = palette.accent }
    }

    /// Rectangle with independent corner radii (TL, TR, BR, BL) in a y-down space.
    static func roundedRect(_ r: CGRect, radii: [CGFloat]) -> CGPath {
        let m = min(r.width, r.height)
        let (tl, tr, br, bl) = (min(radii[0], m), min(radii[1], m), min(radii[2], m), min(radii[3], m))
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.minX + tl, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY))
        if tr > 0 { p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + tr), radius: tr) }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
        if br > 0 { p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - br, y: r.maxY), radius: br) }
        p.addLine(to: CGPoint(x: r.minX + bl, y: r.maxY))
        if bl > 0 { p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - bl), radius: bl) }
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + tl))
        if tl > 0 { p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + tl, y: r.minY), radius: tl) }
        p.closeSubpath()
        return p
    }
}
