import XCTest
@testable import WattsonCore

final class MascotMoodTests: XCTestCase {

    private func snapshot(
        percent: Double,
        state: ChargeState,
        draw: Double? = nil,
        flow: Double? = nil,
        lowPower: Bool = false,
        batteryPresent: Bool = true
    ) -> PowerSnapshot {
        PowerSnapshot(
            isBatteryPresent: batteryPresent,
            percentage: percent,
            source: state.isPluggedIn ? .wallAdapter : .battery,
            chargeState: state,
            batteryFlowWatts: flow,
            systemDrawWatts: draw,
            isLowPowerMode: lowPower
        )
    }

    func testChillWhenIdleOnBattery() {
        XCTAssertEqual(MascotMoodResolver.mood(for: snapshot(percent: 80, state: .discharging, draw: 6)), .chill)
    }

    func testWorkingAndTurboScaleWithDraw() {
        XCTAssertEqual(MascotMoodResolver.mood(for: snapshot(percent: 80, state: .discharging, draw: 18)), .working)
        XCTAssertEqual(MascotMoodResolver.mood(for: snapshot(percent: 80, state: .discharging, draw: 40)), .turbo)
    }

    func testLowAndCriticalOutrankLoad() {
        XCTAssertEqual(MascotMoodResolver.mood(for: snapshot(percent: 15, state: .discharging, draw: 40)), .sweating)
        XCTAssertEqual(MascotMoodResolver.mood(for: snapshot(percent: 5, state: .discharging, draw: 40)), .panicking)
    }

    func testPanicSurvivesBeingPluggedIn() {
        // Charging at 3% is still an emergency until the level recovers.
        XCTAssertEqual(MascotMoodResolver.mood(for: snapshot(percent: 3, state: .charging, flow: 40)), .panicking)
    }

    func testChargingSpeedChoosesSippingOrGuzzling() {
        XCTAssertEqual(MascotMoodResolver.mood(for: snapshot(percent: 50, state: .charging, flow: 12)), .sipping)
        XCTAssertEqual(MascotMoodResolver.mood(for: snapshot(percent: 50, state: .charging, flow: 45)), .guzzling)
    }

    func testPluggedInStates() {
        XCTAssertEqual(MascotMoodResolver.mood(for: snapshot(percent: 100, state: .fullyCharged)), .fullAndSmug)
        XCTAssertEqual(MascotMoodResolver.mood(for: snapshot(percent: 80, state: .chargingPaused)), .napping)
    }

    func testLowPowerModeBeatsLoadButNotLevel() {
        XCTAssertEqual(
            MascotMoodResolver.mood(for: snapshot(percent: 60, state: .discharging, draw: 40, lowPower: true)),
            .powerSaver
        )
        XCTAssertEqual(
            MascotMoodResolver.mood(for: snapshot(percent: 10, state: .discharging, draw: 5, lowPower: true)),
            .sweating
        )
    }

    func testGhostWithoutABattery() {
        XCTAssertEqual(
            MascotMoodResolver.mood(for: snapshot(percent: 0, state: .noBattery, batteryPresent: false)),
            .ghost
        )
    }

    func testCustomThresholdsAreHonoured() {
        let thresholds = MoodThresholds(lowPercent: 40, criticalPercent: 25)
        XCTAssertEqual(
            MascotMoodResolver.mood(for: snapshot(percent: 35, state: .discharging, draw: 5), thresholds: thresholds),
            .sweating
        )
    }

    func testEveryMoodHasDialogueAndTheChoiceIsStable() {
        for mood in MascotMood.allCases {
            let line = MascotMoodResolver.line(for: mood, seed: 7)
            XCTAssertFalse(line.isEmpty)
            XCTAssertEqual(line, MascotMoodResolver.line(for: mood, seed: 7))
            XCTAssertFalse(line.hasPrefix("..."), "\(mood) has no dialogue")
        }
    }

    func testDialogueIndexIsSafeForNegativeSeeds() {
        XCTAssertFalse(MascotMoodResolver.line(for: .chill, seed: -99).isEmpty)
    }
}
