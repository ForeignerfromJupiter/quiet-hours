import AppKit
import QuartzCore

/// Slice: heavy numerals cut into 14 horizontal ribbons. Ported from the prototype's `Slice`.
/// Each digit is rendered once per change into a cached image (ink and accent); every ribbon is
/// a clipped layer showing a slice of those images, so it can sway, slant and smear on its own.
final class SliceRenderer: ClockStyle {
    static let ribbons = 14
    private static let duration = 0.76, ribbonStagger = 0.034, digitStagger = 0.13

    /// One ribbon: a clip, a skew layer (slant pivots on the ribbon's centre) and the images.
    private final class Ribbon {
        let clip = CALayer()
        let skew = CALayer()
        let old = CALayer()
        let ghosts = (0..<4).map { _ in CALayer() }
        let new = CALayer()
        let accent = CALayer()
        init() {
            clip.masksToBounds = true
            clip.addSublayer(skew)
            for l in [old] + ghosts + [new, accent] {
                l.anchorPoint = .zero
                skew.addSublayer(l)
            }
            skew.anchorPoint = .zero
        }
        var images: [CALayer] { [old] + ghosts + [new, accent] }
    }

    private final class Slot {
        var ch: Character = " "
        var old: Character?
        var start: Double = 0     // animation time (s), already includes the digit stagger
        var isSet = false
        let ribbons = (0..<SliceRenderer.ribbons).map { _ in Ribbon() }
        var x: CGFloat = 0
        var visible = false
    }

    private let context: StyleContext
    private var appearance: Appearance
    private var palette: R3Palette
    private let chrome = R3Chrome()
    private let slots = (0..<4).map { _ in Slot() }
    private let colon = (0..<6).map { _ in CALayer() }

    private var bounds = CGRect.zero, scale: CGFloat = 2
    private var size: CGFloat = 0          // numeral size S
    private var top: CGFloat = 0
    private var layoutKey = ""
    /// A digit image cropped to its ink, and where that crop sits in the 0.72 S × 1.02 S cell.
    private struct Glyph { let image: CGImage; let rect: CGRect }
    /// Only the digits on screen are kept (pruned after every change), so memory stays at a
    /// handful of cropped images instead of every digit ever shown.
    private var cache: [String: Glyph] = [:]
    private var usedThisFrame = Set<String>()
    private var speed: Double { max(context.timeScale, 0.01) }

    init(context: StyleContext) {
        self.context = context
        self.palette = .forAppearance(context.appearance)
        self.appearance = context.appearance
    }

    func start(in root: CALayer) {
        chrome.install(in: root)
        for s in slots { for r in s.ribbons { root.addSublayer(r.clip) } }
        for c in colon { root.addSublayer(c) }
        root.addSublayer(chrome.label)
        applyPalette()
    }

    func layout(bounds: CGRect, scale: CGFloat) {
        self.bounds = bounds
        self.scale = scale
        chrome.layout(bounds: bounds, scale: scale)
        layoutKey = ""
        cache.removeAll()
    }

    // MARK: Frame

    func render(time: ClockTime, frameTime: CFTimeInterval) {
        let T = frameTime / speed
        let reduce = context.reduceMotion
        let digits = time.digits

        var order = 0
        for (i, s) in slots.enumerated() {
            let ch = digits[i] ?? " "
            guard !s.isSet || ch != s.ch else { continue }
            if s.isSet && !reduce { s.old = s.ch; s.start = T + Double(order) * Self.digitStagger; order += 1 }
            s.ch = ch
            s.isSet = true
        }

        let mid = Double(Self.ribbons - 1) / 2
        let animEnd = Self.duration + mid * Self.ribbonStagger + 0.02
        for s in slots where s.old != nil && T > s.start + animEnd { s.old = nil }

        let visible = slots.indices.filter { slots[$0].ch != " " || (slots[$0].old.map { $0 != " " } ?? false) }
        let key = visible.map(String.init).joined()
        if key != layoutKey { layoutKey = key; place(visible) }

        let S = size, w = S * 0.72, h = S * 1.02, bh = h / CGFloat(Self.ribbons)
        let scanF = (Double(time.second) + Double(time.millisecond) / 1000) / 60 * Double(Self.ribbons)
        let scanB = Int(scanF.rounded(.down))
        let bump = sin((scanF - Double(scanB)) * .pi)

        usedThisFrame.removeAll(keepingCapacity: true)
        for (j, i) in visible.enumerated() {
            let s = slots[i]
            let ink = glyph(s.ch, accent: false), acc = glyph(s.ch, accent: true)
            let oldImg = s.old.flatMap { glyph($0, accent: false) }
            let anim = oldImg != nil && T <= s.start + animEnd   // a blank old digit just appears
            for (b, r) in s.ribbons.enumerated() {
                let by = top + CGFloat(b) * bh
                let localY = top - by                      // image top in ribbon coordinates
                let base = 0.06 * S                         // clip starts 0.06 S left of the cell
                setContents(r.new, ink?.image); setContents(r.accent, acc?.image)
                if !anim {
                    let io = reduce ? 0 : 0.011 * S * CGFloat(sin(T * 1.5 - Double(b) * 0.5 - Double(j) * 0.9))
                        + (b == scanB ? 0.05 * S * CGFloat(bump) : 0)
                    r.skew.transform = CATransform3DIdentity
                    r.old.isHidden = true
                    for g in r.ghosts { g.isHidden = true }
                    place(r.new, x: base + io, y: localY, rect: ink?.rect, opacity: 1)
                    let lit = b == scanB && !reduce
                    place(r.accent, x: base + io, y: localY, rect: acc?.rect, opacity: lit ? Float(0.9 * bump) : 0)
                } else {
                    let k = min(max((T - s.start - abs(Double(b) - mid) * Self.ribbonStagger) / Self.duration, 0), 1)
                    let e = R3Easing.expoInOut(k)
                    let vel = min(max((R3Easing.expoInOut(min(1, k + 0.01)) - e) / 0.01 / 7, 0), 1)
                    let dir: CGFloat = b % 2 == 1 ? 1 : -1
                    let shift = w * 1.2
                    var skew = CATransform3DIdentity
                    skew.m21 = -dir * CGFloat(vel) * 0.4             // x' = x − dir·vel·0.4·y
                    r.skew.transform = skew
                    setContents(r.old, oldImg?.image)
                    if e < 1, oldImg != nil {
                        place(r.old, x: base + dir * shift * CGFloat(e), y: localY, rect: oldImg?.rect, opacity: 1)
                    } else { r.old.isHidden = true }
                    if e > 0 {
                        let nx = base - dir * shift * CGFloat(1 - e)
                        for (gi, g) in r.ghosts.enumerated() {
                            let n = CGFloat(gi + 1)
                            setContents(g, ink?.image)
                            place(g, x: nx - dir * shift * 0.05 * n, y: localY, rect: ink?.rect, opacity: Float(0.3 / Double(n) * vel))
                        }
                        place(r.new, x: nx, y: localY, rect: ink?.rect, opacity: 1)
                        let tint = max(vel, (1 - e) * 0.35)
                        place(r.accent, x: nx, y: localY, rect: acc?.rect, opacity: tint > 0.01 ? Float(tint) : 0)
                    } else {
                        for l in r.ghosts + [r.new, r.accent] { l.isHidden = true }
                    }
                }
            }
        }

        // Colon: two squares of three ribbons, full for half a second, 30% for the other half.
        let on: Float = context.reduceMotion || time.millisecond < 500 ? 1 : 0.3
        for c in colon where c.opacity != on { c.opacity = on }

        chrome.setLabel(R3Chrome.labelText(time, showSeconds: context.showSeconds))
        if cache.count > usedThisFrame.count { cache = cache.filter { usedThisFrame.contains($0.key) } }
    }

    /// Only touch `contents` when the image actually changes.
    private func setContents(_ l: CALayer, _ img: CGImage?) {
        if (l.contents as AnyObject?) !== img { l.contents = img }
    }

    /// Positions a cropped digit image: (x, y) is the cell's origin, `rect` the crop inside it.
    private func place(_ l: CALayer, x: CGFloat, y: CGFloat, rect: CGRect?, opacity: Float) {
        guard let rect else { l.isHidden = true; return }
        l.isHidden = opacity <= 0
        l.frame = rect.offsetBy(dx: x, dy: y)
        l.opacity = opacity
    }

    // MARK: Layout

    /// Sizes the numerals for the digits on show (the 12h leading blank drops out) and lays out
    /// every ribbon clip and the colon.
    private func place(_ visible: [Int]) {
        let W = bounds.width, H = bounds.height
        let n = CGFloat(visible.count)
        let units = n * 0.72 + 0.3 + max(n - 2, 0) * 0.04
        let S = min(H * 0.6, W * 0.86 / units)
        if abs(S - size) > 0.5 { cache.removeAll() }
        size = S
        top = H / 2 - S * 0.51
        let w = S * 0.72, h = S * 1.02, bh = h / CGFloat(Self.ribbons), gap = max(1 / scale, S * 0.0075)
        var x = (W - units * S) / 2
        for c in colon { c.isHidden = true }

        for (i, s) in slots.enumerated() {
            s.visible = visible.contains(i)
            for r in s.ribbons { r.clip.isHidden = !s.visible }
            guard s.visible, let j = visible.firstIndex(of: i) else { continue }
            s.x = x
            for (b, r) in s.ribbons.enumerated() {
                r.clip.frame = CGRect(x: x - 0.06 * S, y: top + CGFloat(b) * bh, width: w + 0.12 * S, height: bh - gap)
                r.skew.frame = CGRect(x: 0, y: 0, width: r.clip.bounds.width, height: bh)
                // Slant pivots on the ribbon's centre: (glyph centre, ribbon middle).
                r.skew.anchorPoint = CGPoint(x: (0.06 * S + w / 2) / r.clip.bounds.width, y: 0.5)
                r.skew.position = CGPoint(x: 0.06 * S + w / 2, y: bh / 2)
                for l in r.images { l.contentsScale = scale; l.contentsGravity = .resize }
            }
            x += w
            if j < visible.count - 1 {
                if i == 1 {
                    let colonW = S * 0.3, cx = x + colonW / 2, sq = S * 0.09
                    for (k, c) in colon.enumerated() {
                        let sg: CGFloat = k < 3 ? -1 : 1, row = CGFloat(k % 3)
                        let t0 = H / 2 + sg * S * 0.17 - sq / 2
                        c.frame = CGRect(x: cx - sq / 2, y: t0 + row * sq / 3, width: sq, height: sq / 3 - gap * 0.6)
                        c.isHidden = false
                    }
                    x += colonW
                } else {
                    x += S * 0.04
                }
            }
        }
    }

    /// The digit drawn in Anybody 800, semi-condensed, centred in a 0.72 S × 1.02 S cell, cropped
    /// to its ink (plus a 2 pt margin) so the image is a fraction of the cell's size.
    private func glyph(_ ch: Character, accent: Bool) -> Glyph? {
        guard ch != " ", size > 0 else { return nil }
        let key = "\(ch)\(accent ? "a" : "i")"
        usedThisFrame.insert(key)
        if let hit = cache[key] { return hit }
        let S = size, w = S * 0.72, h = S * 1.02
        let font = Fonts.anybody(size: S, weight: 800, width: 87.5)
        var u = UniChar(ch.unicodeScalars.first!.value), g: CGGlyph = 0, adv = CGSize.zero
        CTFontGetGlyphsForCharacters(font, &u, &g, 1)
        CTFontGetAdvancesForGlyphs(font, .horizontal, &g, &adv, 1)
        var ink = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font, .horizontal, &g, &ink, 1)
        // textBaseline 'middle' at h/2 + 0.035 S (canvas, y down).
        let a = CTFontGetAscent(font), d = CTFontGetDescent(font)
        let baselineDown = h / 2 + S * 0.035 + (a - d) / 2
        let penX = (w - adv.width) / 2
        // Ink box in cell coordinates (y down), padded and clamped to the cell.
        let rect = CGRect(x: penX + ink.minX, y: baselineDown - ink.maxY, width: ink.width, height: ink.height)
            .insetBy(dx: -2, dy: -2).intersection(CGRect(x: 0, y: 0, width: w, height: h)).integral
        let pw = max(1, Int(ceil(rect.width * scale))), ph = max(1, Int(ceil(rect.height * scale)))
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(accent ? palette.accent : palette.ink)
        // Cell → crop space (y up): x − rect.minX; baseline at (rect.maxY − baselineDown) from the bottom.
        var pos = CGPoint(x: penX - rect.minX, y: rect.maxY - baselineDown)
        CTFontDrawGlyphs(font, &g, &pos, 1, ctx)
        guard let image = ctx.makeImage() else { return nil }
        let glyph = Glyph(image: image, rect: rect)
        cache[key] = glyph
        return glyph
    }

    // MARK: Appearance

    func appearanceDidChange(_ appearance: Appearance) {
        self.appearance = appearance
        palette = .forAppearance(appearance)
        cache.removeAll()
        applyPalette()
    }

    func stop() {
        chrome.remove()
        for s in slots { for r in s.ribbons { r.clip.removeFromSuperlayer() } }
        for c in colon { c.removeFromSuperlayer() }
        cache.removeAll()
    }

    private func applyPalette() {
        chrome.apply(palette, pureBlack: context.pureBlack && appearance == .dark)
        for c in colon { c.backgroundColor = palette.ink }
    }
}
