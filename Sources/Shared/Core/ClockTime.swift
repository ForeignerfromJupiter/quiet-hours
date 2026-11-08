import Foundation

/// How the user wants hours shown. `.system` follows the locale (and macOS's 24-hour switch).
enum HourCycle: String, CaseIterable {
    case system
    case h12
    case h24
}

/// A snapshot of the wall clock, already split into the digits the styles draw.
/// Pure value type: no UI, so it is unit-tested directly.
struct ClockTime: Equatable {
    let hour24: Int
    let minute: Int
    let second: Int
    let millisecond: Int
    let uses24Hour: Bool

    init(hour24: Int, minute: Int, second: Int, millisecond: Int = 0, uses24Hour: Bool) {
        self.hour24 = hour24
        self.minute = minute
        self.second = second
        self.millisecond = millisecond
        self.uses24Hour = uses24Hour
    }

    init(date: Date, calendar: Calendar, uses24Hour: Bool) {
        let c = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        self.init(hour24: c.hour ?? 0,
                  minute: c.minute ?? 0,
                  second: c.second ?? 0,
                  millisecond: (c.nanosecond ?? 0) / 1_000_000,
                  uses24Hour: uses24Hour)
    }

    var isPM: Bool { hour24 >= 12 }

    /// 0–23 in 24h mode, 1–12 in 12h mode.
    var displayHour: Int {
        if uses24Hour { return hour24 }
        let h = hour24 % 12
        return h == 0 ? 12 : h
    }

    /// The four HHMM slots. In 12h mode a leading zero is `nil` (the card hides entirely);
    /// in 24h mode it is shown as "0", matching the prototype.
    var digits: [Character?] {
        let h = displayHour
        let tens: Character? = (h < 10 && !uses24Hour) ? nil : Self.digit(h / 10)
        return [tens, Self.digit(h % 10), Self.digit(minute / 10), Self.digit(minute % 10)]
    }

    /// Seconds as two characters, always zero-padded.
    var secondDigits: [Character] { [Self.digit(second / 10), Self.digit(second % 10)] }

    /// "AM"/"PM" in 12h mode, nil in 24h mode.
    var meridiem: String? { uses24Hour ? nil : (isPM ? "PM" : "AM") }

    private static func digit(_ n: Int) -> Character {
        Character(String(n))
    }
}

/// Decides 12h vs 24h.
enum TimeFormat {
    /// True when the locale's preferred hour pattern ("j" skeleton) is a 24-hour one.
    static func localeUses24Hour(_ locale: Locale) -> Bool {
        let pattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "H"
        let symbols = unquoted(pattern)
        return !(symbols.contains("h") || symbols.contains("K") || symbols.contains("a"))
    }

    /// Resolves the setting to a concrete answer.
    /// - Parameters:
    ///   - force24 / force12: macOS's "24-hour time" switch as stored in the global domain
    ///     (`AppleICUForce24HourTime` / `AppleICUForce12HourTime`), nil when unset.
    static func uses24Hour(_ cycle: HourCycle,
                           locale: Locale,
                           force24: Bool?,
                           force12: Bool?) -> Bool {
        switch cycle {
        case .h12: return false
        case .h24: return true
        case .system:
            if force24 == true { return true }
            if force12 == true { return false }
            return localeUses24Hour(locale)
        }
    }

    /// Reads the live system state.
    static func systemUses24Hour(_ cycle: HourCycle) -> Bool {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        return uses24Hour(cycle,
                          locale: .autoupdatingCurrent,
                          force24: globalBool("AppleICUForce24HourTime"),
                          force12: globalBool("AppleICUForce12HourTime"))
    }

    private static func globalBool(_ key: String) -> Bool? {
        guard let v = CFPreferencesCopyAppValue(key as CFString, kCFPreferencesAnyApplication) else { return nil }
        return (v as? NSNumber)?.boolValue
    }

    /// Drops 'quoted literal' runs from a date pattern.
    private static func unquoted(_ pattern: String) -> String {
        var out = ""
        var inQuote = false
        for ch in pattern {
            if ch == "'" { inQuote.toggle(); continue }
            if !inQuote { out.append(ch) }
        }
        return out
    }
}
