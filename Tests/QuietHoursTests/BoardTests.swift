import XCTest
@testable import QuietHoursPreview

/// Board's world-time data with fixed dates, including both sides of the 2026 daylight-saving
/// changes (US: Mar 8 / Nov 1; EU: Mar 29 / Oct 25; Sydney: Apr 5 / Oct 4).
final class BoardModelTests: XCTestCase {
    private let kolkata = TimeZone(identifier: "Asia/Kolkata")!
    private let newYork = TimeZone(identifier: "America/New_York")!
    private let minus = "\u{2212}"

    /// A UTC instant: "2026-03-07 12:00".
    private func utc(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    private func offsets(_ local: TimeZone, _ date: String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: BoardModel.rows(local: local, at: utc(date), uses24Hour: true).map { ($0.city, $0.offset) })
    }

    private func row(_ city: String, local: TimeZone, _ date: String, uses24Hour: Bool = true) -> BoardModel.Row {
        BoardModel.rows(local: local, at: utc(date), uses24Hour: uses24Hour).first { $0.city == city }!
    }

    // MARK: Cities

    func testEveryRosterZoneExists() {
        for c in BoardModel.roster {
            XCTAssertNotNil(TimeZone(identifier: c.zoneID), c.zoneID)
            for a in c.aliases { XCTAssertNotNil(TimeZone(identifier: a), a) }
        }
    }

    func testCityListAndDubaiSubstitute() {
        let names = { (id: String) in BoardModel.cities(local: TimeZone(identifier: id)!).map(\.name) }
        let six = ["London", "New York", "San Francisco", "Berlin", "Tokyo", "Sydney"]
        XCTAssertEqual(names("Asia/Kolkata"), six)
        XCTAssertEqual(names("Asia/Dubai"), six)
        XCTAssertEqual(names("Europe/London"), ["New York", "San Francisco", "Berlin", "Tokyo", "Sydney", "Dubai"])
        XCTAssertEqual(names("America/Los_Angeles"), ["London", "New York", "Berlin", "Tokyo", "Sydney", "Dubai"])
        XCTAssertEqual(names("Australia/Sydney"), ["London", "New York", "San Francisco", "Berlin", "Tokyo", "Dubai"])
        XCTAssertEqual(names("GB"), ["New York", "San Francisco", "Berlin", "Tokyo", "Sydney", "Dubai"])
        // Same offset as Berlin, but a different city: Berlin stays.
        XCTAssertEqual(names("Europe/Paris"), six)
        for id in TimeZone.knownTimeZoneIdentifiers {
            XCTAssertEqual(BoardModel.cities(local: TimeZone(identifier: id)!).count, 6, id)
        }
    }

    func testLocalCityName() {
        let name = { (id: String) in BoardModel.localCityName(TimeZone(identifier: id)!) }
        XCTAssertEqual(name("Asia/Kolkata"), "Kolkata")
        XCTAssertEqual(name("Asia/Calcutta"), "Kolkata")
        XCTAssertEqual(name("America/New_York"), "New York")
        XCTAssertEqual(name("America/Argentina/Buenos_Aires"), "Buenos Aires")
        XCTAssertEqual(name("UTC"), "GMT")   // Foundation reports UTC as "GMT"
    }

    // MARK: Offsets

    func testFormatOffset() {
        XCTAssertEqual(BoardModel.formatOffset(minutes: 0), "+0h")
        XCTAssertEqual(BoardModel.formatOffset(minutes: 60), "+1h")
        XCTAssertEqual(BoardModel.formatOffset(minutes: 330), "+5h 30m")
        XCTAssertEqual(BoardModel.formatOffset(minutes: -330), minus + "5h 30m")
        XCTAssertEqual(BoardModel.formatOffset(minutes: -810), minus + "13h 30m")
        XCTAssertEqual(BoardModel.formatOffset(minutes: -45), minus + "0h 45m")
        XCTAssertEqual(BoardModel.formatOffset(minutes: 345), "+5h 45m")
    }

    /// Local India (UTC+5:30, no DST): every city through the US and EU spring changes.
    func testKolkataOffsetsAcrossSpringChanges() {
        // Before either change: GMT, EST, PST, CET, JST, AEDT.
        XCTAssertEqual(offsets(kolkata, "2026-03-07 12:00"), [
            "London": minus + "5h 30m", "New York": minus + "10h 30m", "San Francisco": minus + "13h 30m",
            "Berlin": minus + "4h 30m", "Tokyo": "+3h 30m", "Sydney": "+5h 30m",
        ])
        // US on daylight time (Mar 8), Europe not yet.
        XCTAssertEqual(offsets(kolkata, "2026-03-09 12:00"), [
            "London": minus + "5h 30m", "New York": minus + "9h 30m", "San Francisco": minus + "12h 30m",
            "Berlin": minus + "4h 30m", "Tokyo": "+3h 30m", "Sydney": "+5h 30m",
        ])
        // Europe too (Mar 29, 01:00 UTC).
        XCTAssertEqual(offsets(kolkata, "2026-03-29 00:59")["London"], minus + "5h 30m")
        XCTAssertEqual(offsets(kolkata, "2026-03-29 01:00")["London"], minus + "4h 30m")
        XCTAssertEqual(offsets(kolkata, "2026-03-29 01:00")["Berlin"], minus + "3h 30m")
    }

    func testKolkataOffsetsAcrossAutumnChanges() {
        // Europe back to standard time on Oct 25 (01:00 UTC); US still on daylight time.
        XCTAssertEqual(offsets(kolkata, "2026-10-25 00:59")["London"], minus + "4h 30m")
        XCTAssertEqual(offsets(kolkata, "2026-10-25 01:00")["London"], minus + "5h 30m")
        XCTAssertEqual(offsets(kolkata, "2026-10-25 01:00")["Berlin"], minus + "4h 30m")
        XCTAssertEqual(offsets(kolkata, "2026-10-31 12:00")["New York"], minus + "9h 30m")
        // US back on Nov 1 (New York 02:00 EDT = 06:00 UTC; Los Angeles 09:00 UTC).
        XCTAssertEqual(offsets(kolkata, "2026-11-01 05:59")["New York"], minus + "9h 30m")
        XCTAssertEqual(offsets(kolkata, "2026-11-01 06:00")["New York"], minus + "10h 30m")
        XCTAssertEqual(offsets(kolkata, "2026-11-01 08:59")["San Francisco"], minus + "12h 30m")
        XCTAssertEqual(offsets(kolkata, "2026-11-01 09:00")["San Francisco"], minus + "13h 30m")
    }

    /// Sydney's changes run the other way (southern hemisphere).
    func testSydneyChanges() {
        // AEDT ends Apr 5 at 03:00 local = Apr 4, 16:00 UTC.
        XCTAssertEqual(offsets(kolkata, "2026-04-04 15:59")["Sydney"], "+5h 30m")
        XCTAssertEqual(offsets(kolkata, "2026-04-04 16:00")["Sydney"], "+4h 30m")
        // AEDT starts Oct 4 at 02:00 local = Oct 3, 16:00 UTC.
        XCTAssertEqual(offsets(kolkata, "2026-10-03 15:59")["Sydney"], "+4h 30m")
        XCTAssertEqual(offsets(kolkata, "2026-10-03 16:00")["Sydney"], "+5h 30m")
        // Seen from London: +11h in January, +9h in July (both sides changed).
        let london = TimeZone(identifier: "Europe/London")!
        XCTAssertEqual(offsets(london, "2026-01-15 12:00")["Sydney"], "+11h")
        XCTAssertEqual(offsets(london, "2026-07-15 12:00")["Sydney"], "+9h")
    }

    /// When the local zone changes too, the offset moves with it, and a city that hasn't changed
    /// yet shows the gap for those hours (New York switches 3 hours before Los Angeles).
    func testLocalZoneOnDaylightTime() {
        XCTAssertEqual(offsets(newYork, "2026-03-08 06:30")["San Francisco"], minus + "3h")
        XCTAssertEqual(offsets(newYork, "2026-03-08 07:30")["San Francisco"], minus + "4h")
        XCTAssertEqual(offsets(newYork, "2026-03-08 10:30")["San Francisco"], minus + "3h")
        XCTAssertEqual(offsets(newYork, "2026-03-08 07:30")["London"], "+4h")       // EDT vs GMT
        XCTAssertEqual(offsets(newYork, "2026-03-08 06:30")["London"], "+5h")
        XCTAssertEqual(offsets(newYork, "2026-03-30 12:00")["London"], "+5h")      // both changed
        XCTAssertEqual(offsets(newYork, "2026-03-08 12:00")["Dubai"], "+8h")        // stands in for New York
        XCTAssertEqual(offsets(newYork, "2026-03-07 12:00")["Dubai"], "+9h")
        let kathmandu = TimeZone(identifier: "Asia/Kathmandu")!
        XCTAssertEqual(offsets(kathmandu, "2026-01-15 12:00")["London"], minus + "5h 45m")
    }

    func testUTCLabel() {
        let label = { (id: String, d: String) in BoardModel.utcLabel(TimeZone(identifier: id)!, at: self.utc(d)) }
        XCTAssertEqual(label("Asia/Kolkata", "2026-11-08 12:00"), "UTC+5:30")
        XCTAssertEqual(label("Asia/Kathmandu", "2026-11-08 12:00"), "UTC+5:45")
        XCTAssertEqual(label("America/New_York", "2026-03-07 12:00"), "UTC-5")
        XCTAssertEqual(label("America/New_York", "2026-03-09 12:00"), "UTC-4")
        XCTAssertEqual(label("Europe/London", "2026-01-15 12:00"), "UTC+0")
        XCTAssertEqual(label("Europe/London", "2026-07-15 12:00"), "UTC+1")
        XCTAssertEqual(label("America/St_Johns", "2026-01-15 12:00"), "UTC-3:30")
    }

    // MARK: Days

    func testDayLabelsFromKolkata() {
        // 20:00 UTC Nov 8 = 01:30 Nov 9 in Kolkata.
        XCTAssertEqual(row("New York", local: kolkata, "2026-11-08 20:00").day, .yesterday)
        XCTAssertEqual(row("London", local: kolkata, "2026-11-08 20:00").day, .yesterday)
        XCTAssertEqual(row("Tokyo", local: kolkata, "2026-11-08 20:00").day, .today)
        XCTAssertEqual(row("Sydney", local: kolkata, "2026-11-08 20:00").day, .today)
        // 15:00 UTC = 20:30 in Kolkata, already Nov 9 in Tokyo (00:00) and Sydney (02:00 AEDT).
        XCTAssertEqual(row("Tokyo", local: kolkata, "2026-11-08 15:00").day, .tomorrow)
        XCTAssertEqual(row("Sydney", local: kolkata, "2026-11-08 15:00").day, .tomorrow)
        XCTAssertEqual(row("New York", local: kolkata, "2026-11-08 15:00").day, .today)
        // One minute earlier Tokyo is still on Nov 8.
        XCTAssertEqual(row("Tokyo", local: kolkata, "2026-11-08 14:59").day, .today)
    }

    /// Sydney's day flips an hour later in winter (AEST) than in summer (AEDT).
    func testDayLabelsAcrossDaylightSaving() {
        // 13:30 UTC: 00:30 next day under AEDT (+11), 23:30 same day under AEST (+10).
        XCTAssertEqual(row("Sydney", local: kolkata, "2026-04-03 13:30").day, .tomorrow)
        XCTAssertEqual(row("Sydney", local: kolkata, "2026-04-05 13:30").day, .today)
        // New York local: Los Angeles is still on Mar 7 at 07:30 UTC on Mar 8 (23:30 PST).
        XCTAssertEqual(row("San Francisco", local: newYork, "2026-03-08 07:30").day, .yesterday)
        XCTAssertEqual(row("San Francisco", local: newYork, "2026-03-08 08:30").day, .today)
        XCTAssertEqual(row("London", local: newYork, "2026-03-08 07:30").day, .today)
        // Local London in BST at 23:30 (22:30 UTC): New York is still today, Tokyo tomorrow.
        let london = TimeZone(identifier: "Europe/London")!
        XCTAssertEqual(row("Tokyo", local: london, "2026-07-15 22:30").day, .tomorrow)
        XCTAssertEqual(row("New York", local: london, "2026-07-15 22:30").day, .today)
        // 23:30 UTC is already tomorrow in London under BST (00:30), so New York is yesterday;
        // in January it is 23:30 GMT and New York is today.
        XCTAssertEqual(row("New York", local: london, "2026-07-15 23:30").day, .yesterday)
        XCTAssertEqual(row("New York", local: london, "2026-01-15 23:30").day, .today)
    }

    // MARK: Working hours and times

    func testWorkingHours() {
        // Tokyo (no DST): 09:00 is in, 18:00 is out.
        XCTAssertFalse(row("Tokyo", local: kolkata, "2026-11-07 23:59").working)
        XCTAssertTrue(row("Tokyo", local: kolkata, "2026-11-08 00:00").working)
        XCTAssertTrue(row("Tokyo", local: kolkata, "2026-11-08 08:59").working)
        XCTAssertFalse(row("Tokyo", local: kolkata, "2026-11-08 09:00").working)
        // 13:30 UTC is 08:30 EST before the US change and 09:30 EDT after it.
        XCTAssertFalse(row("New York", local: kolkata, "2026-03-06 13:30").working)
        XCTAssertTrue(row("New York", local: kolkata, "2026-03-09 13:30").working)
    }

    func testTimes() {
        // 04:09 UTC = 13:09 Tokyo, 09:39 Kolkata.
        XCTAssertEqual(row("Tokyo", local: kolkata, "2026-11-08 04:09", uses24Hour: true).time, "13:09")
        XCTAssertEqual(row("Tokyo", local: kolkata, "2026-11-08 04:09", uses24Hour: false).time, "1:09 PM")
        // Midnight and noon in 12h.
        XCTAssertEqual(row("Tokyo", local: kolkata, "2026-11-08 15:05", uses24Hour: false).time, "12:05 AM")
        XCTAssertEqual(row("Tokyo", local: kolkata, "2026-11-08 15:05", uses24Hour: true).time, "00:05")
        XCTAssertEqual(row("Tokyo", local: kolkata, "2026-11-08 03:00", uses24Hour: false).time, "12:00 PM")
        // Across the US change: 13:30 UTC reads 8:30 then 9:30.
        XCTAssertEqual(row("New York", local: kolkata, "2026-03-07 13:30", uses24Hour: false).time, "8:30 AM")
        XCTAssertEqual(row("New York", local: kolkata, "2026-03-09 13:30", uses24Hour: false).time, "9:30 AM")
        // Header in the half-hour zone.
        let h12 = BoardModel.header(local: kolkata, at: utc("2026-11-08 04:39"), uses24Hour: false, showSeconds: false)
        XCTAssertEqual(h12.time, "10:09")
        XCTAssertEqual(h12.sub, "AM · UTC+5:30")
        XCTAssertEqual(h12.city, "KOLKATA")
        XCTAssertEqual(h12.date, "SUNDAY 08 NOVEMBER")
        let h24 = BoardModel.header(local: kolkata, at: utc("2026-11-08 16:39").addingTimeInterval(55), uses24Hour: true, showSeconds: true)
        XCTAssertEqual(h24.time, "22:09")
        XCTAssertEqual(h24.sub, "UTC+5:30 · 55")
        // 19:00 UTC is already Monday in Kolkata.
        XCTAssertEqual(BoardModel.header(local: kolkata, at: utc("2026-11-08 19:00"), uses24Hour: true, showSeconds: false).date,
                       "MONDAY 09 NOVEMBER")
    }

    /// Every city's time equals UTC plus its offset from UTC, for every hour across the year.
    func testEveryCityAgreesWithItsOffsetAllYear() {
        let utcZone = TimeZone(identifier: "UTC")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utcZone
        var date = utc("2026-01-01 00:00")
        let end = utc("2027-01-01 00:00")
        while date < end {
            for row in BoardModel.rows(local: utcZone, at: date, uses24Hour: true) {
                let city = BoardModel.roster.first { $0.name == row.city }!
                let there = date.addingTimeInterval(Double(row.offsetMinutes * 60))
                let c = cal.dateComponents([.hour, .minute], from: there)
                XCTAssertEqual(row.time, String(format: "%02d:%02d", c.hour!, c.minute!), "\(city.name) \(date)")
                XCTAssertEqual(row.offsetMinutes * 60, city.zone.secondsFromGMT(for: date))
            }
            date.addTimeInterval(3600 * 5 + 60 * 7)
        }
    }

    // MARK: Scramble

    func testScrambleTiming() {
        let target = "10:09 AM"
        // Digits are random at the start; punctuation and letters are not.
        let s = BoardModel.scrambled(target, elapsed: 0, seed: 1)!
        XCTAssertEqual(s.count, target.count)
        for (a, b) in zip(s, target) {
            if b.isNumber { XCTAssertTrue(a.isNumber) } else { XCTAssertEqual(a, b) }
        }
        // Digit j settles at 160 + 70·j ms; the line at 160 + 70·len ms.
        let mid = BoardModel.scrambled(target, elapsed: 0.160 + 70 * 2 / 1000 + 0.001, seed: 1)!
        XCTAssertEqual(Array(mid)[0...2], Array(target)[0...2])
        XCTAssertNotNil(BoardModel.scrambled(target, elapsed: 0.160 + 0.070 * 8 - 0.001, seed: 1))
        XCTAssertNil(BoardModel.scrambled(target, elapsed: 0.160 + 0.070 * 8 + 0.001, seed: 1))
        XCTAssertEqual(BoardModel.scrambleDuration("10:09"), 0.51, accuracy: 1e-9)
    }

    func testScrambleIsDeterministicAndVaries() {
        XCTAssertEqual(BoardModel.scrambled("88:88", elapsed: 0.05, seed: 3), BoardModel.scrambled("88:88", elapsed: 0.05, seed: 3))
        var seen = Set<Int>()
        for tick in 0..<200 { seen.insert(BoardModel.randomDigit(seed: 5, slot: 0, tick: tick)) }
        XCTAssertEqual(seen.count, 10)
        // Same 60 Hz tick → same digits whatever the refresh rate.
        XCTAssertEqual(BoardModel.scrambled("12:34", elapsed: 0.0501, seed: 9), BoardModel.scrambled("12:34", elapsed: 0.0659, seed: 9))
    }
}

final class BoardRendererTests: XCTestCase {
    func testRendersAndIdles() {
        let ctx = StyleContext(isPreview: false, showSeconds: true, uses24Hour: false, reduceMotion: false, appearance: .dark)
        let style = ClockStyles.make(.board, context: ctx)
        XCTAssertTrue(style is BoardRenderer)
        let root = CALayer()
        root.isGeometryFlipped = true
        style.start(in: root)
        style.layout(bounds: CGRect(x: 0, y: 0, width: 1240, height: 800), scale: 2)
        let date = Date(timeIntervalSinceReferenceDate: 815_000_000)
        let cal = Calendar.current
        func time(_ d: Date) -> ClockTime { ClockTime(date: d, calendar: cal, uses24Hour: false) }
        // First frame shows the time at once; a second within the same second is idle.
        style.render(time: time(date), frameTime: 100)
        style.render(time: time(date), frameTime: 100.5)
        XCTAssertFalse(style.wantsContinuousFrames)
        // Next minute: scrambles, then idles once every row has settled (< 1.5 s).
        let next = cal.date(byAdding: .minute, value: 1, to: date)!
        style.render(time: time(next), frameTime: 160)
        XCTAssertTrue(style.wantsContinuousFrames)
        style.render(time: time(next), frameTime: 161.6)
        XCTAssertFalse(style.wantsContinuousFrames)
        style.appearanceDidChange(.light)
        style.stop()
    }
}
