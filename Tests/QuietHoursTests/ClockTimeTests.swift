import XCTest
@testable import QuietHoursPreview

final class ClockTimeTests: XCTestCase {
    private func digits(_ t: ClockTime) -> String {
        t.digits.map { $0.map(String.init) ?? "_" }.joined()
    }

    func test24HourKeepsLeadingZero() {
        let t = ClockTime(hour24: 9, minute: 5, second: 7, uses24Hour: true)
        XCTAssertEqual(digits(t), "0905")
        XCTAssertNil(t.meridiem)
    }

    func test12HourHidesLeadingZero() {
        let t = ClockTime(hour24: 9, minute: 41, second: 0, uses24Hour: false)
        XCTAssertEqual(digits(t), "_941")
        XCTAssertEqual(t.meridiem, "AM")
    }

    func test12HourMidnightAndNoon() {
        XCTAssertEqual(digits(ClockTime(hour24: 0, minute: 0, second: 0, uses24Hour: false)), "1200")
        XCTAssertEqual(ClockTime(hour24: 0, minute: 0, second: 0, uses24Hour: false).meridiem, "AM")
        XCTAssertEqual(digits(ClockTime(hour24: 12, minute: 30, second: 0, uses24Hour: false)), "1230")
        XCTAssertEqual(ClockTime(hour24: 12, minute: 30, second: 0, uses24Hour: false).meridiem, "PM")
    }

    func test12HourEvening() {
        let t = ClockTime(hour24: 23, minute: 59, second: 59, uses24Hour: false)
        XCTAssertEqual(digits(t), "1159")
        XCTAssertEqual(t.meridiem, "PM")
        XCTAssertEqual(t.displayHour, 11)
    }

    func test24HourMidnight() {
        XCTAssertEqual(digits(ClockTime(hour24: 0, minute: 7, second: 0, uses24Hour: true)), "0007")
    }

    func testSecondsArePadded() {
        XCTAssertEqual(ClockTime(hour24: 1, minute: 2, second: 3, uses24Hour: true).secondDigits, ["0", "3"])
        XCTAssertEqual(ClockTime(hour24: 1, minute: 2, second: 59, uses24Hour: true).secondDigits, ["5", "9"])
    }

    func testFromDateUsesCalendar() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 13 * 3600 + 4 * 60 + 5.25) // 13:04:05.250 UTC
        let t = ClockTime(date: date, calendar: cal, uses24Hour: false)
        XCTAssertEqual(t.hour24, 13)
        XCTAssertEqual(t.minute, 4)
        XCTAssertEqual(t.second, 5)
        XCTAssertEqual(t.millisecond, 250, accuracy: 1)
        XCTAssertEqual(digits(t), "_104")
        XCTAssertEqual(t.meridiem, "PM")
    }
}

final class TimeFormatTests: XCTestCase {
    func testLocaleDetection() {
        XCTAssertFalse(TimeFormat.localeUses24Hour(Locale(identifier: "en_US")))
        XCTAssertTrue(TimeFormat.localeUses24Hour(Locale(identifier: "en_GB")))
        XCTAssertTrue(TimeFormat.localeUses24Hour(Locale(identifier: "de_DE")))
        XCTAssertTrue(TimeFormat.localeUses24Hour(Locale(identifier: "fr_FR")))
        XCTAssertFalse(TimeFormat.localeUses24Hour(Locale(identifier: "en_IN")))
    }

    func testLocaleOverrideKeywordsAreRespected() {
        // ICU "hours" keyword: what macOS sets when the user flips the 24-hour switch.
        XCTAssertTrue(TimeFormat.localeUses24Hour(Locale(identifier: "en_US@hours=h23")))
        XCTAssertFalse(TimeFormat.localeUses24Hour(Locale(identifier: "en_GB@hours=h12")))
    }

    func testExplicitSettingWins() {
        let us = Locale(identifier: "en_US")
        XCTAssertTrue(TimeFormat.uses24Hour(.h24, locale: us, force24: nil, force12: true))
        XCTAssertFalse(TimeFormat.uses24Hour(.h12, locale: Locale(identifier: "de_DE"), force24: true, force12: nil))
    }

    func testSystemFollowsMacOSSwitchThenLocale() {
        let us = Locale(identifier: "en_US"), de = Locale(identifier: "de_DE")
        XCTAssertTrue(TimeFormat.uses24Hour(.system, locale: us, force24: true, force12: nil))
        XCTAssertFalse(TimeFormat.uses24Hour(.system, locale: de, force24: nil, force12: true))
        XCTAssertFalse(TimeFormat.uses24Hour(.system, locale: us, force24: nil, force12: nil))
        XCTAssertTrue(TimeFormat.uses24Hour(.system, locale: de, force24: false, force12: nil))
    }
}
