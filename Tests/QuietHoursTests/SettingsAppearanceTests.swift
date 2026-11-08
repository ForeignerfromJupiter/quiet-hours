import XCTest
@testable import QuietHoursPreview

final class AppearanceTests: XCTestCase {
    func testAutoFollowsSystem() {
        XCTAssertEqual(AppearanceResolver.resolve(.auto, systemIsDark: true), .dark)
        XCTAssertEqual(AppearanceResolver.resolve(.auto, systemIsDark: false), .light)
    }

    func testPinnedFinishIgnoresSystem() {
        XCTAssertEqual(AppearanceResolver.resolve(.dark, systemIsDark: false), .dark)
        XCTAssertEqual(AppearanceResolver.resolve(.light, systemIsDark: true), .light)
    }

    func testInterfaceStyleKey() {
        XCTAssertTrue(AppearanceResolver.isDark(interfaceStyle: "Dark"))
        XCTAssertTrue(AppearanceResolver.isDark(interfaceStyle: "dark"))
        XCTAssertFalse(AppearanceResolver.isDark(interfaceStyle: nil))
        XCTAssertFalse(AppearanceResolver.isDark(interfaceStyle: "Light"))
        XCTAssertFalse(AppearanceResolver.isDark(interfaceStyle: ""))
    }
}

final class SettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "com.ashik.quiethours.tests.settings"

    override func setUp() {
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
    }

    func testDefaultsWhenEmpty() {
        let s = Settings.load(from: defaults)
        XCTAssertEqual(s, Settings())
        XCTAssertEqual(s.style, .hinge)
        XCTAssertEqual(s.finish(for: .hinge), .auto)
        XCTAssertEqual(s.hourCycle, .system)
        XCTAssertFalse(s.showSeconds)
        XCTAssertTrue(s.pureBlack, "Pure black is on by default")
    }

    func testRoundTrip() {
        var s = Settings()
        s.style = .hinge
        s.finishes[.hinge] = .light
        s.hourCycle = .h24
        s.showSeconds = true
        s.pureBlack = false
        s.save(to: defaults)
        XCTAssertEqual(Settings.load(from: defaults), s)
    }

    func testGarbageFallsBackToDefaults() {
        defaults.set("sundial", forKey: Settings.Key.style)
        defaults.set("h36", forKey: Settings.Key.hourCycle)
        defaults.set("neon", forKey: Settings.Key.finish(.hinge))
        XCTAssertEqual(Settings.load(from: defaults), Settings())
    }
}

final class CubicBezierTests: XCTestCase {
    func testEndpoints() {
        let c = CubicBezier(0.6, 0, 0.95, 0.5)
        XCTAssertEqual(c(0), 0)
        XCTAssertEqual(c(1), 1)
        XCTAssertEqual(c(-1), 0)
        XCTAssertEqual(c(2), 1)
    }

    func testLinear() {
        for x in stride(from: 0.0, through: 1.0, by: 0.1) {
            XCTAssertEqual(CubicBezier.linear(x), x, accuracy: 1e-5)
        }
    }

    func testCSSEaseMidpoint() {
        // Known value for CSS `ease` at 50% time.
        XCTAssertEqual(CubicBezier.ease(0.5), 0.8024, accuracy: 0.001)
    }

    func testHingeLandingOvershootsAbout11Degrees() {
        let land = CubicBezier(0.18, 1.65, 0.42, 1)
        let peak = stride(from: 0.0, through: 1.0, by: 0.001).map { land($0) }.max()!
        XCTAssertEqual(peak, 1.126, accuracy: 0.003)
    }
}

final class RoomTests: XCTestCase {
    func testPureBlackOnlyAffectsDarkFinish() {
        let c = srgb(0x111111), e = srgb(0x000000), light = srgb(0xeeeeee)
        XCTAssertEqual(Room.colors(center: c, edge: e, appearance: .dark, pureBlack: true), [Room.black, Room.black])
        XCTAssertEqual(Room.colors(center: c, edge: e, appearance: .dark, pureBlack: false), [c, e])
        XCTAssertEqual(Room.colors(center: light, edge: e, appearance: .light, pureBlack: true), [light, e])
    }

    func testBurnInShiftStaysSmallAndPixelSnapped() {
        let size = CGSize(width: 2544, height: 1431)
        var seen = Set<String>()
        for t in stride(from: 0.0, through: 900, by: 0.5) {
            let o = Room.burnInOffset(at: t, size: size, scale: 2)
            XCTAssertLessThanOrEqual(abs(o.x), Room.shiftMargin - 2)
            XCTAssertLessThanOrEqual(abs(o.y), Room.shiftMargin - 2)
            XCTAssertEqual(o.x * 2, (o.x * 2).rounded(), "whole device pixels")
            seen.insert("\(o.x),\(o.y)")
        }
        XCTAssertGreaterThan(seen.count, 20, "it actually moves over 15 minutes")
        XCTAssertEqual(Room.burnInOffset(at: 100, size: size, scale: 2), Room.burnInOffset(at: 100.2, size: size, scale: 2),
                       "slow enough to sit still between seconds")
    }
}
