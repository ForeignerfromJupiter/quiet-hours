import AppKit
import CoreVideo
import QuartzCore

/// Calls `tick(frameTime)` once per display refresh on the main thread.
/// `frameTime` is in the `CACurrentMediaTime()` time base.
///
/// Neither driver retains the view: the display link retains a small proxy that holds the
/// tick closure, and the closure is expected to capture the view weakly (host workaround 4).
protocol FrameDriver: AnyObject {
    func start()
    func stop()
}

enum FrameDrivers {
    /// `NSView.displayLink` on macOS 14+, `CVDisplayLink` below (or when forced, for testing that path).
    static func make(for view: NSView,
                     maxFPS: Int?,
                     forceCVDisplayLink: Bool,
                     tick: @escaping (CFTimeInterval) -> Void) -> FrameDriver {
        if #available(macOS 14.0, *), !forceCVDisplayLink {
            return ViewDisplayLinkDriver(view: view, maxFPS: maxFPS, tick: tick)
        }
        return CVDisplayLinkDriver(view: view, maxFPS: maxFPS, tick: tick)
    }
}

// MARK: - macOS 14+

@available(macOS 14.0, *)
private final class ViewDisplayLinkDriver: FrameDriver {
    private final class Proxy: NSObject {
        let tick: (CFTimeInterval) -> Void
        init(tick: @escaping (CFTimeInterval) -> Void) { self.tick = tick }
        @objc func step(_ link: CADisplayLink) { tick(link.targetTimestamp) }
    }

    private weak var view: NSView?
    private let proxy: Proxy
    private let maxFPS: Int?
    private var link: CADisplayLink?

    init(view: NSView, maxFPS: Int?, tick: @escaping (CFTimeInterval) -> Void) {
        self.view = view
        self.maxFPS = maxFPS
        self.proxy = Proxy(tick: tick)
    }

    func start() {
        guard link == nil, let view else { return }
        let l = view.displayLink(target: proxy, selector: #selector(Proxy.step(_:)))
        if let maxFPS {
            let f = Float(maxFPS)
            l.preferredFrameRateRange = CAFrameRateRange(minimum: f / 2, maximum: f, preferred: f)
        }
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()   // releases the proxy
        link = nil
    }

    deinit { stop() }
}

// MARK: - macOS 12–13

private final class CVDisplayLinkDriver: FrameDriver {
    /// Shared between the CVDisplayLink thread and main. Retained by the link's callback context
    /// while running; coalesces so a slow main thread never builds a queue of frames.
    private final class Box {
        let tick: (CFTimeInterval) -> Void
        let minInterval: CFTimeInterval
        private let lock = NSLock()
        private var pending = false
        private var lastFire: CFTimeInterval = 0
        var active = true

        init(tick: @escaping (CFTimeInterval) -> Void, minInterval: CFTimeInterval) {
            self.tick = tick
            self.minInterval = minInterval
        }

        func fire(at time: CFTimeInterval) {
            lock.lock()
            if pending || time - lastFire < minInterval * 0.9 { lock.unlock(); return }
            pending = true
            lastFire = time
            lock.unlock()
            DispatchQueue.main.async { [self] in
                lock.lock(); pending = false; lock.unlock()
                if active { tick(time) }
            }
        }
    }

    private weak var view: NSView?
    private let box: Box
    private var link: CVDisplayLink?
    private var boxRef: Unmanaged<Box>?
    private var screenObserver: NSObjectProtocol?

    private static let hostTicksToSeconds: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()

    init(view: NSView, maxFPS: Int?, tick: @escaping (CFTimeInterval) -> Void) {
        self.view = view
        self.box = Box(tick: tick, minInterval: maxFPS.map { 1.0 / Double($0) } ?? 0)
    }

    func start() {
        guard link == nil else { return }
        var l: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&l) == kCVReturnSuccess, let l else { return }
        box.active = true
        let ref = Unmanaged.passRetained(box)
        boxRef = ref
        CVDisplayLinkSetOutputCallback(l, { _, _, outTime, _, _, ctx in
            guard let ctx else { return kCVReturnSuccess }
            let box = Unmanaged<Box>.fromOpaque(ctx).takeUnretainedValue()
            let t = Double(outTime.pointee.hostTime) * CVDisplayLinkDriver.hostTicksToSeconds
            box.fire(at: t)
            return kCVReturnSuccess
        }, ref.toOpaque())
        link = l
        bindToViewScreen()
        CVDisplayLinkStart(l)
        if let window = view?.window {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeScreenNotification, object: window, queue: .main
            ) { [weak self] _ in self?.bindToViewScreen() }
        }
    }

    private func bindToViewScreen() {
        guard let link,
              let number = view?.window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return }
        CVDisplayLinkSetCurrentCGDisplay(link, CGDirectDisplayID(number.uint32Value))
    }

    func stop() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        box.active = false
        if let link {
            CVDisplayLinkStop(link)   // returns after any in-flight callback has finished
        }
        link = nil
        boxRef?.release()
        boxRef = nil
    }

    deinit { stop() }
}
