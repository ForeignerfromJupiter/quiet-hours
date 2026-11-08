import Foundation

/// Board's world-time data (prototype `BOARD_CITIES` and `Board.frame`). Pure: everything is
/// computed from a `Date` and `TimeZone`s through `Calendar`, so daylight saving always comes from
/// the system time zone database. Unit-tested with fixed dates either side of DST changes.
enum BoardModel {
    struct City: Equatable {
        let name: String
        let zoneID: String
        /// Other identifiers the tz database uses for the same zone (so a Mac set to "GB" still
        /// counts as London).
        var aliases: [String] = []

        var zone: TimeZone { TimeZone(identifier: zoneID) ?? TimeZone(secondsFromGMT: 0)! }

        func matches(_ local: TimeZone) -> Bool {
            local.identifier == zoneID || aliases.contains(local.identifier)
        }
    }

    enum Day: String, Equatable {
        case yesterday = "YESTERDAY", today = "TODAY", tomorrow = "TOMORROW"
    }

    struct Row: Equatable {
        let city: String
        let offsetMinutes: Int
        /// "−5h 30m", "+3h", "+0h" (U+2212 minus, as in the prototype).
        let offset: String
        let day: Day
        /// 09:00 ≤ local hour there < 18:00.
        let working: Bool
        /// "10:09 PM" in 12h mode, "22:09" in 24h mode.
        let time: String
    }

    struct Header: Equatable {
        /// "KOLKATA"
        let city: String
        /// "10:09" (12h, no meridiem) or "22:09"
        let time: String
        /// "SUNDAY 08 NOVEMBER"
        let date: String
        /// "PM · UTC+5:30" (12h) or "UTC+5:30" (24h), then " · 55" with seconds on.
        let sub: String
    }

    /// The prototype's six cities, then Dubai as the substitute.
    static let roster: [City] = [
        City(name: "London", zoneID: "Europe/London", aliases: ["GB", "GB-Eire", "Europe/Belfast"]),
        City(name: "New York", zoneID: "America/New_York", aliases: ["US/Eastern", "EST5EDT"]),
        City(name: "San Francisco", zoneID: "America/Los_Angeles", aliases: ["US/Pacific", "PST8PDT"]),
        City(name: "Berlin", zoneID: "Europe/Berlin"),
        City(name: "Tokyo", zoneID: "Asia/Tokyo", aliases: ["Japan"]),
        City(name: "Sydney", zoneID: "Australia/Sydney", aliases: ["Australia/NSW", "Australia/ACT", "Australia/Canberra"]),
        City(name: "Dubai", zoneID: "Asia/Dubai"),
    ]

    static let rowCount = 6

    /// The six cities shown: the roster minus the local zone's city (Dubai then moves up).
    static func cities(local: TimeZone) -> [City] {
        Array(roster.filter { !$0.matches(local) }.prefix(rowCount))
    }

    /// "Asia/Kolkata" → "Kolkata", "America/New_York" → "New York" (prototype `localCity`).
    static func localCityName(_ zone: TimeZone) -> String {
        let last = zone.identifier.split(separator: "/").last.map(String.init) ?? ""
        let name = last.replacingOccurrences(of: "_", with: " ")
        if name.isEmpty { return "Local" }
        return name == "Calcutta" ? "Kolkata" : name
    }

    // MARK: Per-zone values

    static func calendar(_ zone: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }

    /// Minutes `zone` is ahead of `local` at `date` (negative when behind).
    static func offsetMinutes(_ zone: TimeZone, from local: TimeZone, at date: Date) -> Int {
        (zone.secondsFromGMT(for: date) - local.secondsFromGMT(for: date)) / 60
    }

    /// Prototype: `(om>=0?'+':'−')+floor(|om|/60)+'h'+(|om|%60?' '+(|om|%60)+'m':'')`.
    static func formatOffset(minutes: Int) -> String {
        let a = abs(minutes)
        return (minutes >= 0 ? "+" : "\u{2212}") + "\(a / 60)h" + (a % 60 != 0 ? " \(a % 60)m" : "")
    }

    /// "UTC+5:30", "UTC-5", "UTC+0" (prototype header sub line).
    static func utcLabel(_ zone: TimeZone, at date: Date) -> String {
        let m = zone.secondsFromGMT(for: date) / 60, a = abs(m)
        return "UTC" + (m >= 0 ? "+" : "-") + "\(a / 60)" + (a % 60 != 0 ? String(format: ":%02d", a % 60) : "")
    }

    /// The calendar day in `zone` compared with the one in `local`.
    static func day(_ zone: TimeZone, relativeTo local: TimeZone, at date: Date) -> Day {
        func ymd(_ tz: TimeZone) -> Int {
            let c = calendar(tz).dateComponents([.year, .month, .day], from: date)
            return (c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0)
        }
        let there = ymd(zone), here = ymd(local)
        return there > here ? .tomorrow : there < here ? .yesterday : .today
    }

    static func isWorkingHours(_ zone: TimeZone, at date: Date) -> Bool {
        let h = calendar(zone).component(.hour, from: date)
        return h >= 9 && h < 18
    }

    /// The wall time in `zone`: "22:09" (24h, zero-padded), "10:09" or "10:09 PM" (12h, en-US).
    static func time(_ zone: TimeZone, at date: Date, uses24Hour: Bool, meridiem: Bool) -> String {
        let c = calendar(zone).dateComponents([.hour, .minute], from: date)
        let h = c.hour ?? 0, m = c.minute ?? 0
        if uses24Hour { return String(format: "%02d:%02d", h, m) }
        let h12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d", h12, m) + (meridiem ? (h >= 12 ? " PM" : " AM") : "")
    }

    /// "SUNDAY 08 NOVEMBER" (prototype: en-GB weekday long, day 2-digit, month long, uppercased).
    static func dateLine(_ zone: TimeZone, at date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.calendar = calendar(zone)
        f.timeZone = zone
        f.dateFormat = "EEEE dd MMMM"
        return f.string(from: date).uppercased()
    }

    // MARK: Board

    static func header(local: TimeZone, at date: Date, uses24Hour: Bool, showSeconds: Bool) -> Header {
        var sub = utcLabel(local, at: date)
        if !uses24Hour {
            let h = calendar(local).component(.hour, from: date)
            sub = (h >= 12 ? "PM" : "AM") + " · " + sub
        }
        if showSeconds {
            sub += String(format: " · %02d", calendar(local).component(.second, from: date))
        }
        return Header(city: localCityName(local).uppercased(),
                      time: time(local, at: date, uses24Hour: uses24Hour, meridiem: false),
                      date: dateLine(local, at: date),
                      sub: sub)
    }

    static func rows(local: TimeZone, at date: Date, uses24Hour: Bool) -> [Row] {
        cities(local: local).map { city in
            let zone = city.zone
            let om = offsetMinutes(zone, from: local, at: date)
            return Row(city: city.name, offsetMinutes: om, offset: formatOffset(minutes: om),
                       day: day(zone, relativeTo: local, at: date),
                       working: isWorkingHours(zone, at: date),
                       time: time(zone, at: date, uses24Hour: uses24Hour, meridiem: true))
        }
    }

    // MARK: Scramble

    /// Prototype `scramble`: digit j shows random digits until 160 + 70·j ms; the line settles
    /// after 160 + 70·len ms.
    static let scrambleLead = 0.160, scrambleStep = 0.070
    /// The header starts at once; row i starts 120 + 90·i ms later.
    static let rowLead = 0.120, rowStep = 0.090

    static func scrambleDuration(_ text: String) -> Double {
        scrambleLead + Double(text.count) * scrambleStep
    }

    /// The text to show `elapsed` seconds into a scramble (nil once settled). The random digits
    /// change 60 times a second whatever the refresh rate, and are a pure function of
    /// (seed, position, tick) so the motion is the same on every display.
    static func scrambled(_ target: String, elapsed: Double, seed: Int) -> String? {
        guard elapsed <= scrambleDuration(target) else { return nil }
        let tick = Int((max(elapsed, 0) * 60).rounded(.down))
        var out = ""
        for (j, ch) in target.enumerated() {
            if ch.isASCII, ch.isNumber, elapsed < scrambleLead + Double(j) * scrambleStep {
                out.append(Character(String(randomDigit(seed: seed, slot: j, tick: tick))))
            } else {
                out.append(ch)
            }
        }
        return out
    }

    static func randomDigit(seed: Int, slot: Int, tick: Int) -> Int {
        var x = UInt64(bitPattern: Int64(seed &* 7919 &+ slot &* 104_729 &+ tick &* 15_485_863))
        x = (x ^ (x >> 30)) &* 0xbf58_476d_1ce4_e5b9
        x = (x ^ (x >> 27)) &* 0x94d0_49bb_1331_11eb
        x ^= x >> 31
        return Int(x % 10)
    }
}
