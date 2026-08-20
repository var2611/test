import XCTest
@testable import WattsonCore

final class PowerHistoryTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(_ offsetSeconds: Double, percent: Double, draw: Double?, state: ChargeState = .discharging) -> PowerSample {
        PowerSample(
            timestamp: base.addingTimeInterval(offsetSeconds),
            percentage: percent,
            drawWatts: draw,
            flowWatts: draw.map { -$0 },
            state: state
        )
    }

    func testRingBufferNeverExceedsCapacity() {
        var history = PowerHistory(capacity: 100)
        for index in 0..<500 {
            history.append(sample(Double(index) * 10, percent: 50, draw: 10))
        }
        XCTAssertEqual(history.count, 100)
        // The newest sample survives, the oldest is gone.
        XCTAssertEqual(history.latest?.timestamp, base.addingTimeInterval(4990))
    }

    func testCapacityIsAlsoEnforcedOnInitialisation() {
        let seeded = (0..<50).map { sample(Double($0), percent: 10, draw: 1) }
        let history = PowerHistory(capacity: 20, samples: seeded)
        XCTAssertEqual(history.count, 20)
    }

    func testPruneDropsOnlyOldSamples() {
        var history = PowerHistory(capacity: 1000)
        for index in 0..<10 { history.append(sample(Double(index) * 600, percent: 90, draw: 8)) }
        let now = base.addingTimeInterval(9 * 600)
        history.prune(olderThan: 3600, now: now)
        XCTAssertEqual(history.count, 7)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(history.samples.first).timestamp, now.addingTimeInterval(-3600))
    }

    func testPruneCanEmptyTheHistory() {
        var history = PowerHistory(capacity: 10)
        history.append(sample(0, percent: 50, draw: 5))
        history.prune(olderThan: 60, now: base.addingTimeInterval(10_000))
        XCTAssertTrue(history.isEmpty)
    }

    func testDownsamplingHitsTheBucketBudget() {
        var history = PowerHistory(capacity: 5000)
        for index in 0..<1000 { history.append(sample(Double(index) * 10, percent: 80, draw: 12)) }
        let points = history.downsampled(within: 24 * 3600, buckets: 60, now: base.addingTimeInterval(10_000))
        XCTAssertLessThanOrEqual(points.count, 60)
        XCTAssertGreaterThan(points.count, 50)
    }

    func testDownsamplingReturnsRawSeriesWhenSmallerThanBudget() {
        var history = PowerHistory(capacity: 100)
        for index in 0..<10 { history.append(sample(Double(index), percent: 80, draw: 12)) }
        XCTAssertEqual(history.downsampled(within: 3600, buckets: 60, now: base.addingTimeInterval(20)).count, 10)
    }

    func testStatsComputeAverageEnergyAndDischargeRate() {
        var history = PowerHistory(capacity: 1000)
        // Two hours of a steady 10 W discharge losing 5 percentage points per hour.
        for index in 0...120 {
            history.append(sample(Double(index) * 60, percent: 100 - Double(index) * (5.0 / 60.0), draw: 10))
        }
        let stats = history.stats(within: 6 * 3600, now: base.addingTimeInterval(120 * 60))
        XCTAssertEqual(try XCTUnwrap(stats.averageDrawWatts), 10, accuracy: 0.0001)
        XCTAssertEqual(stats.energyWattHours, 20, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(stats.dischargeRatePerHour), 5, accuracy: 0.1)
        XCTAssertEqual(stats.timeOnBattery, 120 * 60, accuracy: 1)
        XCTAssertEqual(stats.timeOnAdapter, 0, accuracy: 0.001)
    }

    func testStatsIgnoreSleepGaps() {
        var history = PowerHistory(capacity: 100)
        history.append(sample(0, percent: 100, draw: 10))
        // An eight-hour gap is the lid being shut, not eighty watt-hours of use.
        history.append(sample(8 * 3600, percent: 95, draw: 10))
        let stats = history.stats(within: 24 * 3600, now: base.addingTimeInterval(8 * 3600 + 60))
        XCTAssertEqual(stats.energyWattHours, 0, accuracy: 0.0001)
    }

    func testStatsOnEmptyWindow() {
        let history = PowerHistory(capacity: 10)
        XCTAssertEqual(history.stats(within: 3600), .empty)
    }

    func testCodableRoundTripPreservesCapacity() throws {
        var history = PowerHistory(capacity: 42)
        for index in 0..<10 { history.append(sample(Double(index), percent: 55, draw: 9)) }
        let data = try JSONEncoder().encode(history)
        let restored = try JSONDecoder().decode(PowerHistory.self, from: data)
        XCTAssertEqual(restored.capacity, 42)
        XCTAssertEqual(restored.count, 10)
        XCTAssertEqual(restored, history)
    }

    func testCSVHasHeaderAndOneRowPerSample() {
        var history = PowerHistory(capacity: 10)
        history.append(sample(0, percent: 50, draw: 12.345))
        history.append(sample(60, percent: 49, draw: nil))
        let csv = history.csv(within: 3600, now: base.addingTimeInterval(120))
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "timestamp,percentage,system_draw_w,battery_flow_w,state")
        XCTAssertTrue(lines[1].contains("12.35"))
        XCTAssertTrue(lines[2].hasSuffix(",,,discharging"))
    }
}
