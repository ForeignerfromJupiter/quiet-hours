import Foundation

enum StyleID: String, CaseIterable {
    case hinge, chorus, breath, lumen

    var displayName: String {
        switch self {
        case .hinge: return "Hinge"
        case .chorus: return "Chorus"
        case .breath: return "Breath"
        case .lumen: return "Lumen"
        }
    }

    /// Styles built so far. Unbuilt styles fall back to Hinge.
    var isAvailable: Bool { self == .hinge }
}

/// Per-style finish. `.dark`/`.light` pin the style's dark or light finish.
enum FinishChoice: String, CaseIterable {
    case auto, dark, light
}

/// User options. Persisted in ScreenSaverDefaults (any UserDefaults in tests).
/// Re-read on every `startAnimation` because the host may not deliver changes to a running instance.
struct Settings: Equatable {
    var style: StyleID = .hinge
    var finishes: [StyleID: FinishChoice] = [:]
    var hourCycle: HourCycle = .system
    var showSeconds = false

    func finish(for style: StyleID) -> FinishChoice { finishes[style] ?? .auto }

    enum Key {
        static let style = "style"
        static let hourCycle = "hourCycle"
        static let showSeconds = "showSeconds"
        static func finish(_ s: StyleID) -> String { "finish.\(s.rawValue)" }
    }

    static func load(from defaults: UserDefaults) -> Settings {
        defaults.synchronize()   // pick up writes from other processes (configure sheet, Preview app)
        var s = Settings()
        if let raw = defaults.string(forKey: Key.style), let v = StyleID(rawValue: raw) { s.style = v }
        if let raw = defaults.string(forKey: Key.hourCycle), let v = HourCycle(rawValue: raw) { s.hourCycle = v }
        if defaults.object(forKey: Key.showSeconds) != nil { s.showSeconds = defaults.bool(forKey: Key.showSeconds) }
        for id in StyleID.allCases {
            if let raw = defaults.string(forKey: Key.finish(id)), let v = FinishChoice(rawValue: raw) {
                s.finishes[id] = v
            }
        }
        return s
    }

    func save(to defaults: UserDefaults) {
        defaults.set(style.rawValue, forKey: Key.style)
        defaults.set(hourCycle.rawValue, forKey: Key.hourCycle)
        defaults.set(showSeconds, forKey: Key.showSeconds)
        for id in StyleID.allCases {
            if let f = finishes[id] { defaults.set(f.rawValue, forKey: Key.finish(id)) }
            else { defaults.removeObject(forKey: Key.finish(id)) }
        }
        defaults.synchronize()
    }
}
