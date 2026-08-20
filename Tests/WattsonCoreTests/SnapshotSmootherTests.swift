import XCTest
@testable import WattsonCore

final class SnapshotSmootherTests: XCTestCase {

    private func snapshot(draw: Double?, state: ChargeState = .discharging) -> PowerSnapshot {
        PowerSnapshot(percentage: 50, source: .battery, chargeState: state, systemDrawWatts: draw, drawConfidence: .measured)
    }

    func testFirstSampleIsPassedThroughUnchanged() {
        var smoother = SnapshotSmoother(alpha: 0.35)
        let result = smoother.smooth(snapshot(draw: 12))
        XCTAssertEqual(try XCTUnwrap(result.systemDrawWatts), 12, accuracy: 0.0001)
    }

    func testSubsequentSamplesAreDamped() {
        var smoother = SnapshotSmoother(alpha: 0.5)
        _ = smoother.smooth(snapshot(draw: 10))
        let result = smoother.smooth(snapshot(draw: 20))
        XCTAssertEqual(try XCTUnwrap(result.systemDrawWatts), 15, accuracy: 0.0001)
    }

    func testStateChangeResetsTheAverage() {
        var smoother = SnapshotSmoother(alpha: 0.5)
        _ = smoother.smooth(snapshot(draw: 10, state: .discharging))
        // Plugging in must snap, not glide.
        let result = smoother.smooth(snapshot(draw: 60, state: .charging))
        XCTAssertEqual(try XCTUnwrap(result.systemDrawWatts), 60, accuracy: 0.0001)
    }

    func testMissingReadingIsNotPresentedAsCurrent() {
        var smoother = SnapshotSmoother(alpha: 0.5)
        _ = smoother.smooth(snapshot(draw: 10))
        XCTAssertNil(smoother.smooth(snapshot(draw: nil)).systemDrawWatts)
    }

    func testAlphaIsClampedAwayFromZero() {
        let smoother = SnapshotSmoother(alpha: 0)
        XCTAssertGreaterThan(smoother.alpha, 0)
    }

    func testConvergesTowardsTheTrueValue() {
        var smoother = SnapshotSmoother(alpha: 0.35)
        _ = smoother.smooth(snapshot(draw: 0))
        var last: Double = 0
        for _ in 0..<25 { last = smoother.smooth(snapshot(draw: 20)).systemDrawWatts ?? 0 }
        XCTAssertEqual(last, 20, accuracy: 0.05)
    }
}
