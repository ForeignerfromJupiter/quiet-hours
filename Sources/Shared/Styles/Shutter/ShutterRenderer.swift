import AppKit
import QuartzCore

/// Shutter's seven-blade iris (prototype `Shutter`). Pure geometry, unit-tested.
///
/// The aperture is a regular heptagon. Blade i is the region between aperture edge i and edge
/// i − 1, both extended outward: its outline runs from vertex i along edge i (through vertex
/// i + 1) to a far point, across to the far end of edge i − 1's extension, and back to vertex i.
/// Neighbouring blades share an extended edge exactly, so the blades tile everything outside the
/// aperture out to `reach` with no gaps and no overlaps, at any aperture down to fully shut.
enum ShutterGeometry {
    static let bladeCount = 7

    struct Iris {
        /// Aperture vertices (y down), vertex i at angle `angle + i·2π/7`.
        var aperture: [CGPoint]
        /// Each blade as a quad (a, b, far(i), far(i−1)); a, b and far(i) are collinear.
        var blades: [[CGPoint]]
        /// The far ends of the extended edges: the outer outline of all the blades together.
        var outline: [CGPoint]
    }

    /// - Parameters:
    ///   - radius: aperture circumradius (0 = shut).
    ///   - angle: rotation of vertex 0, radians (canvas convention: y down, clockwise on screen).
    ///   - reach: how far each edge is extended past its vertex (prototype `BIG`).
    static func iris(center c: CGPoint, radius r: CGFloat, angle th: Double, reach: CGFloat) -> Iris {
        let n = bladeCount
        let step = 2 * Double.pi / Double(n)
        let V = (0..<n).map { i -> CGPoint in
            let a = th + Double(i) * step
            return CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r)
        }
        // Direction of edge i (vertex i → i + 1). For a regular polygon this is exact and also
        // defined when the aperture is shut (the prototype's r < 1 fallback is the same formula).
        let D = (0..<n).map { i -> CGVector in
            let a = th + Double(i) * step + Double.pi / 2 + Double.pi / Double(n)
            return CGVector(dx: CGFloat(cos(a)), dy: CGFloat(sin(a)))
        }
        let far = (0..<n).map { i -> CGPoint in
            let b = V[(i + 1) % n]
            return CGPoint(x: b.x + D[i].dx * reach, y: b.y + D[i].dy * reach)
        }
        let blades = (0..<n).map { i in [V[i], V[(i + 1) % n], far[i], far[(i + n - 1) % n]] }
        return Iris(aperture: V, blades: blades, outline: far)
    }

    /// Edge extension long enough that the blades cover `rect` (prototype: 4 × half-diagonal).
    static func reach(covering rect: CGRect, center: CGPoint) -> CGFloat {
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
        let d = corners.map { hypot($0.x - center.x, $0.y - center.y) }.max() ?? 1
        return 4 * d
    }

    static func path(_ points: [CGPoint]) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: points)
        p.closeSubpath()
        return p
    }
}

/// The close, swap and reopen timeline (PRD "Change"), in milliseconds since the minute changed.
enum ShutterTimeline {
    static let closeEnd = 380.0, swapAt = 460.0, reopenStart = 540.0, end = 1240.0

    /// 0 = at rest, 1 = shut. nil once the change is over.
    static func closure(at ms: Double) -> Double? {
        if ms < 0 { return 0 }
        if ms < closeEnd { let k = ms / closeEnd; return k * k * k }             // cubic ease-in
        if ms < reopenStart { return 1 }                                         // hold shut
        if ms < end { return pow(2, -10 * (ms - reopenStart) / (end - reopenStart)) }  // 1 − expo-out
        return nil
    }

    /// The numerals show the new time from here on; the iris is shut at this point.
    static func hasSwapped(at ms: Double) -> Bool { ms >= swapAt }
}

/// Shutter: the time behind a camera iris. Blade tips frame the corners and breathe; on the
/// minute the blades snap shut in the accent colour, turn about 63°, and reopen on the new time.
final class ShutterRenderer: ClockStyle {
    private let context: StyleContext
    private var appearance: Appearance
    private var palette: R3Palette
    private let chrome = R3Chrome()
    private let numerals = CAShapeLayer()
    /// Under the blades: the whole blade area in one even-odd fill, so an antialiased seam between
    /// two blades can only ever show blade colour, never the numerals or the room behind.
    private let backing = CAShapeLayer()
    private let blades = (0..<ShutterGeometry.bladeCount).map { _ in CAShapeLayer() }

    private var bounds = CGRect.zero, scale: CGFloat = 2
    private var shown: String?
    private var pending: String?
    private var changeStart: Double = 0
    private var drawnText = ""
    private var drawnKey = ""
    private var pathCache: [String: CGPath] = [:]
    private var speed: Double { max(context.timeScale, 0.01) }

    init(context: StyleContext) {
        self.context = context
        self.palette = .forAppearance(context.appearance)
        self.appearance = context.appearance
    }

    /// The iris breathes and turns all the time; with Reduce Motion it holds still.
    var wantsContinuousFrames: Bool { !context.reduceMotion }

    func start(in root: CALayer) {
        chrome.install(in: root)
        root.addSublayer(numerals)
        backing.fillRule = .evenOdd
        root.addSublayer(backing)
        for b in blades {
            b.lineWidth = 1                                       // strokeStyle rgba(0,0,0,.28), lineWidth 1
            b.strokeColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28)
            b.lineJoin = .miter
            root.addSublayer(b)
        }
        root.addSublayer(chrome.label)
        applyPalette()
    }

    func layout(bounds: CGRect, scale: CGFloat) {
        self.bounds = bounds
        self.scale = scale
        chrome.layout(bounds: bounds, scale: scale)
        for l in [numerals, backing] + blades { l.frame = bounds; l.contentsScale = scale }
        pathCache.removeAll()
        drawnText = ""
        drawnKey = ""
    }

    // MARK: Frame

    func render(time: ClockTime, frameTime: CFTimeInterval) {
        let T = frameTime / speed
        let txt = Self.timeText(time)
        if shown == nil || context.reduceMotion {
            shown = txt
            pending = nil
        } else if txt != shown && txt != pending {
            pending = txt
            changeStart = T
        }

        var close = 0.0
        if let next = pending {
            let ms = (T - changeStart) * 1000
            if let c = ShutterTimeline.closure(at: ms) {
                close = c
                if ShutterTimeline.hasSwapped(at: ms) { shown = next }
            } else {
                shown = next
                pending = nil
            }
        }
        chrome.setLabel(R3Chrome.labelText(time, showSeconds: context.showSeconds))

        let still = context.reduceMotion
        let key = still ? "\(shown ?? "")" : ""
        guard !still || key != drawnKey else { return }      // Reduce Motion: draw only on change
        drawnKey = key

        drawNumerals(shown ?? txt)
        numerals.isHidden = close >= 1                         // the swap happens while shut

        // Iris: aperture 86% of the half-diagonal, breathing ±1.8% (sin(t/1500), t in ms) and
        // turning 0.00004 rad/ms; closing shrinks it to a point while turning another 1.1 rad.
        let W = bounds.width, H = bounds.height
        let center = CGPoint(x: W / 2, y: H / 2)
        let hd = hypot(W, H) / 2
        let ms = T * 1000
        let breathe = still ? 0 : 0.018 * sin(ms / 1500)
        let r = hd * 0.86 * CGFloat(1 + breathe) * CGFloat(1 - close)
        let spin = still ? 0 : (ms * 0.00004).truncatingRemainder(dividingBy: 2 * Double.pi)
        let iris = ShutterGeometry.iris(center: center, radius: r, angle: spin + close * 1.1,
                                        reach: ShutterGeometry.reach(covering: Room.frame(bounds), center: center))

        let rest = appearance == .dark ? SIMD3<Double>(29, 30, 35) : SIMD3<Double>(208, 201, 187)  // #1d1e23 / #d0c9bb
        let acc = palette.accentRGB * 255
        let col = rest + (acc - rest) * close

        let back = CGMutablePath()
        back.addPath(ShutterGeometry.path(iris.outline))
        back.addPath(ShutterGeometry.path(iris.aperture))
        backing.path = back
        backing.fillColor = Self.rgb(col, shade: 0.9)
        for (i, layer) in blades.enumerated() {
            layer.path = ShutterGeometry.path(iris.blades[i])
            layer.fillColor = Self.rgb(col, shade: i % 2 == 1 ? 0.9 : 1)   // alternate blades 10% darker
        }
    }

    /// Prototype `trimTime`: "09:41" in 24h mode, "9:41" in 12h mode.
    static func timeText(_ t: ClockTime) -> String {
        let d = t.digits.compactMap { $0 }
        return String(d.dropLast(2)) + ":" + String(d.suffix(2))
    }

    /// Prototype `rgb(${col.map(c=>Math.round(c*sh))})` with col already rounded.
    private static func rgb(_ c: SIMD3<Double>, shade: Double) -> CGColor {
        let q = { (v: Double) in CGFloat((v.rounded() * shade).rounded() / 255) }
        return CGColor(srgbRed: q(c.x), green: q(c.y), blue: q(c.z), alpha: 1)
    }

    /// Anybody 800 semi-condensed, size min(46% H, 74% W / (0.6 × characters)), centred with
    /// canvas textBaseline 'middle' at H/2 + 0.03 S.
    private func drawNumerals(_ text: String) {
        guard text != drawnText else { return }
        drawnText = text
        let W = bounds.width, H = bounds.height
        let S = min(H * 0.46, W * 0.74 / (CGFloat(text.count) * 0.6))
        let key = "\(text)@\(Int(S * 4))"
        if let hit = pathCache[key] { numerals.path = hit; return }
        let font = Fonts.anybody(size: S, weight: 800, width: 87.5)   // fontStretch: semi-condensed
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let a = CTFontGetAscent(font), d = CTFontGetDescent(font)
        let baseline = H / 2 + S * 0.03 + (a - d) / 2
        let x0 = (W - width) / 2
        let path = CGMutablePath()
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let n = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: n), pos = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: n), &pos)
            for i in 0..<n {
                var t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: x0 + pos[i].x, ty: baseline)
                if let g = CTFontCreatePathForGlyph(font, glyphs[i], &t) { path.addPath(g) }
            }
        }
        pathCache[key] = path
        numerals.path = path
    }

    // MARK: Appearance

    func appearanceDidChange(_ appearance: Appearance) {
        self.appearance = appearance
        palette = .forAppearance(appearance)
        applyPalette()
        drawnKey = "\u{0}"
    }

    func stop() {
        chrome.remove()
        for l in [numerals, backing] + blades { l.removeFromSuperlayer() }
        pathCache.removeAll()
    }

    private func applyPalette() {
        chrome.apply(palette, pureBlack: context.pureBlack && appearance == .dark)
        numerals.fillColor = palette.ink
    }
}
