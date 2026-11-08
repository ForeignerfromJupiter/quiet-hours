import Foundation

/// Listens for `com.apple.screensaver.willstop`. Since macOS 14 the `legacyScreenSaver` host often
/// keeps instances alive (and never calls `stopAnimation`) after the saver is dismissed, so this is
/// the reliable moment to stop frames and release resources (host workaround 1).
final class HostLifecycleObserver {
    private var token: NSObjectProtocol?

    init(onWillStop: @escaping () -> Void) {
        token = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screensaver.willstop"),
            object: nil, queue: .main
        ) { _ in onWillStop() }
    }

    func invalidate() {
        if let token { DistributedNotificationCenter.default().removeObserver(token) }
        token = nil
    }

    deinit { invalidate() }
}
