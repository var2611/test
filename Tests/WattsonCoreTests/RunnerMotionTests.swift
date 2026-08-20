import XCTest
@testable import WattsonCore

final class RunnerMotionTests: XCTestCase {

    private func snapshot(draw: Double?, state: ChargeState = .discharging, percent: Double = 70) -> PowerSnapshot {
        PowerSnapshot(
            percentage: percent,
            source: state.isPluggedIn ? .wallAdapter : .battery,
            chargeState: state,
            systemDrawWatts: draw
        )
    }

    func testHigherDrawRunsFaster() {
        let idle = RunnerMotion.motion(for: snapshot(draw: 4), mood: .chill)
        let busy = RunnerMotion.motion(for: snapshot(draw: 40), mood: .turbo)
        XCTAssertGreaterThan(busy.strideRate, idle.strideRate)
        XCTAssertGreaterThan(busy.travelSpeed, idle.travelSpeed)
        XCTAssertGreaterThan(busy.effort, idle.effort)
    }

    func testRatesStayInsideAnimatableBounds() {
        for watts in stride(from: -50.0, through: 400.0, by: 7.0) {
            for multiplier in [0.1, 1.0, 9.0] {
                let motion = RunnerMotion.motion(
                    for: snapshot(draw: watts), mood: .working, speedMultiplier: multiplier
                )
                XCTAssertTrue((0.5...9).contains(motion.strideRate))
                XCTAssertTrue((0...260).contains(motion.travelSpeed))
                XCTAssertTrue((0...1).contains(motion.effort))
            }
        }
    }

    func testMissingReadingFallsBackToAModestJog() {
        let motion = RunnerMotion.motion(for: snapshot(draw: nil), mood: .chill)
        XCTAssertGreaterThan(motion.strideRate, 0.5)
        XCTAssertLessThan(motion.strideRate, 3)
    }

    func testChargingAndCelebratingStates() {
        let charging = RunnerMotion.motion(for: snapshot(draw: 20, state: .charging), mood: .sipping)
        XCTAssertTrue(charging.isCharging)
        XCTAssertFalse(charging.isCelebrating)

        let full = RunnerMotion.motion(for: snapshot(draw: 8, state: .fullyCharged, percent: 100), mood: .fullAndSmug)
        XCTAssertTrue(full.isCelebrating)
        XCTAssertEqual(full.travelSpeed, 0, "a victory lap happens on the spot")
    }

    func testTrudgingWhenConserving() {
        let normal = RunnerMotion.motion(for: snapshot(draw: 20), mood: .working)
        let saving = RunnerMotion.motion(for: snapshot(draw: 20, percent: 12), mood: .powerSaver)
        XCTAssertLessThan(saving.strideRate, normal.strideRate)
        XCTAssertTrue(saving.isTrudging)
        XCTAssertGreaterThanOrEqual(saving.effort, 0.75)
    }

    func testCaptionsDescribeTheState() {
        XCTAssertTrue(RunnerMotion.motion(for: snapshot(draw: 8, state: .fullyCharged), mood: .fullAndSmug).caption(watts: 8).contains("victory"))
        XCTAssertTrue(RunnerMotion.motion(for: snapshot(draw: 8, state: .charging), mood: .sipping).caption(watts: 8).contains("adapter"))
        XCTAssertTrue(RunnerMotion.motion(for: snapshot(draw: 8), mood: .chill).caption(watts: 8).contains("strides/s"))
    }
}
