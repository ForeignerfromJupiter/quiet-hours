import QuartzCore

/// Everything a style needs to know when it is created. Rebuilt on every `startAnimation`.
struct StyleContext {
    var isPreview: Bool          // System Settings thumbnail: keep it cheap
    var showSeconds: Bool
    var uses24Hour: Bool
    var reduceMotion: Bool
    var appearance: Appearance
    var timeScale: Double = 1    // >1 slows animations down (Preview app debugging only)
    var freezeFlipAt: Double?    // hold transitions at this point (Preview app debugging only)
}

/// One self-contained renderer per clock style.
///
/// Lifecycle: `init` → `start(in:)` → `layout` → `render` every frame → `stop`.
/// All calls arrive on the main thread inside a CATransaction with implicit actions disabled.
protocol ClockStyle: AnyObject {
    init(context: StyleContext)

    /// Build the layer tree under `root` (a geometry-flipped layer: origin top-left).
    func start(in root: CALayer)

    /// Bounds or backing scale changed.
    func layout(bounds: CGRect, scale: CGFloat)

    /// Called once per display frame. `frameTime` is in the `CACurrentMediaTime()` base.
    /// Styles should do no layer work when nothing changes.
    func render(time: ClockTime, frameTime: CFTimeInterval)

    /// Dark/light changed while running (Auto finish following the system).
    func appearanceDidChange(_ appearance: Appearance)

    /// Tear down layers and drop any resources.
    func stop()
}

enum ClockStyles {
    static func make(_ id: StyleID, context: StyleContext) -> ClockStyle {
        switch id {
        case .hinge, .chorus, .breath, .lumen:
            // Only Hinge exists in Phase 1; the others fall back to it.
            return HingeRenderer(context: context)
        }
    }
}
