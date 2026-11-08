import Foundation

/// The prototype's flip, as a pure function of elapsed time (seconds).
///
///     .flap.go .front  hFold .25s cubic-bezier(.6,0,.95,.5)            rotateX 0 → -90°
///     .flap.go .back   hRise .42s delay .24s cubic-bezier(.18,1.65,.42,1) rotateX 90° → 0 (overshoots ~11°)
///     front::after     shade 0 → 1 over .25s (ease)
///     bottom::after    shade 0 → 1 over .25s (ease), held until the flip ends
///     back::after      shade 1 → 0 over .42s, delay .24s (ease)
///     700 ms           flip ends; the static bottom half takes the new digit
enum HingeFlipTimeline {
    static let foldDuration = 0.25
    static let riseDelay = 0.24
    static let riseDuration = 0.42
    static let total = 0.70

    static let foldCurve = CubicBezier(0.6, 0, 0.95, 0.5)
    static let riseCurve = CubicBezier(0.18, 1.65, 0.42, 1)
    static let shadeCurve = CubicBezier.ease

    struct State: Equatable {
        var frontVisible: Bool
        var frontAngle: Double     // degrees, CSS rotateX sign convention
        var frontShade: Double
        var bottomShade: Double
        var backVisible: Bool
        var backAngle: Double
        var backShade: Double
        var finished: Bool
    }

    static func state(at e: Double) -> State {
        let fold = min(max(e / foldDuration, 0), 1)
        let riseT = (e - riseDelay) / riseDuration
        let rising = e >= riseDelay
        return State(
            frontVisible: e < foldDuration,
            frontAngle: -90 * foldCurve(fold),
            frontShade: shadeCurve(fold),
            bottomShade: shadeCurve(fold),
            backVisible: rising && e < total,
            backAngle: rising ? 90 * (1 - riseCurve(riseT)) : 90,
            backShade: rising ? 1 - shadeCurve(riseT) : 1,
            finished: e >= total)
    }
}
