import XCTest
@testable import QuietHoursPreview

final class TickerTextTests: XCTestCase {
    func testTimeText() {
        let am = ClockTime(hour24: 9, minute: 9, second: 5, uses24Hour: false)
        XCTAssertEqual(TickerText.time(am, showSeconds: false), "9:09")
        XCTAssertEqual(TickerText.time(am, showSeconds: true), "9:09:05")
        let am24 = ClockTime(hour24: 9, minute: 9, second: 5, uses24Hour: true)
        XCTAssertEqual(TickerText.time(am24, showSeconds: false), "09:09")
        let pm = ClockTime(hour24: 22, minute: 30, second: 59, uses24Hour: false)
        XCTAssertEqual(TickerText.time(pm, showSeconds: true), "10:30:59")
        XCTAssertEqual(TickerText.time(ClockTime(hour24: 0, minute: 0, second: 0, uses24Hour: false), showSeconds: false), "12:00")
        XCTAssertEqual(TickerText.time(ClockTime(hour24: 0, minute: 0, second: 0, uses24Hour: true), showSeconds: false), "00:00")
    }

    func testDateText() {
        let utc = TimeZone(identifier: "UTC")!
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 8; c.hour = 12
        var cal = Calendar(identifier: .gregorian); cal.timeZone = utc
        XCTAssertEqual(TickerText.date(cal.date(from: c)!, timeZone: utc), "SUNDAY 08 NOV")
        c.month = 3; c.day = 4
        XCTAssertEqual(TickerText.date(cal.date(from: c)!, timeZone: utc), "WEDNESDAY 04 MAR")
    }

    func testBandText() {
        XCTAssertEqual(TickerText.band(date: "SUN", time: "9:09", meridiem: "AM"),
                       "Q U I E T   H O U R S     /     S U N     /     9 : 0 9   A M     /       ")
        XCTAssertEqual(TickerText.band(date: "X", time: "21:09", meridiem: nil),
                       "Q U I E T   H O U R S     /     X     /     2 1 : 0 9     /       ")
    }
}

final class TickerStreamTests: XCTestCase {
    private let W = 1000.0

    private func fill(_ s: inout TickerStream, time: String, date: String = "DATE") -> [TickerStream.Item] {
        s.fill(screenWidth: W, text: { $0 == .time ? time : date },
               width: { kind, text in kind == .sep ? 62 : Double(text.count) * 50 })
    }

    func testInitialFillIsContiguousFromSixPercent() {
        var s = TickerStream()
        let added = fill(&s, time: "10:09")
        XCTAssertEqual(added.first?.start, 60)
        XCTAssertEqual(added.map(\.kind), added.indices.map { TickerStream.sequence[$0 % 4] })
        XCTAssertEqual(TickerStream.sequence, [.time, .sep, .date, .sep])
        for (a, b) in zip(added, added.dropFirst()) { XCTAssertEqual(a.end, b.start) }   // no gaps, no overlaps
        XCTAssertGreaterThanOrEqual(added.last!.end, W * 1.4)
        XCTAssertLessThan(added.last!.start, W * 1.4)
        XCTAssertTrue(added.filter { $0.kind == .sep }.allSatisfy { $0.text.isEmpty })
    }

    /// Over an hour of scrolling, new items only ever appear beyond the right edge, keep the text
    /// they entered with, and the line stays seamless.
    func testNewItemsEnterOnlyFromTheRightWithFixedText() {
        var s = TickerStream()
        var seen: [Int: String] = [:]
        for item in fill(&s, time: "10:00") { seen[item.id] = item.text }
        let fps = 120.0, v = W * 0.06
        for frame in 1...Int(3600 * fps) {
            let minute = 10 * 60 + frame / Int(60 * fps)
            let time = "\(minute / 60):\(String(format: "%02d", minute % 60))"
            s.advance(by: v / fps)
            let gone = s.prune(screenWidth: W)
            for g in gone { XCTAssertLessThan(s.x(g) + g.width, -W * 0.05) }
            for item in fill(&s, time: time) {
                XCTAssertGreaterThan(s.x(item), W, "entered on screen")
                if item.kind == .time { XCTAssertEqual(item.text, time) }
                seen[item.id] = item.text
            }
            if frame % 600 == 0 {
                for (a, b) in zip(s.items, s.items.dropFirst()) { XCTAssertEqual(a.end, b.start) }
                for item in s.items { XCTAssertEqual(seen[item.id], item.text) }
                XCTAssertLessThan(s.items.count, 16)
            }
        }
        XCTAssertTrue(s.items.contains { $0.text == "11:00" || $0.text == "10:59" })
    }

    func testResetStartsAgain() {
        var s = TickerStream()
        _ = fill(&s, time: "1")
        s.advance(by: 500)
        let gone = s.reset()
        XCTAssertFalse(gone.isEmpty)
        XCTAssertTrue(s.items.isEmpty)
        XCTAssertEqual(fill(&s, time: "2").first?.start, 60)
    }
}
