import ScreenSaver

/// The `.saver` principal class. Picks the style, drives frames, handles start/stop and appearance.
/// The Preview app hosts this same class.
@objc(QuietHoursView)
final class QuietHoursView: ScreenSaverView {

    // MARK: Preview-app hooks (defaults are what the real saver uses)

    /// Added to the wall clock. The Preview app's "Next minute" moves this forward.
    var timeOffset: TimeInterval = 0
    /// Use the macOS 12–13 frame path on a newer Mac, to exercise it.
    var forceCVDisplayLink = false
    /// >1 slows flips down for inspection.
    var timeScale: Double = 1
    /// Debug: hold every flip at this many seconds into its timeline.
    var freezeFlipAt: Double?
    /// The Preview app turns this off so the real saver stopping doesn't stop the preview.
    var followsHostLifecycle = true
    /// Called when the resolved appearance changes (Preview status line).
    var onAppearanceChange: (() -> Void)?

    // MARK: State

    let defaults: UserDefaults
    private(set) var settings = Settings()
    private(set) var finishAppearance: Appearance = .dark
    private(set) var systemIsDark = true
    private(set) var usingCVDisplayLink = false

    private var contentLayer: CALayer?
    private var style: ClockStyle?
    private var driver: FrameDriver?
    private var appearanceObserver: SystemAppearanceObserver?
    private var lifecycleObserver: HostLifecycleObserver?
    private var uses24Hour = false
    private var lastLinkTick: CFTimeInterval = 0
    private var running = false
    private let calendar = Calendar.autoupdatingCurrent

    static var moduleName: String {
        Bundle(for: QuietHoursView.self).bundleIdentifier ?? "com.ashik.quiethours.saver"
    }

    // MARK: Init

    override init?(frame: NSRect, isPreview: Bool) {
        defaults = ScreenSaverDefaults(forModuleWithName: Self.moduleName) ?? .standard
        super.init(frame: frame, isPreview: isPreview)
        commonInit()
    }

    required init?(coder: NSCoder) {
        defaults = ScreenSaverDefaults(forModuleWithName: Self.moduleName) ?? .standard
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = CGColor(gray: 0, alpha: 1)
        // ScreenSaverView's own timer only serves as a watchdog (see animateOneFrame).
        animationTimeInterval = 1.0 / 30
        Fonts.registerOnce()
    }

    override var isOpaque: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {}   // all drawing is in sublayers

    // Simple Options sheet for now; the full panel with live preview is Phase 5.
    private var optionsSheet: OptionsSheet?
    override var hasConfigureSheet: Bool { true }
    override var configureSheet: NSWindow? {
        if optionsSheet == nil { optionsSheet = OptionsSheet(view: self, defaults: defaults) }
        optionsSheet?.load()
        return optionsSheet?.window
    }

    // MARK: Start / stop

    override func startAnimation() {
        super.startAnimation()
        begin()
    }

    override func stopAnimation() {
        super.stopAnimation()
        end()
    }

    private func begin() {
        guard !running else { return }
        running = true

        // Host workaround 3: settings may have changed while an old instance lingered.
        settings = Settings.load(from: defaults)
        uses24Hour = TimeFormat.systemUses24Hour(settings.hourCycle)
        systemIsDark = AppearanceResolver.systemIsDark()
        finishAppearance = AppearanceResolver.resolve(settings.finish(for: settings.style), systemIsDark: systemIsDark)

        buildStyle()

        appearanceObserver = SystemAppearanceObserver { [weak self] dark in self?.systemAppearanceChanged(dark) }
        if followsHostLifecycle {
            // Host workaround 1: stop everything when the saver is dismissed, even if
            // stopAnimation never arrives.
            lifecycleObserver = HostLifecycleObserver { [weak self] in self?.hostWillStop() }
        }

        // Host workaround 2: the System Settings thumbnail runs at 30 fps.
        usingCVDisplayLink = forceCVDisplayLink || !Self.hasViewDisplayLink
        driver = FrameDrivers.make(for: self, maxFPS: isPreview ? 30 : nil,
                                   forceCVDisplayLink: forceCVDisplayLink) { [weak self] t in
            self?.lastLinkTick = CACurrentMediaTime()
            self?.tick(t)
        }
        lastLinkTick = CACurrentMediaTime()
        driver?.start()
        tick(CACurrentMediaTime())   // first frame immediately, no black flash
        onAppearanceChange?()
    }

    private func end() {
        guard running else { return }
        running = false
        driver?.stop(); driver = nil
        appearanceObserver?.invalidate(); appearanceObserver = nil
        lifecycleObserver?.invalidate(); lifecycleObserver = nil
        withoutActions { style?.stop() }
        style = nil
        contentLayer?.removeFromSuperlayer()
        contentLayer = nil
    }

    private func hostWillStop() {
        if isAnimating { stopAnimation() } else { end() }
    }

    private static var hasViewDisplayLink: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    private func buildStyle() {
        guard let host = layer else { return }
        let root = CALayer()
        root.isGeometryFlipped = true     // styles lay out top-left like the prototype's CSS
        root.masksToBounds = true
        root.frame = bounds
        host.addSublayer(root)
        contentLayer = root

        let ctx = StyleContext(isPreview: isPreview,
                               showSeconds: settings.showSeconds,
                               uses24Hour: uses24Hour,
                               reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                               appearance: finishAppearance,
                               timeScale: timeScale,
                               freezeFlipAt: freezeFlipAt)
        let s = ClockStyles.make(settings.style, context: ctx)
        withoutActions {
            s.start(in: root)
            s.layout(bounds: bounds, scale: backingScale)
        }
        style = s
    }

    // MARK: Frames

    private func tick(_ frameTime: CFTimeInterval) {
        guard running, let style else { return }
        let time = ClockTime(date: Date().addingTimeInterval(timeOffset), calendar: calendar, uses24Hour: uses24Hour)
        withoutActions { style.render(time: time, frameTime: frameTime) }
    }

    /// Watchdog: if the display link stops ticking (it has in some host states), keep the clock
    /// moving from ScreenSaverView's own 30 fps timer.
    override func animateOneFrame() {
        guard running else { return }
        let now = CACurrentMediaTime()
        if now - lastLinkTick > 0.25 { tick(now) }
    }

    // MARK: Layout

    private var backingScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        relayout()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        relayout()
    }

    private func relayout() {
        guard let contentLayer, let style else { return }
        withoutActions {
            contentLayer.frame = bounds
            style.layout(bounds: bounds, scale: backingScale)
        }
        tick(CACurrentMediaTime())
    }

    // MARK: Appearance

    private func systemAppearanceChanged(_ dark: Bool) {
        systemIsDark = dark
        let resolved = AppearanceResolver.resolve(settings.finish(for: settings.style), systemIsDark: dark)
        if resolved != finishAppearance {
            finishAppearance = resolved
            withoutActions { style?.appearanceDidChange(resolved) }
        }
        onAppearanceChange?()
    }

    // MARK: Preview-app API

    /// Saves settings and restarts so they are read back exactly as the saver would on start.
    func apply(_ newSettings: Settings) {
        newSettings.save(to: defaults)
        restart()
    }

    func restart() {
        if isAnimating {
            stopAnimation()
            startAnimation()
        } else {
            end()
            begin()
        }
    }

    /// Jumps to 40 ms past the next minute (cumulative), like the prototype.
    func skipToNextMinute() {
        let now = Date().addingTimeInterval(timeOffset)
        let c = calendar.dateComponents([.second, .nanosecond], from: now)
        let intoMinute = Double(c.second ?? 0) + Double(c.nanosecond ?? 0) / 1e9
        timeOffset += 60 - intoMinute + 0.04
    }

    func backToLive() { timeOffset = 0 }

    private func withoutActions(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    deinit {
        driver?.stop()
    }
}
