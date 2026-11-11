import XCTest
@testable import QuietHoursPreview

final class LeadingSlotChangeTests: XCTestCase {
    func testGoingChangesDigitsFirstThenGlidesShut() {
        let c = LeadingSlotChange(start: 10, opening: false, settle: 0.7)
        XCTAssertEqual(c.changeStart, 10)
        XCTAssertEqual(c.glideStart, 10.7, accuracy: 1e-9)
        XCTAssertEqual(c.presence(at: 10), 1)          // old row holds while the digits change
        XCTAssertEqual(c.presence(at: 10.69), 1)
        XCTAssertEqual(c.presence(at: 10.7 + LeadingSlotChange.glide), 0, accuracy: 1e-9)
        XCTAssertEqual(c.presence(at: 10.7 + LeadingSlotChange.glide / 2), 0.5, accuracy: 0.01)
        XCTAssertFalse(c.isDone(at: 11.1))
        XCTAssertTrue(c.isDone(at: 10.7 + LeadingSlotChange.glide))
    }

    func testOpeningGlidesFirstThenChangesDigits() {
        let c = LeadingSlotChange(start: 10, opening: true, settle: 0.7)
        XCTAssertEqual(c.glideStart, 10)
        XCTAssertEqual(c.changeStart, 10 + LeadingSlotChange.glide, accuracy: 1e-9)
        XCTAssertEqual(c.presence(at: 10), 0)
        XCTAssertEqual(c.presence(at: c.changeStart), 1, accuracy: 1e-9)
        XCTAssertTrue(c.isDone(at: c.changeStart))
    }

    func testPresenceIsMonotonic() {
        for opening in [false, true] {
            let c = LeadingSlotChange(start: 0, opening: opening, settle: 1)
            var last = c.presence(at: -1)
            for i in 0...300 {
                let p = c.presence(at: Double(i) / 100)
                XCTAssert(opening ? p >= last - 1e-12 : p <= last + 1e-12)
                XCTAssert((0...1).contains(p))
                last = p
            }
        }
    }

    func testEchoLongestChangeCoversFourSlots() {
        // 12:59 → 1:00 changes four slots; the last back layer must finish before the row moves.
        let last = EchoModel.swapStart(now: 0, layer: EchoModel.layers - 1, order: 3) + EchoModel.swapDuration
        XCTAssertEqual(EchoModel.longestChange, last, accuracy: 1e-9)
    }
}
