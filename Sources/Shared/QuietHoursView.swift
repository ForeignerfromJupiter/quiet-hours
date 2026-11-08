import ScreenSaver

/// The principal class of every `.saver` (NSPrincipalClass = `<Module>.QuietHoursView`).
/// Each saver is its own Swift module, so the five can share one host process without their
/// Objective-C class names clashing. Picks the style, drives frames, handles start/stop and
/// appearance. The Preview app hosts this same class.
final class QuietHoursView: ScreenSaverView {

    // MARK: Preview-app hooks (defaults are what the real saver uses)

    /// Added to the wall clock. The Preview app's "Next minute" moves this forward.
    var timeOffset: TimeInterval = 0
    /// Use the macOS 12–13 frame path on a newer Mac, to exercise it.
    var forceCVDisplayLink = false
    /// >1 slows flips down for inspection.
    var timeScale: Double = 1
    /// Debug: log frame pacing for each burst of continuous frames (Preview `-QHFrameStats YES`).
    var logFrameStats = false
    private var stats = (frames: 0, slow: 0, worst: 0.0, last: 0.0, busy: 0.0, first: 0.0)

    /// The display's maximum refresh rate (what the frame driver asks for), for the Preview status.
    var refreshRate: Int { isPreview ? min(30, FrameDrivers.nativeFPS(of: self)) : FrameDrivers.nativeFPS(of: self) }
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
    private var idle = false          // display link paused; one render per second
    private var burnInOffset = CGPoint.zero
    private var idleTimer: Timer?
    private var running = false
    private let calendar = Calendar.autoupdatingCurrent

    static var moduleName: String {
        Bundle(for: QuietHoursView.self).bundleIdentifier ?? "com.ashik.quiethours"
    }

    /// The style this bundle is locked to (`QHStyle` in each saver's Info.plist); nil in the
    /// Preview app, which lets you pick.
    static let fixedStyle: StyleID? =
        (Bundle(for: QuietHoursView.self).object(forInfoDictionaryKey: "QHStyle") as? String).flatMap(StyleID.init(rawValue:))

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
        if optionsSheet == nil { optionsSheet = OptionsSheet(view: self, defaults: defaults, fixedStyle: Self.fixedStyle) }
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
        if let fixed = Self.fixedStyle { settings.style = fixed }
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
        idleTimer?.invalidate(); idleTimer = nil; idle = false
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
                               pureBlack: settings.pureBlack,
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
        let work = CACurrentMediaTime()
        withoutActions {
            style.render(time: time, frameTime: frameTime)
            applyBurnInShift()
        }
        if logFrameStats && !idle { recordFrame(at: work, frameTime: frameTime) }
        updateIdle()
    }

    /// Counts frames that missed a refresh (interval over 1.5 × this display's budget, so 12.5 ms
    /// at 120 Hz, 10.4 ms at 144 Hz) and the CPU time spent rendering. Logs every 5 s and when a
    /// style goes idle.
    /// Intervals come from the display link's target timestamps (when frames reach the screen),
    /// not from when the main thread happened to run.
    private func recordFrame(at start: CFTimeInterval, frameTime now: CFTimeInterval) {
        stats.busy += CACurrentMediaTime() - start
        if stats.last > 0 {
            let dt = (now - stats.last) * 1000
            stats.frames += 1
            if dt > 1500 / Double(refreshRate) { stats.slow += 1 }
            stats.worst = max(stats.worst, dt)
        } else {
            stats.first = now
        }
        stats.last = now
        if now - stats.first >= 5 { flushStats() }
    }

    private func flushStats() {
        guard stats.frames > 0 else { return }
        let fps = Double(stats.frames) / max(stats.last - stats.first, 0.001)
        NSLog("QuietHours frames @%d Hz: %d frames, %.1f fps, missed: %d, worst %.1f ms, render CPU %.2f ms/frame",
              refreshRate, stats.frames, fps, stats.slow, stats.worst, stats.busy * 1000 / Double(stats.frames))
        stats = (0, 0, 0, 0, 0, 0)
    }
    /// Moves the whole clock a few pixels over minutes (OLED burn-in protection). Pixel-snapped,
    /// so it only changes every several seconds and text never resamples soft.
    private func applyBurnInShift() {
        guard let contentLayer, let style else { return }
        let offset = style.allowsBurnInShift
            ? Room.burnInOffset(at: Date().timeIntervalSinceReferenceDate, size: bounds.size, scale: backingScale)
            : .zero
        guard offset != burnInOffset else { return }
        burnInOffset = offset
        contentLayer.sublayerTransform = CATransform3DMakeTranslation(offset.x, offset.y, 0)
    }

    /// Styles that are still between transitions (Prose) get no frames: the display link pauses
    /// and a timer renders once per second, on the second, until the style moves again.
    private func updateIdle() {
        guard running, let style else { return }
        let wantsIdle = !style.wantsContinuousFrames
        if wantsIdle && !idle {
            if logFrameStats { flushStats() }
            stats = (0, 0, 0, 0, 0, 0)
            idle = true
            driver?.setPaused(true)
            scheduleIdleTick()
        } else if !wantsIdle && idle {
            idle = false
            idleTimer?.invalidate(); idleTimer = nil
            lastLinkTick = CACurrentMediaTime()
            driver?.setPaused(false)
        }
    }

    private func scheduleIdleTick() {
        idleTimer?.invalidate()
        let now = Date().addingTimeInterval(timeOffset).timeIntervalSinceReferenceDate
        let delay = 1 - now.truncatingRemainder(dividingBy: 1) + 0.002
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, self.idle else { return }
            self.tick(CACurrentMediaTime())
            if self.idle { self.scheduleIdleTick() }
        }
        timer.tolerance = 0.004
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    /// Watchdog: if the display link stops ticking (it has in some host states), keep the clock
    /// moving from ScreenSaverView's own 30 fps timer.
    override func animateOneFrame() {
        guard running, !idle else { return }
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
        tick(CACurrentMediaTime())   // an idle style wakes now, not at the next second
    }

    /// Jumps to 40 ms past the next full hour (Poster re-composes every hour).
    func skipToNextHour() {
        let now = Date().addingTimeInterval(timeOffset)
        let c = calendar.dateComponents([.minute, .second, .nanosecond], from: now)
        let intoHour = Double(c.minute ?? 0) * 60 + Double(c.second ?? 0) + Double(c.nanosecond ?? 0) / 1e9
        timeOffset += 3600 - intoHour + 0.04
        tick(CACurrentMediaTime())
    }

    func backToLive() {
        timeOffset = 0
        tick(CACurrentMediaTime())
    }

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
