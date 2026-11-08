import Foundation

enum Appearance: String {
    case dark, light
}

/// Resolves Auto to dark or light from the global `AppleInterfaceStyle` key.
/// We deliberately do not use `effectiveAppearance`: the screensaver host may never update it.
enum AppearanceResolver {
    static func resolve(_ choice: FinishChoice, systemIsDark: Bool) -> Appearance {
        switch choice {
        case .dark: return .dark
        case .light: return .light
        case .auto: return systemIsDark ? .dark : .light
        }
    }

    /// `AppleInterfaceStyle` is "Dark" in dark mode and absent in light mode.
    static func isDark(interfaceStyle: String?) -> Bool {
        interfaceStyle?.caseInsensitiveCompare("Dark") == .orderedSame
    }

    /// Reads the live value. Synchronizes first so a sandboxed host does not serve a cached value.
    static func systemIsDark() -> Bool {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let v = CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication)
        return isDark(interfaceStyle: v as? String)
    }
}

/// Watches `AppleInterfaceThemeChangedNotification` and reports the new dark/light state.
/// Holds no reference to the view; the caller passes a closure that captures it weakly.
final class SystemAppearanceObserver {
    private var token: NSObjectProtocol?
    private let onChange: (Bool) -> Void
    private var generation = 0

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        token = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in self?.themeChanged() }
    }

    private func themeChanged() {
        onChange(AppearanceResolver.systemIsDark())
        // The preference write can land a moment after the notification; read once more.
        generation += 1
        let g = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.generation == g else { return }
            self.onChange(AppearanceResolver.systemIsDark())
        }
    }

    func invalidate() {
        if let token { DistributedNotificationCenter.default().removeObserver(token) }
        token = nil
        generation += 1
    }

    deinit { invalidate() }
}
