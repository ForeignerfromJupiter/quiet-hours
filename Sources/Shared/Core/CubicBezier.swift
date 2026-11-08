import Foundation

/// CSS `cubic-bezier(x1, y1, x2, y2)` timing function, solved the same way browsers do
/// (Newton–Raphson, falling back to bisection). y values may leave 0…1 for overshoot.
struct CubicBezier {
    private let cx, bx, ax, cy, by, ay: Double

    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        cx = 3 * x1; bx = 3 * (x2 - x1) - cx; ax = 1 - cx - bx
        cy = 3 * y1; by = 3 * (y2 - y1) - cy; ay = 1 - cy - by
    }

    private func sampleX(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
    private func sampleY(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
    private func sampleDX(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }

    private func solveT(forX x: Double) -> Double {
        var t = x
        for _ in 0..<8 {
            let err = sampleX(t) - x
            if abs(err) < 1e-7 { return t }
            let d = sampleDX(t)
            if abs(d) < 1e-6 { break }
            t -= err / d
        }
        var lo = 0.0, hi = 1.0
        t = x
        while lo < hi {
            let v = sampleX(t)
            if abs(v - x) < 1e-7 { return t }
            if x > v { lo = t } else { hi = t }
            t = (lo + hi) / 2
            if hi - lo < 1e-9 { break }
        }
        return t
    }

    /// Progress at time fraction `x` (clamped to 0…1).
    func callAsFunction(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        return sampleY(solveT(forX: x))
    }

    static let ease = CubicBezier(0.25, 0.1, 0.25, 1)
    static let linear = CubicBezier(0, 0, 1, 1)
}
