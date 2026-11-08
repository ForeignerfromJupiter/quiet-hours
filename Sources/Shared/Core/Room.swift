import CoreGraphics

/// The background ("room") behind every style: the Pure black option and burn-in shift margin.
enum Room {
    /// The burn-in shift moves a clock at most this far (points), so backgrounds are oversized by it.
    static let shiftMargin: CGFloat = 16

    static let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)

    /// Background frame, oversized so the burn-in shift never uncovers an edge.
    static func frame(_ bounds: CGRect) -> CGRect {
        bounds.insetBy(dx: -shiftMargin, dy: -shiftMargin)
    }

    /// Room gradient colours. With Pure black on, a dark finish's room is #000 throughout, so an OLED
    /// panel switches those pixels off and mini-LED panels don't glow around the clock.
    static func colors(center: CGColor, edge: CGColor, appearance: Appearance, pureBlack: Bool) -> [CGColor] {
        appearance == .dark && pureBlack ? [black, black] : [center, edge]
    }

    /// Burn-in shift: a slow Lissajous drift of a few pixels (about 0.4% of the shorter side, at
    /// least 3 pt), snapped to whole device pixels so text never resamples soft. Periods of ~7 and
    /// ~6 minutes mean nothing stays on the same pixels for long, and nobody notices it moving.
    static func burnInOffset(at time: Double, size: CGSize, scale: CGFloat) -> CGPoint {
        let amplitude = min(shiftMargin - 2, max(3, 0.004 * min(size.width, size.height)))
        let x = amplitude * CGFloat(sin(2 * .pi * time / 437))
        let y = amplitude * CGFloat(sin(2 * .pi * time / 353 + 1.3))
        let s = max(scale, 1)
        return CGPoint(x: (x * s).rounded() / s, y: (y * s).rounded() / s)
    }
}
