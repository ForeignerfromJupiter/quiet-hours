import AppKit
import QuartzCore

/// The shared look of Slice, Poster and Module (prototype `R3_PAL`, PRD "Shared look").
struct R3Palette {
    let roomCenter: CGColor, roomEdge: CGColor
    let ink: CGColor
    let inkRGB: SIMD3<Double>
    let accent: CGColor
    let accentRGB: SIMD3<Double>
    let label: CGColor

    func ink(_ alpha: Double) -> CGColor { color(inkRGB, alpha) }

    /// Night: prototype bg #17171b → #08080a, deepened (owner's call) to true black at the edges.
    static let night = R3Palette(roomCenter: srgb(0x111114), roomEdge: srgb(0x000000),
                                 ink: srgb(0xefebe2), inkRGB: SIMD3(239, 235, 226) / 255,
                                 accent: srgb(0xf0b35e), accentRGB: SIMD3(240, 179, 94) / 255,
                                 label: srgb(0xece9e2, 0.42))
    static let paper = R3Palette(roomCenter: srgb(0xf3f0e9), roomEdge: srgb(0xddd7cb),
                                 ink: srgb(0x161514), inkRGB: SIMD3(22, 21, 20) / 255,
                                 accent: srgb(0x2b4c7e), accentRGB: SIMD3(43, 76, 126) / 255,
                                 label: srgb(0x1e1c18, 0.5))

    static func forAppearance(_ a: Appearance) -> R3Palette { a == .dark ? .night : .paper }

    /// Linear blend from ink to accent (Module's curve tint, Slice's speed tint).
    func blend(_ k: Double) -> CGColor {
        let t = min(max(k, 0), 1)
        return color(inkRGB + (accentRGB - inkRGB) * t, 1)
    }

    private func color(_ c: SIMD3<Double>, _ a: Double) -> CGColor {
        CGColor(srgbRed: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: CGFloat(a))
    }
}

enum R3Easing {
    /// Prototype `expoIO`: exponential in-out.
    static func expoInOut(_ k: Double) -> Double {
        if k <= 0 { return 0 }
        if k >= 1 { return 1 }
        return k < 0.5 ? pow(2, 20 * k - 10) / 2 : (2 - pow(2, -20 * k + 10)) / 2
    }

    /// Prototype `easeBack` (c1 = 1.9): overshoots then settles.
    static func backOut(_ k: Double) -> Double {
        let c1 = 1.9, c3 = c1 + 1
        return 1 + c3 * pow(k - 1, 3) + c1 * pow(k - 1, 2)
    }
}

/// Background and corner label shared by the three styles.
final class R3Chrome {
    let background = CAGradientLayer()
    let label = CATextLayer()
    private var text = ""
    private var bounds = CGRect.zero

    init() {
        // createRadialGradient(W*.5, H*.42, 0, W*.5, H*.5, max(W,H)*.7)
        background.type = .radial
        label.alignmentMode = .right
    }

    func install(in root: CALayer, below: CALayer? = nil) {
        root.insertSublayer(background, at: 0)
        root.addSublayer(label)
    }

    func layout(bounds: CGRect, scale: CGFloat) {
        self.bounds = bounds
        background.frame = Room.frame(bounds)
        let r = 0.7 * max(bounds.width, bounds.height)
        background.startPoint = CGPoint(x: 0.5, y: 0.46)
        background.endPoint = CGPoint(x: 0.5 + r / max(bounds.width, 1), y: 0.46 + r / max(bounds.height, 1))
        let u = bounds.width / 100
        label.contentsScale = scale
        label.frame = CGRect(x: 0, y: bounds.height - 2.8 * u - 1.6 * u, width: bounds.width - 3.2 * u, height: 1.8 * u)
    }

    func apply(_ p: R3Palette, pureBlack: Bool) {
        background.colors = pureBlack ? [Room.black, Room.black] : [p.roomCenter, p.roomEdge]
        palette = p
        setLabel(text, force: true)
    }

    private var palette: R3Palette = .night

    /// `.corner-label`: seconds and AM/PM, letter-spaced mono, bottom right.
    func setLabel(_ s: String, force: Bool = false) {
        guard force || s != text else { return }
        text = s
        let size = max(1, 1.4 * bounds.width / 100)
        label.string = NSAttributedString(string: s, attributes: [
            .font: Fonts.label(size: size), .kern: 0.24 * size,
            .foregroundColor: NSColor(cgColor: palette.label) ?? .gray,
        ])
    }

    func remove() {
        background.removeFromSuperlayer()
        label.removeFromSuperlayer()
    }

    static func labelText(_ time: ClockTime, showSeconds: Bool) -> String {
        [showSeconds ? time.secondsMark : nil, time.meridiem].compactMap { $0 }.joined(separator: "   ")
    }
}
