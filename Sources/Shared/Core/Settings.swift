import Foundation

enum StyleID: String, CaseIterable {
    case hinge, chorus, breath, lumen, prose, slice, poster, module, echo, shutter, ticker, specimen, board

    var displayName: String {
        switch self {
        case .hinge: return "Hinge"
        case .chorus: return "Chorus"
        case .breath: return "Breath"
        case .lumen: return "Lumen"
        case .prose: return "Prose"
        case .slice: return "Slice"
        case .poster: return "Poster"
        case .module: return "Module"
        case .board: return "Board"
        case .specimen: return "Specimen"
        case .ticker: return "Ticker"
        case .shutter: return "Shutter"
        case .echo: return "Echo"
        }
    }

    /// Styles built so far.
    var isAvailable: Bool { true }

    /// Names of the style's dark and light finishes.
    var finishNames: (dark: String, light: String) {
        switch self {
        case .hinge: return ("Graphite", "Ivory")
        case .chorus: return ("Night", "Paper")
        case .breath: return ("Graphite", "Paper")
        case .lumen: return ("Night", "Paper")
        case .prose, .slice, .poster, .module, .echo, .shutter, .ticker, .specimen, .board: return ("Night", "Paper")
        }
    }
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
    /// Dark finishes use a #000 room (OLED: pixels off). On by default.
    var pureBlack = true
    /// false = only the main display shows the clock; the others stay black.
    var allDisplays = true
    /// 0…0.6: darkens the whole saver.
    var dim = 0.0

    func finish(for style: StyleID) -> FinishChoice { finishes[style] ?? .auto }

    enum Key {
        static let style = "style"
        static let hourCycle = "hourCycle"
        static let showSeconds = "showSeconds"
        static let pureBlack = "pureBlack"
        static let allDisplays = "allDisplays"
        static let dim = "dim"
        static func finish(_ s: StyleID) -> String { "finish.\(s.rawValue)" }
    }

    static func load(from defaults: UserDefaults) -> Settings {
        defaults.synchronize()   // pick up writes from other processes (configure sheet, Preview app)
        var s = Settings()
        if let raw = defaults.string(forKey: Key.style), let v = StyleID(rawValue: raw) { s.style = v }
        if let raw = defaults.string(forKey: Key.hourCycle), let v = HourCycle(rawValue: raw) { s.hourCycle = v }
        if defaults.object(forKey: Key.showSeconds) != nil { s.showSeconds = defaults.bool(forKey: Key.showSeconds) }
        if defaults.object(forKey: Key.pureBlack) != nil { s.pureBlack = defaults.bool(forKey: Key.pureBlack) }
        if defaults.object(forKey: Key.allDisplays) != nil { s.allDisplays = defaults.bool(forKey: Key.allDisplays) }
        if defaults.object(forKey: Key.dim) != nil { s.dim = min(max(defaults.double(forKey: Key.dim), 0), 0.6) }
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
        defaults.set(pureBlack, forKey: Key.pureBlack)
        defaults.set(allDisplays, forKey: Key.allDisplays)
        defaults.set(dim, forKey: Key.dim)
        for id in StyleID.allCases {
            if let f = finishes[id] { defaults.set(f.rawValue, forKey: Key.finish(id)) }
            else { defaults.removeObject(forKey: Key.finish(id)) }
        }
        defaults.synchronize()
    }
}
