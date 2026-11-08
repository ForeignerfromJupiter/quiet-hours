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

    /// Dark finish: charcoal cards, warm white numerals, black room.
    /// Deeper than the prototype (owner's call): room goes to true black at the edges and the
    /// cards sit one step darker, so the saver disappears into a dark room and suits OLED/mini-LED.
    /// Prototype values: room #1a1b1f→#070708, top #25262b→#1d1e22, bottom #1a1b1e→#141517, seam #050506.
    static let graphite = HingePalette(
        roomCenter: srgb(0x0c0c0e), roomEdge: srgb(0x000000),
        topA: srgb(0x1e1f23), topB: srgb(0x17181b),
        bottomA: srgb(0x141517), bottomB: srgb(0x0e0f11),
        ink: srgb(0xefebe2), seam: srgb(0x000000), pin: srgb(0x2c2d32), label: srgb(0x6f6c66),
        highlight: srgb(0xffffff, 0.07),
        fold: srgb(0x000000, 0.62), foldClear: srgb(0x000000, 0))

    /// Light finish: cream cards, near-black numerals, dark warm room (prototype room #2a2723→#0d0c0b, deepened).
    static let ivory = HingePalette(
        roomCenter: srgb(0x1c1a17), roomEdge: srgb(0x000000),
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
