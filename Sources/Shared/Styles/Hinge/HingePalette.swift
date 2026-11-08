import CoreGraphics

/// Colors straight from the prototype's `.hinge` CSS custom properties (sRGB).
struct HingePalette {
    let roomCenter: CGColor   // --bgA
    let roomEdge: CGColor     // --bgB
    let topA: CGColor, topB: CGColor
    let bottomA: CGColor, bottomB: CGColor
    let ink: CGColor
    let seam: CGColor
    let pin: CGColor
    let label: CGColor
    let highlight: CGColor    // --hi
    let fold: CGColor         // --fold: the shade a falling leaf casts
    let foldClear: CGColor    // --fold at alpha 0, so gradients fade without going grey

    /// Dark finish: charcoal cards, warm white numerals, near-black room.
    static let graphite = HingePalette(
        roomCenter: srgb(0x1a1b1f), roomEdge: srgb(0x070708),
        topA: srgb(0x25262b), topB: srgb(0x1d1e22),
        bottomA: srgb(0x1a1b1e), bottomB: srgb(0x141517),
        ink: srgb(0xefebe2), seam: srgb(0x050506), pin: srgb(0x34353b), label: srgb(0x7f7c75),
        highlight: srgb(0xffffff, 0.07),
        fold: srgb(0x000000, 0.62), foldClear: srgb(0x000000, 0))

    /// Light finish: cream cards, near-black numerals, dark warm room.
    static let ivory = HingePalette(
        roomCenter: srgb(0x2a2723), roomEdge: srgb(0x0d0c0b),
        topA: srgb(0xf4f0e6), topB: srgb(0xebe6da),
        bottomA: srgb(0xe3ddd0), bottomB: srgb(0xd8d1c2),
        ink: srgb(0x1c1b19), seam: srgb(0x6f695f), pin: srgb(0xb9b2a3), label: srgb(0x9b958a),
        highlight: srgb(0xffffff, 0.7),
        fold: srgb(0x281e0f, 0.38), foldClear: srgb(0x281e0f, 0))

    static func forAppearance(_ a: Appearance) -> HingePalette { a == .dark ? .graphite : .ivory }
}

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha)
}
