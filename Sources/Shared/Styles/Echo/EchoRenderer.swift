import AppKit
import QuartzCore

/// Echo's numbers and schedules (prototype `Echo`), kept pure so they can be unit-tested.
enum EchoModel {
    /// One solid numeral in front (layer 0) and six accent outlines behind it (`NL = 7`).
    static let layers = 7
    /// Each layer swaps 70 ms after the one in front of it; each changing slot starts 110 ms after
    /// the previous one; a swap takes 420 ms (`t0 = t + L*70 + order*110`, `/420`).
    static let layerDelay = 0.070, slotDelay = 0.110, swapDuration = 0.420
    /// Offset per layer (`S*.024`), outline stroke (`S*.007`, at least 1 pt) and the swap's
    /// vertical travel (`S*.35`), all as fractions of the numeral size S.
    static let offsetPerLayer: CGFloat = 0.024, stroke: CGFloat = 0.007, travel: CGFloat = 0.35

    /// The five slots the prototype draws (`timeSlots`): HH:MM, with " " for the hidden 12h
    /// leading digit.
    static func slots(_ t: ClockTime) -> [Character] {
        let d = t.digits.map { $0 ?? " " }
        return [d[0], d[1], ":", d[2], d[3]]
    }

    /// Advance of a slot in units of S (`wOf`): the colon is narrow.
    static func width(of c: Character) -> CGFloat { c == ":" ? 0.32 : 0.66 }

    /// Numeral size: up to 52% of the height or 80% of the width for the visible slots.
    static func numeralSize(visible: [Character], in size: CGSize) -> CGFloat {
        numeralSize(units: visible.reduce(0) { $0 + width(of: $1) }, in: size)
    }

    /// The same for a row `units` wide (in units of S), which is fractional during a glide.
    static func numeralSize(units: CGFloat, in size: CGSize) -> CGFloat {
        min(size.height * 0.52, size.width * 0.8 / max(units, 0.01))
    }

    /// The longest minute change: the back layer of the fourth changing slot (12:59 → 1:00
    /// changes four), in seconds.
    static let longestChange = Double(layers - 1) * layerDelay + 3 * slotDelay + swapDuration

    /// Direction of the echo offset (radians, y down): 135° at the top of the minute, turning
    /// once a minute (`PI*.75 - ((s+ms/1000)/60)*TAU`). Reduced motion holds it at 45°.
    static func orbitAngle(second: Int, millisecond: Int, reduceMotion: Bool) -> Double {
        if reduceMotion { return .pi * 0.25 }
        return .pi * 0.75 - (Double(second) + Double(millisecond) / 1000) / 60 * 2 * .pi
    }

    /// Opacity of a depth layer: the solid front is opaque, outlines fade to the back
    /// (`(1-L/8)*.95`).
    static func layerOpacity(_ layer: Int) -> Double {
        layer == 0 ? 1 : (1 - Double(layer) / 8) * 0.95
    }

    /// When layer `layer` of the `order`-th changing slot starts its swap (seconds).
    static func swapStart(now: Double, layer: Int, order: Int) -> Double {
        now + Double(layer) * layerDelay + Double(order) * slotDelay
    }

    /// For each slot, its position among the slots that change (left to right), or nil if it
    /// keeps its character. Slots that turn blank still count, as in the prototype.
    static func changeOrders(from old: [Character], to new: [Character]) -> [Int?] {
        var order = 0
        return zip(old, new).map { o, n in
            guard o != n else { return nil }
            defer { order += 1 }
            return order
        }
    }

    /// A swap at linear progress `k`: the old character slides up and fades out while the new one
    /// rises from below and fades in, exponential in-out. Offsets are in units of S.
    struct Swap: Equatable { let oldAlpha: Double, oldDY: Double, newAlpha: Double, newDY: Double }
    static func swap(at k: Double) -> Swap {
        let e = R3Easing.expoInOut(min(max(k, 0), 1))
        return Swap(oldAlpha: 1 - e, oldDY: -e * Double(travel), newAlpha: e, newDY: (1 - e) * Double(travel))
    }
}

/// Echo: big numerals with six outline echoes stacked behind them. Ported from the prototype's
/// `Echo`.
///
/// Every character of every depth layer is a CAShapeLayer holding a cached glyph path (filled
/// ink in front, stroked accent behind), plus a second one for the character swapping out. The
/// orbit moves seven depth containers; a swap moves and fades individual glyph layers. Per frame
/// only positions and opacities change; paths are set only when a character or the size changes.
final class EchoRenderer: ClockStyle {
    /// One character slot in one depth layer: the current glyph and the one swapping out.
    private final class Cell {
        let cur = CAShapeLayer()
        let old = CAShapeLayer()
        var oldCh: Character?        // swapping out; nil at rest
        var start: Double = 0        // swap start (animation seconds), includes both delays
        var curShown: (Character, Int)?, oldShown: (Character, Int)?
    }

    private final class Slot {
        var ch: Character = " "
        var isSet = false
        var center = CGPoint.zero
        var visible = false
        let cells = (0..<EchoModel.layers).map { _ in Cell() }
    }

    private let context: StyleContext
    private var appearance: Appearance
    private var palette: R3Palette
    private let chrome = R3Chrome()
    /// Depth containers, `depth[0]` in front. Each is moved by the orbit as a whole.
    private let depth = (0..<EchoModel.layers).map { _ in CALayer() }
    private let slots = (0..<5).map { _ in Slot() }

    private var bounds = CGRect.zero, scale: CGFloat = 2
    private var size: CGFloat = 0           // numeral size the glyph paths are built at
    private var drawSize: CGFloat = 0       // numeral size on screen (differs during a glide)
    private var glyphScale: CGFloat = 1
    /// 12h: whether the leading digit is showing, and its slot opening or closing.
    private var leadShown: Bool?
    private var leadChange: LeadingSlotChange?
    private var layoutKey = ""
    private var paths: [Character: CGPath] = [:]
    private var pathGeneration = 0          // bumps when the cache is dropped (size change)
    private var speed: Double { max(context.timeScale, 0.01) }

    init(context: StyleContext) {
        self.context = context
        self.palette = .forAppearance(context.appearance)
        self.appearance = context.appearance
    }

    /// The orbit never rests; with reduced motion nothing moves between minutes.
    var wantsContinuousFrames: Bool { !context.reduceMotion }

    func start(in root: CALayer) {
        chrome.install(in: root)
        // Back to front, and within a layer old before new, as the prototype paints.
        for L in stride(from: EchoModel.layers - 1, through: 0, by: -1) {
            let d = depth[L]
            d.bounds = .zero
            root.addSublayer(d)
            for s in slots {
                for l in [s.cells[L].old, s.cells[L].cur] {
                    l.bounds = .zero
                    l.isHidden = true
                    d.addSublayer(l)
                }
            }
        }
        root.addSublayer(chrome.label)
        applyPalette()
    }

    func layout(bounds: CGRect, scale: CGFloat) {
        self.bounds = bounds
        self.scale = scale
        chrome.layout(bounds: bounds, scale: scale)
        for s in slots { for c in s.cells { for l in [c.cur, c.old] { l.contentsScale = scale } } }
        layoutKey = ""
        dropPaths()
    }

    // MARK: Frame

    func render(time: ClockTime, frameTime: CFTimeInterval) {
        let T = frameTime / speed
        let reduce = context.reduceMotion
        let chars = EchoModel.slots(time)

        let lead = chars[0] != " "
        if lead != leadShown {
            if leadShown != nil, slots[0].isSet, !reduce {
                leadChange = LeadingSlotChange(start: T, opening: lead, settle: EchoModel.longestChange)
            }
            leadShown = lead
        }
        // While the leading slot opens, the swaps wait for it.
        let delay = leadChange.map { max(0, $0.changeStart - T) } ?? 0
        let orders = EchoModel.changeOrders(from: slots.map(\.ch), to: chars)
        for (i, s) in slots.enumerated() where !s.isSet || chars[i] != s.ch {
            if s.isSet && !reduce, let order = orders[i] {
                for (L, c) in s.cells.enumerated() {
                    c.oldCh = s.ch
                    c.start = EchoModel.swapStart(now: T + delay, layer: L, order: order)
                }
            }
            s.ch = chars[i]
            s.isSet = true
        }

        var p: CGFloat = lead ? 1 : 0
        if let change = leadChange {
            if change.isDone(at: T) { leadChange = nil } else { p = CGFloat(change.presence(at: T)) }
        }
        let key = chars.map(String.init).joined() + "|\(p)"
        if key != layoutKey { layoutKey = key; place(leading: p) }
        let S = drawSize

        // Orbit: the stack is centred, so the front layer moves too (`- ox*(NL-1)/2`).
        let a = EchoModel.orbitAngle(second: time.second, millisecond: time.millisecond, reduceMotion: reduce)
        let off = S * EchoModel.offsetPerLayer
        let ox = CGFloat(cos(a)) * off, oy = CGFloat(sin(a)) * off
        let mid = CGFloat(EchoModel.layers - 1) / 2
        for (L, d) in depth.enumerated() {
            d.position = CGPoint(x: ox * (CGFloat(L) - mid), y: oy * (CGFloat(L) - mid))
        }

        for s in slots where s.visible {
            for (L, c) in s.cells.enumerated() {
                let base = EchoModel.layerOpacity(L)
                if let o = c.oldCh {
                    let k = (T - c.start) / EchoModel.swapDuration
                    if k < 1 {
                        let w = EchoModel.swap(at: k)
                        show(c.old, o, &c.oldShown, dy: CGFloat(w.oldDY) * S, alpha: w.oldAlpha * base, at: s.center)
                        show(c.cur, s.ch, &c.curShown, dy: CGFloat(w.newDY) * S, alpha: w.newAlpha * base, at: s.center)
                        continue
                    }
                    c.oldCh = nil
                }
                show(c.cur, s.ch, &c.curShown, dy: 0, alpha: base, at: s.center)
                show(c.old, " ", &c.oldShown, dy: 0, alpha: 0, at: s.center)
            }
        }

        chrome.setLabel(R3Chrome.labelText(time, showSeconds: context.showSeconds))
    }

    /// Shows `ch` on `l` at the slot centre plus `dy`, touching only what changed.
    private func show(_ l: CAShapeLayer, _ ch: Character, _ shown: inout (Character, Int)?,
                      dy: CGFloat, alpha: Double, at center: CGPoint) {
        guard ch != " ", alpha > 0 else {
            if !l.isHidden { l.isHidden = true }
            return
        }
        if shown?.0 != ch || shown?.1 != pathGeneration {
            l.path = glyph(ch)
            shown = (ch, pathGeneration)
        }
        let p = CGPoint(x: center.x, y: center.y + dy)
        if l.position != p { l.position = p }
        let o = Float(alpha)
        if l.opacity != o { l.opacity = o }
        if l.isHidden { l.isHidden = false }
    }

    // MARK: Layout

    /// Sizes the numerals for the slots on show and finds each slot's centre at rest. `p` is how
    /// open the 12h leading slot is (0…1): it narrows as it closes and the rest re-centre, so the
    /// row glides. During a glide the paths stay at the larger size and the layers scale.
    private func place(leading p: CGFloat) {
        let W = bounds.width, H = bounds.height
        let widths = slots.enumerated().map { i, s in
            i == 0 ? p * EchoModel.width(of: "0") : EchoModel.width(of: s.ch)
        }
        let units = widths.reduce(0, +)
        let S = EchoModel.numeralSize(units: units, in: bounds.size)
        var pathSize = S
        if leadChange != nil {
            let rest = units - widths[0]
            pathSize = max(EchoModel.numeralSize(units: rest, in: bounds.size),
                           EchoModel.numeralSize(units: rest + EchoModel.width(of: "0"), in: bounds.size))
        }
        if abs(pathSize - size) > 0.25 { size = pathSize; dropPaths() }
        drawSize = S
        let k = size > 0 ? S / size : 1
        if k != glyphScale {
            glyphScale = k
            let t = k == 1 ? CATransform3DIdentity : CATransform3DMakeScale(k, k, 1)
            for s in slots { for c in s.cells { c.cur.transform = t; c.old.transform = t } }
        }
        var x = (W - units * S) / 2
        let cy = H / 2 + S * 0.03
        for (i, s) in slots.enumerated() {
            s.visible = s.ch != " " || (i == 0 && p > 0)
            if s.visible {
                let w = widths[i] * S
                // A closing leading slot keeps its glyph width and slides out to the left.
                s.center = CGPoint(x: i == 0 ? x + (p - 0.5) * EchoModel.width(of: "0") * S : x + w / 2, y: cy)
                x += w
            } else {
                for c in s.cells { c.oldCh = nil; for l in [c.cur, c.old] where !l.isHidden { l.isHidden = true } }
            }
        }
        let line = max(1, size * EchoModel.stroke)
        for s in slots { for c in s.cells.dropFirst() { c.cur.lineWidth = line; c.old.lineWidth = line } }
    }

    private func dropPaths() {
        paths.removeAll()
        pathGeneration += 1
    }

    /// The character in Anybody 800 semi-condensed at S, centred on its advance (`textAlign
    /// center`) with the em box's middle at y = 0 (`textBaseline middle`), y down.
    private func glyph(_ ch: Character) -> CGPath? {
        if let p = paths[ch] { return p }
        guard size > 0, let scalar = ch.unicodeScalars.first else { return nil }
        let font = Fonts.anybody(size: size, weight: 800, width: 87.5)   // fontStretch: semi-condensed
        var u = UniChar(scalar.value), g: CGGlyph = 0, adv = CGSize.zero
        guard CTFontGetGlyphsForCharacters(font, &u, &g, 1) else { return nil }
        CTFontGetAdvancesForGlyphs(font, .horizontal, &g, &adv, 1)
        let a = CTFontGetAscent(font), d = CTFontGetDescent(font)
        var t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: -adv.width / 2, ty: (a - d) / 2)
        guard let raw = CTFontCreatePathForGlyph(font, g, &t) else { return nil }
        // Union overlapping contours so the outline echoes don't show seams inside a glyph.
        let path: CGPath
        if #available(macOS 13.0, *) { path = raw.normalized(using: .winding) } else { path = raw }
        paths[ch] = path
        return path
    }

    // MARK: Appearance

    func appearanceDidChange(_ appearance: Appearance) {
        self.appearance = appearance
        palette = .forAppearance(appearance)
        applyPalette()
    }

    func stop() {
        chrome.remove()
        for d in depth { d.removeFromSuperlayer() }
        paths.removeAll()
    }

    private func applyPalette() {
        chrome.apply(palette, pureBlack: context.pureBlack && appearance == .dark)
        for s in slots {
            for (L, c) in s.cells.enumerated() {
                for l in [c.cur, c.old] {
                    if L == 0 {
                        l.fillColor = palette.ink
                        l.strokeColor = nil
                    } else {
                        l.fillColor = nil
                        l.strokeColor = palette.accent
                    }
                }
            }
        }
    }
}
