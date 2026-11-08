import AppKit

/// Hosts QuietHoursView in a resizable window with the controls we iterate with.
/// Every change is written to the view's ScreenSaverDefaults and the view is restarted,
/// so settings travel the same path as in the real saver.
final class PreviewWindowController: NSWindowController, NSWindowDelegate {
    private let saverView: QuietHoursView
    private let bar = NSStackView()

    private let stylePopup = NSPopUpButton()
    private let finishControl = NSSegmentedControl(labels: ["Auto", "Dark", "Light"], trackingMode: .selectOne, target: nil, action: nil)
    private let hourControl = NSSegmentedControl(labels: ["System", "12h", "24h"], trackingMode: .selectOne, target: nil, action: nil)
    private let secondsCheck = NSButton(checkboxWithTitle: "Seconds", target: nil, action: nil)
    private let nextMinuteButton = NSButton(title: "Next minute", target: nil, action: nil)
    private let liveButton = NSButton(title: "Back to live", target: nil, action: nil)
    private let slowCheck = NSButton(checkboxWithTitle: "Slow ×10", target: nil, action: nil)
    private let cvCheck = NSButton(checkboxWithTitle: "CVDisplayLink", target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")

    private static let finishes: [FinishChoice] = [.auto, .dark, .light]
    private static let hours: [HourCycle] = [.system, .h12, .h24]

    init() {
        saverView = QuietHoursView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800), isPreview: false)!
        saverView.followsHostLifecycle = false

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 850),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Quiet Hours Preview"
        window.collectionBehavior = [.fullScreenPrimary]
        window.minSize = NSSize(width: 480, height: 320)
        window.setFrameAutosaveName("QuietHoursPreview")
        super.init(window: window)
        window.delegate = self
        if !window.setFrameUsingName("QuietHoursPreview") { window.center() }
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        for id in StyleID.allCases {
            stylePopup.addItem(withTitle: id.isAvailable ? id.displayName : "\(id.displayName) (later phase)")
            stylePopup.lastItem?.representedObject = id.rawValue
            stylePopup.lastItem?.isEnabled = id.isAvailable
        }
        stylePopup.autoenablesItems = false

        for (control, action) in [(stylePopup as NSControl, #selector(settingsChanged)),
                                  (finishControl, #selector(settingsChanged)),
                                  (hourControl, #selector(settingsChanged)),
                                  (secondsCheck, #selector(settingsChanged)),
                                  (nextMinuteButton, #selector(nextMinute)),
                                  (liveButton, #selector(backToLive)),
                                  (slowCheck, #selector(debugChanged)),
                                  (cvCheck, #selector(debugChanged))] {
            control.target = self
            control.action = action
        }
        nextMinuteButton.keyEquivalent = "n"
        nextMinuteButton.keyEquivalentModifierMask = []
        nextMinuteButton.toolTip = "Jump to the next minute (N)"
        slowCheck.toolTip = "Run flips ten times slower"
        cvCheck.toolTip = "Drive frames with CVDisplayLink (the macOS 12–13 path)"
        status.textColor = .secondaryLabelColor
        status.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        bar.orientation = .horizontal
        bar.spacing = 10
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        for v in [stylePopup, finishControl, hourControl, secondsCheck, nextMinuteButton, liveButton,
                  slowCheck, cvCheck, spacer, status] as [NSView] {
            bar.addArrangedSubview(v)
        }

        let stack = NSStackView(views: [bar, saverView])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .width
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        saverView.setContentHuggingPriority(.init(1), for: .vertical)

        saverView.onAppearanceChange = { [weak self] in self?.updateStatus() }
    }

    func startClock() {
        // Debug launch arguments, e.g. `-QHTimeScale 10 -QHFlipIn 2`:
        // slow flips down and land the next minute change N seconds after launch.
        let args = UserDefaults.standard
        if args.double(forKey: "QHTimeScale") > 0 {
            saverView.timeScale = args.double(forKey: "QHTimeScale")
            slowCheck.state = saverView.timeScale > 1 ? .on : .off
        }
        // `-QHTime 20:06` or `-QHTime 20:07:58` starts the clock at that time.
        if let hm = args.string(forKey: "QHTime")?.split(separator: ":").compactMap({ Int($0) }), hm.count >= 2 {
            let cal = Calendar.current
            let target = cal.date(bySettingHour: hm[0], minute: hm[1], second: hm.count > 2 ? hm[2] : 0, of: Date()) ?? Date()
            saverView.timeOffset = target.timeIntervalSinceNow
        }
        saverView.logFrameStats = args.bool(forKey: "QHFrameStats")
        if args.bool(forKey: "QHFullScreen") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.window?.toggleFullScreen(nil) }
        }
        if args.object(forKey: "QHFreeze") != nil {
            saverView.freezeFlipAt = args.double(forKey: "QHFreeze")
        }
        if args.object(forKey: "QHFlipIn") != nil {
            let c = Calendar.current.dateComponents([.second, .nanosecond], from: Date())
            let intoMinute = Double(c.second ?? 0) + Double(c.nanosecond ?? 0) / 1e9
            saverView.timeOffset = 60 - intoMinute - args.double(forKey: "QHFlipIn")
        }
        if !saverView.isAnimating { saverView.startAnimation() }
        syncControls()
        updateStatus()
    }

    // MARK: Actions

    @objc private func settingsChanged() {
        var s = saverView.settings
        if let raw = stylePopup.selectedItem?.representedObject as? String, let id = StyleID(rawValue: raw) { s.style = id }
        s.finishes[s.style] = Self.finishes[max(0, finishControl.selectedSegment)]
        s.hourCycle = Self.hours[max(0, hourControl.selectedSegment)]
        s.showSeconds = secondsCheck.state == .on
        saverView.apply(s)
        syncControls()
        updateStatus()
    }

    @objc private func debugChanged() {
        saverView.timeScale = slowCheck.state == .on ? 10 : 1
        saverView.forceCVDisplayLink = cvCheck.state == .on
        saverView.restart()
        updateStatus()
    }

    @objc private func nextMinute() {
        saverView.skipToNextMinute()
        updateStatus()
    }

    @objc private func backToLive() {
        saverView.backToLive()
        updateStatus()
    }

    private func syncControls() {
        let s = saverView.settings
        if let i = StyleID.allCases.firstIndex(of: s.style) { stylePopup.selectItem(at: i) }
        finishControl.selectedSegment = Self.finishes.firstIndex(of: s.finish(for: s.style)) ?? 0
        hourControl.selectedSegment = Self.hours.firstIndex(of: s.hourCycle) ?? 0
        secondsCheck.state = s.showSeconds ? .on : .off
    }

    private func updateStatus() {
        let system = saverView.systemIsDark ? "dark" : "light"
        let names = saverView.settings.style.finishNames
        let finish = saverView.finishAppearance == .dark ? names.dark : names.light
        let driver = saverView.usingCVDisplayLink ? "CVDisplayLink" : "NSView.displayLink"
        var text = "System \(system) → \(finish) · \(driver)"
        if saverView.timeOffset != 0 { text += " · previewing another time" }
        status.stringValue = text
        liveButton.isEnabled = saverView.timeOffset != 0
    }

    // MARK: Full screen: hide the controls

    func windowWillEnterFullScreen(_ notification: Notification) { bar.isHidden = true }
    func windowWillExitFullScreen(_ notification: Notification) { bar.isHidden = false }
}
