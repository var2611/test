import XCTest
@testable import WattsonCore

final class PreferencesTests: XCTestCase {

    func testValidationClampsEveryRange() {
        var prefs = Preferences.default
        prefs.runnerScale = 99
        prefs.runnerSpeedMultiplier = -4
        prefs.refreshIntervalOnAdapter = 0.001
        prefs.refreshIntervalOnBattery = 9_999
        prefs.historyRetentionDays = 4_000
        prefs.lowBatteryPercent = 500
        prefs.highDrawWatts = 1
        prefs.highTemperatureCelsius = 900
        prefs.quietHoursStartHour = 47

        let validated = prefs.validated()
        XCTAssertEqual(validated.runnerScale, 2.0)
        XCTAssertEqual(validated.runnerSpeedMultiplier, 0.5)
        XCTAssertEqual(validated.refreshIntervalOnAdapter, 1)
        XCTAssertEqual(validated.refreshIntervalOnBattery, 120)
        XCTAssertEqual(validated.historyRetentionDays, 90)
        XCTAssertEqual(validated.lowBatteryPercent, 50)
        XCTAssertEqual(validated.highDrawWatts, 10)
        XCTAssertEqual(validated.highTemperatureCelsius, 60)
        XCTAssertEqual(validated.quietHoursStartHour, 23)
    }

    func testCriticalThresholdStaysBelowLowThreshold() {
        var prefs = Preferences.default
        prefs.lowBatteryPercent = 15
        prefs.criticalBatteryPercent = 40
        XCTAssertLessThan(prefs.validated().criticalBatteryPercent, prefs.validated().lowBatteryPercent)
    }

    func testDecodingToleratesMissingKeys() throws {
        // A preferences blob written by an older build: one known key, nothing else.
        let json = Data(#"{"runnerCorner":"bottomLeft"}"#.utf8)
        let decoded = try JSONDecoder().decode(Preferences.self, from: json)
        XCTAssertEqual(decoded.runnerCorner, .bottomLeft)
        XCTAssertEqual(decoded.mascotSkin, Preferences.default.mascotSkin)
        XCTAssertEqual(decoded.refreshIntervalOnBattery, Preferences.default.refreshIntervalOnBattery)
    }

    func testDecodingToleratesUnknownEnumValues() throws {
        // A skin removed in a later build must not break the whole preferences file.
        let json = Data(#"{"mascotSkin":"holographic","runnerCharacter":"dino"}"#.utf8)
        let decoded = try JSONDecoder().decode(Preferences.self, from: json)
        XCTAssertEqual(decoded.mascotSkin, .classic)
        XCTAssertEqual(decoded.runnerCharacter, .dino)
    }

    func testCodableRoundTrip() throws {
        var prefs = Preferences.default
        prefs.mascotSkin = .neon
        prefs.runnerCharacter = .toaster
        prefs.quietHoursEnabled = true
        let data = try JSONEncoder().encode(prefs)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: data), prefs)
    }

    func testDowngradeRemovesEveryPaidSetting() {
        var prefs = Preferences.default
        prefs.mascotSkin = .vaporwave
        prefs.runnerCharacter = .corgi
        prefs.runnerScale = 1.8
        prefs.historyRetentionDays = 30
        prefs.notifyOnHighDraw = true
        prefs.quietHoursEnabled = true
        prefs.menuBarDisplay = MenuBarDisplay(showPercentage: false, showWatts: false, showTimeRemaining: true)

        let free = prefs.downgradedToFreeTier()
        XCTAssertEqual(free.mascotSkin, .classic)
        XCTAssertEqual(free.runnerCharacter, .wattson)
        XCTAssertEqual(free.runnerScale, 1.0)
        XCTAssertEqual(free.historyRetentionDays, 1)
        XCTAssertFalse(free.notifyOnHighDraw)
        XCTAssertFalse(free.quietHoursEnabled)
        XCTAssertEqual(free.menuBarDisplay, .default)
    }

    func testDowngradeIsIdempotent() {
        let once = Preferences.default.downgradedToFreeTier()
        XCTAssertEqual(once.downgradedToFreeTier(), once)
    }

    func testOnlyTheDefaultSkinAndRunnerAreFree() {
        XCTAssertEqual(MascotSkin.allCases.filter { !$0.requiresPro }, [.classic])
        XCTAssertEqual(RunnerCharacter.allCases.filter { !$0.requiresPro }, [.wattson])
    }

    func testMoodThresholdsFollowPreferences() {
        var prefs = Preferences.default
        prefs.lowBatteryPercent = 33
        prefs.criticalBatteryPercent = 11
        XCTAssertEqual(prefs.moodThresholds.lowPercent, 33)
        XCTAssertEqual(prefs.moodThresholds.criticalPercent, 11)
    }
}
