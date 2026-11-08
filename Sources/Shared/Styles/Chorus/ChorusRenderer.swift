import AppKit
import QuartzCore

/// Chorus: 24 small analog clocks (8 × 3, two columns per digit) whose hands spell the time.
/// Ported from the prototype's `Chorus`. Faces are one pre-rendered bitmap; hands are layers
/// rotated per frame from the prototype's easing.
final class ChorusRenderer: ClockStyle {
    private struct Palette {
        let bg, faceA, faceB, rim, tick, hand, shadow, label: CGColor
        /// Prototype night bg #09090b, deepened to true black.
        static let night = Palette(bg: srgb(0x000000), faceA: srgb(0x1d1e23), faceB: srgb(0x0f1013),
                                   rim: srgb(0xffffff, 0.07), tick: srgb(0xffffff, 0.16), hand: srgb(0xf3efe6),
                                   shadow: srgb(0x000000, 0.6), label: srgb(0xece9e2, 0.42))
        static let paper = Palette(bg: srgb(0xe6e2d8), faceA: srgb(0xfbf9f4), faceB: srgb(0xe4dfd4),
                                   rim: srgb(0x000000, 0.09), tick: srgb(0x000000, 0.22), hand: srgb(0x161618),
                                   shadow: srgb(0x3c2d14, 0.22), label: srgb(0x1e1c18, 0.5))
    }

    /// Hand angles per digit: [row][column] → (hand A, hand B), degrees clockwise from 12.
    /// `n` is the parked position (both hands at 225°, drawn at 25% opacity).
    private static let n = (225.0, 225.0)
    private static let patterns: [Character: [[(Double, Double)]]] = [
        "0": [[(90, 180), (270, 180)], [(0, 180), (0, 180)], [(0, 90), (0, 270)]],
        "1": [[n, (180, 180)], [n, (0, 180)], [n, (0, 0)]],
        "2": [[(90, 90), (270, 180)], [(90, 180), (270, 0)], [(0, 90), (270, 270)]],
        "3": [[(90, 90), (270, 180)], [(90, 90), (0, 180)], [(90, 90), (270, 0)]],
        "4": [[(180, 180), (180, 180)], [(0, 90), (0, 180)], [n, (0, 0)]],
        "5": [[(90, 180), (270, 270)], [(0, 90), (270, 180)], [(90, 90), (0, 270)]],
        "6": [[(90, 180), (270, 270)], [(0, 90), (270, 180)], [(0, 90), (0, 270)]],
        "7": [[(90, 90), (270, 180)], [n, (0, 180)], [n, (0, 0)]],
        // Prototype's 8 repeats the top row at the bottom (lower loop has no sides); closed here.
        "8": [[(90, 180), (270, 180)], [(0, 90), (0, 270)], [(0, 90), (0, 270)]],
        "9": [[(90, 180), (270, 180)], [(0, 90), (0, 180)], [(90, 90), (0, 270)]],
    ]
    private static let blank: [[(Double, Double)]] = Array(repeating: [n, n], count: 3)
    private static let columnGap: [Double] = [0, 0.2, 1, 1.2]   // extra space before each digit

    private final class Cell {
        let c: Int, r: Int
        let face = CALayer()
        let shadows = [CALayer(), CALayer()]
        let hands = [CALayer(), CALayer()]
        let hub = CALayer()
        var fa = 225.0, fb = 225.0, da = 0.0, db = 0.0, fal = 0.25, dal = 0.0
        var start: CFTimeInterval = 0, delay = 0.0
        init(c: Int, r: Int) { self.c = c; self.r = r }
        /// Position relative to the grid's center, in cells.
        var gx: Double { Double(c) + ChorusRenderer.columnGap[c >> 1] - 4.1 }
        var gy: Double { Double(r) - 1 }
    }

    private let context: StyleContext
    private var appearance: Appearance
    private var palette: Palette
    private let background = CALayer()
    private let label = CATextLayer()
    private let cells: [Cell]
    private var key: String?
    private var bounds = CGRect.zero, scale: CGFloat = 2
    private var cellSize: CGFloat = 0, origin = CGPoint.zero
    private var labelText = ""

    private var duration: Double { (context.reduceMotion ? 0.4 : 2.6) * max(context.timeScale, 0.01) }

    init(context: StyleContext) {
        self.context = context
        self.palette = context.appearance == .dark ? .night : .paper
        self.appearance = context.appearance
        var list: [Cell] = []
        for c in 0..<8 { for r in 0..<3 { list.append(Cell(c: c, r: r)) } }
        cells = list
    }

    func start(in root: CALayer) {
        root.addSublayer(background)
        for cl in cells {
            for l in [cl.face] + cl.shadows + cl.hands + [cl.hub] { root.addSublayer(l) }
            for h in cl.hands + cl.shadows { h.allowsEdgeAntialiasing = true }
        }
        label.alignmentMode = .right
        root.addSublayer(label)
        applyPalette()
    }

    func layout(bounds: CGRect, scale: CGFloat) {
        self.bounds = bounds
        self.scale = scale
        background.frame = Room.frame(bounds)
        let W = bounds.width, H = bounds.height
        cellSize = min(W * 0.9 / 9.2, H * 0.74 / 3)
        origin = CGPoint(x: (W - cellSize * 9.2) / 2, y: (H - cellSize * 3) / 2)
        let R = cellSize * 0.47, hw = cellSize * 0.115
        let faceImage = makeFace(radius: R)
        let len = R * 0.9 + hw
        for cl in cells {
            let center = cellCenter(cl)
            cl.face.contents = faceImage
            cl.face.contentsScale = scale
            cl.face.frame = CGRect(x: center.x - R - 3, y: center.y - R - 3, width: 2 * R + 6, height: 2 * R + 6)
            for h in cl.hands + cl.shadows {
                h.bounds = CGRect(x: 0, y: 0, width: hw, height: len)
                h.cornerRadius = hw / 2
                h.anchorPoint = CGPoint(x: 0.5, y: (len - hw / 2) / len)   // rotate about the clock center
                h.contentsScale = scale
            }
            let so = cellSize * 0.032
            for h in cl.hands { h.position = center }
            for s in cl.shadows { s.position = CGPoint(x: center.x + so * 0.6, y: center.y + so) }
            let hubR = hw * 0.62
            cl.hub.frame = CGRect(x: center.x - hubR, y: center.y - hubR, width: 2 * hubR, height: 2 * hubR)
            cl.hub.cornerRadius = hubR
        }
        let u = W / 100
        label.contentsScale = scale
        label.frame = CGRect(x: 0, y: H - 2.8 * u - 1.6 * u, width: W - 3.2 * u, height: 1.8 * u)
        updateLabel(force: true)
    }

    private func cellCenter(_ cl: Cell) -> CGPoint {
        CGPoint(x: origin.x + (CGFloat(cl.c) + CGFloat(Self.columnGap[cl.c >> 1])) * cellSize + cellSize / 2,
                y: origin.y + CGFloat(cl.r) * cellSize + cellSize / 2)
    }

    // MARK: Motion

    private func value(_ cl: Cell, _ t: CFTimeInterval) -> (a: Double, b: Double, al: Double) {
        let k = min(max((t - cl.start - cl.delay) / duration, 0), 1)
        let e = k < 0.5 ? 4 * k * k * k : 1 - pow(-2 * k + 2, 3) / 2   // ease-in-out cubic
        return (cl.fa + cl.da * e, cl.fb + cl.db * e, cl.fal + cl.dal * e)
    }

    /// Every hand travels to its target with one extra full turn: A clockwise, B counterclockwise.
    private func retarget(_ t: CFTimeInterval, ripple: Bool, _ target: (Cell) -> (Double, Double, Bool)) {
        let speed = max(context.timeScale, 0.01)
        for cl in cells {
            let (ta, tb, neutral) = target(cl)
            let cur = value(cl, t)
            cl.fa = cur.a.truncatingRemainder(dividingBy: 360); if cl.fa < 0 { cl.fa += 360 }
            cl.fb = cur.b.truncatingRemainder(dividingBy: 360); if cl.fb < 0 { cl.fb += 360 }
            cl.fal = cur.al
            cl.da = mod360(ta - cl.fa) + 360
            cl.db = -(mod360(cl.fb - tb) + 360)
            cl.dal = (neutral ? 0.25 : 1) - cl.fal
            cl.start = t
            let d = ripple ? hypot(cl.gx, cl.gy) * 0.170 : Double(cl.c) * 0.090 + Double(cl.r) * 0.055
            cl.delay = context.reduceMotion ? 0 : d * speed
        }
    }

    private func mod360(_ v: Double) -> Double { let m = v.truncatingRemainder(dividingBy: 360); return m < 0 ? m + 360 : m }

    func render(time: ClockTime, frameTime t: CFTimeInterval) {
        let digits = time.digits
        let digitString = String(digits.map { $0 ?? " " })
        let inPattern = !context.reduceMotion && time.second >= 27 && time.second < 36
        let k = inPattern ? "pat\(time.minute % 3)\(digitString)" : digitString
        if k != key {
            let wasPattern = key?.hasPrefix("pat") ?? false
            key = k
            if inPattern {
                let p = time.minute % 3
                retarget(t, ripple: true) { cl in
                    switch p {
                    case 0: return (45, 225, false)                         // diagonals
                    case 1: return (90, 270, false)                         // horizontal lines
                    default:                                                // starburst to center
                        let a = (atan2(cl.gy, cl.gx) * 180 / .pi + 90 + 360).truncatingRemainder(dividingBy: 360)
                        return (a, (a + 180).truncatingRemainder(dividingBy: 360), false)
                    }
                }
            } else {
                retarget(t, ripple: wasPattern) { cl in
                    let digit = digits[cl.c >> 1]
                    let grid = digit.flatMap { Self.patterns[$0] } ?? Self.blank
                    let pair = grid[cl.r][cl.c & 1]
                    return (pair.0, pair.1, pair == Self.n)
                }
            }
        }

        for cl in cells {
            let v = value(cl, t)
            let angles = [v.a, v.b]
            for i in 0..<2 {
                let rot = CATransform3DMakeRotation(CGFloat(angles[i] * .pi / 180), 0, 0, 1)
                cl.hands[i].transform = rot
                cl.shadows[i].transform = rot
                cl.hands[i].opacity = Float(v.al)
                cl.shadows[i].opacity = Float(v.al)
            }
            cl.hub.opacity = Float(max(0.5, v.al))
        }

        let text = [context.showSeconds ? String(time.secondDigits) : nil, time.meridiem].compactMap { $0 }.joined(separator: "   ")
        if text != labelText { labelText = text; updateLabel(force: true) }
    }

    func appearanceDidChange(_ appearance: Appearance) {
        self.appearance = appearance
        palette = appearance == .dark ? .night : .paper
        applyPalette()
        if cellSize > 0 { layout(bounds: bounds, scale: scale) }   // faces are baked per palette
    }

    func stop() {
        background.removeFromSuperlayer()
        label.removeFromSuperlayer()
        for cl in cells { for l in [cl.face] + cl.shadows + cl.hands + [cl.hub] { l.removeFromSuperlayer() } }
    }

    private func applyPalette() {
        background.backgroundColor = palette.bg
        for cl in cells {
            for h in cl.hands { h.backgroundColor = palette.hand }
            for s in cl.shadows { s.backgroundColor = palette.shadow }
            cl.hub.backgroundColor = palette.hand
        }
        updateLabel(force: true)
    }

    private func updateLabel(force: Bool) {
        let size = 1.4 * bounds.width / 100
        label.string = NSAttributedString(string: labelText, attributes: [
            .font: Fonts.label(size: max(size, 1)), .kern: 0.24 * size,
            .foregroundColor: NSColor(cgColor: palette.label) ?? .gray,
        ])
    }

    /// One face bitmap: radial gradient, 1 px rim, 12 ticks (quarters longer and thicker).
    private func makeFace(radius R: CGFloat) -> CGImage? {
        let side = Int(ceil((2 * R + 6) * scale))
        guard side > 0, let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        // Draw y-down like the canvas.
        ctx.translateBy(x: 0, y: 2 * R + 6); ctx.scaleBy(x: 1, y: -1)
        let m = R + 3
        if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [palette.faceA, palette.faceB] as CFArray, locations: [0, 1]) {
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: m - R, y: m - R, width: 2 * R, height: 2 * R))
            ctx.clip()
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: m, y: m - R * 0.5), startRadius: R * 0.1,
                                   endCenter: CGPoint(x: m, y: m), endRadius: R, options: [.drawsAfterEndLocation])
            ctx.restoreGState()
        }
        ctx.setLineWidth(1)
        ctx.setStrokeColor(palette.rim)
        ctx.strokeEllipse(in: CGRect(x: m - R, y: m - R, width: 2 * R, height: 2 * R))
        ctx.setStrokeColor(palette.tick)
        ctx.setLineCap(.round)
        for i in 0..<12 {
            let a = CGFloat(i) * .pi / 6
            let r1 = R * (i % 3 == 0 ? 0.8 : 0.86), r2 = R * 0.92
            ctx.setLineWidth(max(1, R * (i % 3 == 0 ? 0.035 : 0.022)))
            ctx.move(to: CGPoint(x: m + cos(a) * r1, y: m + sin(a) * r1))
            ctx.addLine(to: CGPoint(x: m + cos(a) * r2, y: m + sin(a) * r2))
            ctx.strokePath()
        }
        return ctx.makeImage()
    }
}
