import Foundation

/// 12h time: the leading hour digit appears (9:59 → 10:00) or goes (12:59 → 1:00), and the row
/// changes width. The prototype dropped or added the slot at once, so for a moment the clock read
/// "2:59" and the row jumped. Styles that lay out a row of digits use this timeline instead, and
/// never show a wrong time:
///
/// - going: the digits change first (the leading one to blank), then the row glides shut;
/// - opening: the row glides open around an empty slot first, then the digits change.
///
/// Times are animation seconds (frame time / time scale).
struct LeadingSlotChange: Equatable {
    var start: Double
    var opening: Bool
    /// How long the style's digit change takes (going: the row waits for it).
    var settle: Double

    static let glide = 0.45
    static let curve = CubicBezier(0.65, 0, 0.35, 1)   // ease-in-out

    var glideStart: Double { opening ? start : start + settle }
    var end: Double { glideStart + Self.glide }
    /// When the digits start changing.
    var changeStart: Double { opening ? start + Self.glide : start }

    /// How open the leading slot is: 0 = no slot, 1 = a full slot.
    func presence(at t: Double) -> Double {
        let k = Self.curve(min(max((t - glideStart) / Self.glide, 0), 1))
        return opening ? k : 1 - k
    }

    func isDone(at t: Double) -> Bool { t >= end }
}
