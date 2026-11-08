import QuartzCore

/// Everything a style needs to know when it is created. Rebuilt on every `startAnimation`.
struct StyleContext {
    var isPreview: Bool          // System Settings thumbnail: keep it cheap
    var showSeconds: Bool
    var uses24Hour: Bool
    var reduceMotion: Bool
    var appearance: Appearance
    var pureBlack = true         // dark finishes use a #000 room
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

    /// False when nothing moves until the next time change: the view then pauses the display
    /// link and renders once per second instead (Prose between rewrites).
    var wantsContinuousFrames: Bool { get }

    /// False for styles that never hold still (Lumen), which need no burn-in shift.
    var allowsBurnInShift: Bool { get }
}

extension ClockStyle {
    var wantsContinuousFrames: Bool { true }
    var allowsBurnInShift: Bool { true }
}

enum ClockStyles {
    static func make(_ id: StyleID, context: StyleContext) -> ClockStyle {
        switch id {
        case .hinge: return HingeRenderer(context: context)
        case .chorus: return ChorusRenderer(context: context)
        case .breath: return BreathRenderer(context: context)
        case .lumen: return LumenRenderer(context: context)
        case .prose: return ProseRenderer(context: context)
        case .slice: return SliceRenderer(context: context)
        case .poster: return PosterRenderer(context: context)
        case .module: return ModuleRenderer(context: context)
        }
    }
}
