import XCTest
@testable import WattsonCore

final class PowerMathTests: XCTestCase {

    func testBatteryFlowSignedConversion() {
        // 12.6 V at -0.95 A is a machine discharging just under 12 W.
        let flow = PowerMath.batteryFlowWatts(volts: 12.6, amps: -0.95)
        XCTAssertEqual(try XCTUnwrap(flow), -11.97, accuracy: 0.001)
    }

    func testBatteryFlowRejectsImplausibleSensorValues() {
        XCTAssertNil(PowerMath.batteryFlowWatts(volts: 0, amps: 1))
        XCTAssertNil(PowerMath.batteryFlowWatts(volts: 900, amps: 1))
        XCTAssertNil(PowerMath.batteryFlowWatts(volts: 12.6, amps: 500))
        XCTAssertNil(PowerMath.batteryFlowWatts(volts: nil, amps: 1))
        XCTAssertNil(PowerMath.batteryFlowWatts(volts: .nan, amps: 1))
    }

    func testMillivoltAndMilliampConversion() {
        XCTAssertEqual(try XCTUnwrap(PowerMath.volts(fromMillivolts: 12_600)), 12.6, accuracy: 0.0001)
        XCTAssertNil(PowerMath.volts(fromMillivolts: 12))          // already volts, not millivolts
        XCTAssertEqual(try XCTUnwrap(PowerMath.amps(fromMilliamps: -950)), -0.95, accuracy: 0.0001)
        XCTAssertNil(PowerMath.amps(fromMilliamps: 99_000))
    }

    func testDrawOnBatteryIsMeasuredAndPositive() {
        let estimate = PowerMath.systemDraw(chargeState: .discharging, batteryFlowWatts: -14.2, adapter: nil)
        XCTAssertEqual(estimate.confidence, .measured)
        XCTAssertEqual(try XCTUnwrap(estimate.watts), 14.2, accuracy: 0.001)
    }

    func testDrawOnBatteryWithoutSensorIsUnavailable() {
        XCTAssertEqual(
            PowerMath.systemDraw(chargeState: .discharging, batteryFlowWatts: nil, adapter: nil).confidence,
            .unavailable
        )
        // A positive flow while "discharging" is contradictory; refuse to invent a number.
        XCTAssertEqual(
            PowerMath.systemDraw(chargeState: .discharging, batteryFlowWatts: 3, adapter: nil).confidence,
            .unavailable
        )
    }

    func testDrawWhileChargingSubtractsChargePowerFromAdapter() {
        let adapter = AdapterInfo(name: "70W USB-C", ratedWatts: 70, volts: 20, amps: 3.0)
        let estimate = PowerMath.systemDraw(chargeState: .charging, batteryFlowWatts: 38, adapter: adapter)
        XCTAssertEqual(estimate.confidence, .estimated)
        // 20 V x 3 A negotiated = 60 W envelope, 38 W of it into the cell.
        XCTAssertEqual(try XCTUnwrap(estimate.watts), 22, accuracy: 0.001)
    }

    func testDrawWhileChargingWithoutAdapterDataIsUnavailable() {
        XCTAssertEqual(
            PowerMath.systemDraw(chargeState: .charging, batteryFlowWatts: 30, adapter: AdapterInfo()).confidence,
            .unavailable
        )
    }

    func testDrawWhenFullUsesAdapterEnvelope() {
        let adapter = AdapterInfo(ratedWatts: 96, volts: 20, amps: 4.7)
        let estimate = PowerMath.systemDraw(chargeState: .fullyCharged, batteryFlowWatts: 0, adapter: adapter)
        XCTAssertEqual(estimate.confidence, .estimated)
        XCTAssertEqual(try XCTUnwrap(estimate.watts), 94, accuracy: 0.001)
        XCTAssertTrue(estimate.explanation.lowercased().contains("upper bound"))
    }

    func testNegotiatedWattsPrefersNegotiatedPairOverNameplate() {
        // A 96 W brick negotiated down to 20 V x 1 A is a 20 W brick today.
        XCTAssertEqual(AdapterInfo(ratedWatts: 96, volts: 20, amps: 1).negotiatedWatts, 20)
        XCTAssertEqual(AdapterInfo(ratedWatts: 96).negotiatedWatts, 96)
        XCTAssertNil(AdapterInfo().negotiatedWatts)
    }

    func testDrawIsClampedToPlausibleRange() {
        let silly = AdapterInfo(volts: 20, amps: 25) // 500 W, physically impossible here
        let estimate = PowerMath.systemDraw(chargeState: .fullyCharged, batteryFlowWatts: 0, adapter: silly)
        XCTAssertEqual(try XCTUnwrap(estimate.watts), PowerMath.maximumPlausibleWatts)
    }

    func testProjectedRuntime() {
        // 40 Wh left at 10 W is four hours.
        let runtime = PowerMath.projectedRuntime(remainingWattHours: 40, drawWatts: 10)
        XCTAssertEqual(try XCTUnwrap(runtime), 4 * 3600, accuracy: 1)
        // A negligible draw would project days; refuse rather than lie.
        XCTAssertNil(PowerMath.projectedRuntime(remainingWattHours: 40, drawWatts: 0.1))
        XCTAssertNil(PowerMath.projectedRuntime(remainingWattHours: nil, drawWatts: 10))
    }

    func testProjectedTimeToCharge() {
        // 8000 mAh at 12.6 V is 100.8 Wh; 50% of that at 40 W is ~1.26 h.
        let time = PowerMath.projectedTimeToCharge(
            currentPercent: 50,
            targetPercent: 100,
            fullChargeCapacityMilliampHours: 8000,
            volts: 12.6,
            chargeWatts: 40
        )
        XCTAssertEqual(try XCTUnwrap(time) / 3600, 1.26, accuracy: 0.01)
        XCTAssertNil(
            PowerMath.projectedTimeToCharge(
                currentPercent: 100, targetPercent: 100,
                fullChargeCapacityMilliampHours: 8000, volts: 12.6, chargeWatts: 40
            )
        )
    }

    func testWattHoursTrapezoid() {
        XCTAssertEqual(PowerMath.wattHours(fromWatts: 10, to: 20, seconds: 3600), 15, accuracy: 0.0001)
        XCTAssertEqual(PowerMath.wattHours(fromWatts: 10, to: 10, seconds: 1800), 5, accuracy: 0.0001)
        // A gap longer than six hours is a sleep/wake gap, not a measurement.
        XCTAssertEqual(PowerMath.wattHours(fromWatts: 10, to: 10, seconds: 100_000), 0)
    }

    func testIntensityMapping() {
        XCTAssertEqual(PowerMath.intensity(forWatts: 3), 0, accuracy: 0.0001)
        XCTAssertEqual(PowerMath.intensity(forWatts: 45), 1, accuracy: 0.0001)
        XCTAssertEqual(PowerMath.intensity(forWatts: 200), 1, accuracy: 0.0001)
        XCTAssertEqual(PowerMath.intensity(forWatts: -5), 0, accuracy: 0.0001)
    }
}
