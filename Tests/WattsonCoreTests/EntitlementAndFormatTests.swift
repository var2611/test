import XCTest
@testable import WattsonCore

final class EntitlementTests: XCTestCase {

    func testFreeUsersGetNoProFeatures() {
        let free = EntitlementMatrix(isPro: false)
        for feature in ProFeature.allCases {
            XCTAssertFalse(free.isAvailable(feature), "\(feature) leaked to the free tier")
        }
        XCTAssertEqual(free.lockedFeatures.count, ProFeature.allCases.count)
    }

    func testProUsersGetEverything() {
        let pro = EntitlementMatrix(isPro: true)
        for feature in ProFeature.allCases {
            XCTAssertTrue(pro.isAvailable(feature))
        }
        XCTAssertTrue(pro.lockedFeatures.isEmpty)
    }

    func testEveryFeatureIsPresentable() {
        for feature in ProFeature.allCases {
            XCTAssertFalse(feature.title.isEmpty)
            XCTAssertFalse(feature.blurb.isEmpty)
            XCTAssertFalse(feature.systemImage.isEmpty)
        }
    }

    func testFreeTierPromiseIsNotEmpty() {
        // The free tier must stand on its own; App Review reads this list too.
        XCTAssertGreaterThanOrEqual(EntitlementMatrix.freeTierPromise.count, 5)
    }
}

final class FormatterTests: XCTestCase {

    func testWattFormatting() {
        XCTAssertEqual(Fmt.watts(12.34), "12.3 W")
        XCTAssertEqual(Fmt.watts(4.567), "4.6 W")
        XCTAssertEqual(Fmt.watts(120.4), "120 W")
        XCTAssertEqual(Fmt.watts(nil), "—")
        XCTAssertEqual(Fmt.watts(.infinity), "—")
    }

    func testCompactWattsForTheMenuBar() {
        XCTAssertEqual(Fmt.compactWatts(9.44), "9.4W")
        XCTAssertEqual(Fmt.compactWatts(23.6), "24W")
        XCTAssertEqual(Fmt.compactWatts(nil), "—")
    }

    func testFlowShowsDirection() {
        XCTAssertEqual(Fmt.flow(21.5), "↑ 21.5 W")
        XCTAssertEqual(Fmt.flow(-11.2), "↓ 11.2 W")
        XCTAssertEqual(Fmt.flow(0.01), "0 W")
        XCTAssertEqual(Fmt.flow(nil), "—")
    }

    func testDurationFormatting() {
        XCTAssertEqual(Fmt.duration(4 * 3600 + 12 * 60), "4h 12m")
        XCTAssertEqual(Fmt.duration(48 * 60), "48m")
        XCTAssertEqual(Fmt.duration(2 * 3600), "2h")
        XCTAssertEqual(Fmt.duration(20), "< 1m")
        XCTAssertEqual(Fmt.duration(0), "—")
        XCTAssertEqual(Fmt.duration(nil), "—")
    }

    func testLongDurationReadsAsASentence() {
        XCTAssertEqual(Fmt.longDuration(3600 + 60), "1 hour 1 minute")
        XCTAssertEqual(Fmt.longDuration(2 * 3600 + 120), "2 hours 2 minutes")
        XCTAssertEqual(Fmt.longDuration(nil), "an unknown amount of time")
    }

    func testTemperatureConversion() {
        XCTAssertEqual(Fmt.temperature(30, unit: .celsius), "30.0 °C")
        XCTAssertEqual(Fmt.temperature(30, unit: .fahrenheit), "86.0 °F")
        XCTAssertEqual(Fmt.temperature(nil, unit: .celsius), "—")
    }

    func testHeadlinesCoverEveryState() {
        for state in ChargeState.allCases {
            var snapshot = PowerSnapshot.placeholder
            snapshot.chargeState = state
            XCTAssertFalse(Fmt.headline(for: snapshot).isEmpty)
            XCTAssertFalse(Fmt.stateTitle(state).isEmpty)
        }
        for source in PowerSource.allCases {
            XCTAssertFalse(Fmt.sourceTitle(source).isEmpty)
        }
    }
}

final class SnapshotTests: XCTestCase {

    func testPercentageIsClampedOnConstruction() {
        XCTAssertEqual(PowerSnapshot(percentage: 140).percentage, 100)
        XCTAssertEqual(PowerSnapshot(percentage: -20).percentage, 0)
        XCTAssertEqual(PowerSnapshot(percentage: 55).fraction, 0.55, accuracy: 0.0001)
    }

    func testRemainingWattHours() {
        var snapshot = PowerSnapshot.placeholder
        snapshot.volts = 12.0
        snapshot.health.currentCapacityMilliampHours = 5000
        XCTAssertEqual(try XCTUnwrap(snapshot.remainingWattHours), 60, accuracy: 0.0001)

        snapshot.health.currentCapacityMilliampHours = nil
        XCTAssertNil(snapshot.remainingWattHours)
    }

    func testHealthGrades() {
        func health(design: Double, full: Double, condition: String? = nil, failure: Bool = false) -> BatteryHealth {
            BatteryHealth(
                designCapacityMilliampHours: design,
                fullChargeCapacityMilliampHours: full,
                conditionRaw: condition,
                isPermanentFailure: failure
            )
        }
        XCTAssertEqual(health(design: 100, full: 95).grade, .excellent)
        XCTAssertEqual(health(design: 100, full: 85).grade, .good)
        XCTAssertEqual(health(design: 100, full: 70).grade, .fair)
        XCTAssertEqual(health(design: 100, full: 50).grade, .serviceNeeded)
        XCTAssertEqual(health(design: 100, full: 99, condition: "Service Battery").grade, .serviceNeeded)
        XCTAssertEqual(health(design: 100, full: 99, failure: true).grade, .serviceNeeded)
        XCTAssertEqual(BatteryHealth().grade, .unknown)
        XCTAssertEqual(health(design: 8694, full: 8320).maximumCapacityPercent ?? 0, 95.7, accuracy: 0.1)
    }

    func testChargeStateKnowsWhenItIsPluggedIn() {
        XCTAssertTrue(ChargeState.charging.isPluggedIn)
        XCTAssertTrue(ChargeState.fullyCharged.isPluggedIn)
        XCTAssertTrue(ChargeState.chargingPaused.isPluggedIn)
        XCTAssertFalse(ChargeState.discharging.isPluggedIn)
        XCTAssertFalse(ChargeState.noBattery.isPluggedIn)
    }
}
