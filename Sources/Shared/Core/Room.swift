import CoreGraphics

/// The background ("room") behind every style: the Pure black option and burn-in shift margin.
enum Room {
    /// The burn-in shift moves a clock at most this far (points), so backgrounds are oversized by it.
    static let shiftMargin: CGFloat = 16

    static let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)

    /// Widest aspect a composition is laid out for. Wider screens (21:9, 32:9 super-ultrawides)
    /// get the composition in a centred stage of this shape; backgrounds still fill the screen.
    static let maxStageAspect: CGFloat = 16.0 / 9.0

    /// The centred area compositions that place things by screen-width fractions (Poster, Prose,
    /// Board) lay out in. Equal to `bounds` on 16:10, 16:9 and anything narrower.
    static func stage(_ bounds: CGRect) -> CGRect {
        let w = min(bounds.width, bounds.height * maxStageAspect)
        return CGRect(x: bounds.minX + (bounds.width - w) / 2, y: bounds.minY, width: w, height: bounds.height)
    }

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
