import XCTest
@testable import WattsonCore

final class AlertEngineTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(
        percent: Double,
        state: ChargeState = .discharging,
        draw: Double? = 10,
        temperature: Double? = nil
    ) -> PowerSnapshot {
        PowerSnapshot(
            percentage: percent,
            source: state.isPluggedIn ? .wallAdapter : .battery,
            chargeState: state,
            systemDrawWatts: draw,
            adapter: state.isPluggedIn ? AdapterInfo(name: "70W", ratedWatts: 70, volts: 20, amps: 3.5) : nil,
            health: BatteryHealth(temperatureCelsius: temperature)
        )
    }

    func testLowBatteryFiresOnceUntilItRecovers() {
        var engine = AlertEngine()
        let prefs = Preferences.default

        // Establish a baseline above the threshold.
        _ = engine.evaluate(snapshot: snapshot(percent: 60), preferences: prefs, isPro: false, now: start)

        let first = engine.evaluate(snapshot: snapshot(percent: 19), preferences: prefs, isPro: false, now: start.addingTimeInterval(60))
        XCTAssertEqual(first.map(\.kind), [.lowBattery])

        // Still low a minute later: no second notification.
        let second = engine.evaluate(snapshot: snapshot(percent: 18), preferences: prefs, isPro: false, now: start.addingTimeInterval(120))
        XCTAssertTrue(second.isEmpty)

        // Recover past the re-arm margin, then drop again — that is a new event.
        _ = engine.evaluate(snapshot: snapshot(percent: 40, state: .charging), preferences: prefs, isPro: false, now: start.addingTimeInterval(1800))
        let third = engine.evaluate(snapshot: snapshot(percent: 19), preferences: prefs, isPro: false, now: start.addingTimeInterval(3600))
        XCTAssertEqual(third.map(\.kind), [.lowBattery])
    }

    func testCriticalBatteryIsTimeSensitiveAndOutranksLow() {
        var engine = AlertEngine()
        _ = engine.evaluate(snapshot: snapshot(percent: 60), preferences: .default, isPro: false, now: start)
        let alerts = engine.evaluate(snapshot: snapshot(percent: 4), preferences: .default, isPro: false, now: start.addingTimeInterval(60))
        XCTAssertEqual(alerts.map(\.kind), [.criticalBattery])
        XCTAssertTrue(try XCTUnwrap(alerts.first).isTimeSensitive)
    }

    func testCooldownSuppressesRepeats() {
        var engine = AlertEngine()
        var prefs = Preferences.default
        prefs.notifyOnPowerSourceChange = true

        _ = engine.evaluate(snapshot: snapshot(percent: 80, state: .discharging), preferences: prefs, isPro: false, now: start)
        let plugged = engine.evaluate(snapshot: snapshot(percent: 80, state: .charging), preferences: prefs, isPro: false, now: start.addingTimeInterval(5))
        XCTAssertEqual(plugged.map(\.kind), [.pluggedIn])

        // Flapping cable: unplug/replug inside the cooldown must stay quiet.
        _ = engine.evaluate(snapshot: snapshot(percent: 80, state: .discharging), preferences: prefs, isPro: false, now: start.addingTimeInterval(6))
        let replug = engine.evaluate(snapshot: snapshot(percent: 80, state: .charging), preferences: prefs, isPro: false, now: start.addingTimeInterval(7))
        XCTAssertTrue(replug.isEmpty)
    }

    func testFullyChargedFiresOnTheTransitionOnly() {
        var engine = AlertEngine()
        _ = engine.evaluate(snapshot: snapshot(percent: 99, state: .charging), preferences: .default, isPro: false, now: start)
        let full = engine.evaluate(snapshot: snapshot(percent: 100, state: .fullyCharged), preferences: .default, isPro: false, now: start.addingTimeInterval(60))
        XCTAssertEqual(full.map(\.kind), [.fullyCharged])

        let stillFull = engine.evaluate(snapshot: snapshot(percent: 100, state: .fullyCharged), preferences: .default, isPro: false, now: start.addingTimeInterval(120))
        XCTAssertTrue(stillFull.isEmpty)
    }

    func testProAlertsAreGated() {
        var engine = AlertEngine()
        var prefs = Preferences.default
        prefs.notifyOnHighDraw = true
        prefs.highDrawWatts = 30

        _ = engine.evaluate(snapshot: snapshot(percent: 80, draw: 5), preferences: prefs, isPro: false, now: start)
        let free = engine.evaluate(snapshot: snapshot(percent: 80, draw: 45), preferences: prefs, isPro: false, now: start.addingTimeInterval(60))
        XCTAssertTrue(free.isEmpty, "high draw is a Pro alert")

        var proEngine = AlertEngine()
        _ = proEngine.evaluate(snapshot: snapshot(percent: 80, draw: 5), preferences: prefs, isPro: true, now: start)
        let pro = proEngine.evaluate(snapshot: snapshot(percent: 80, draw: 45), preferences: prefs, isPro: true, now: start.addingTimeInterval(60))
        XCTAssertEqual(pro.map(\.kind), [.highDraw])
    }

    func testHighDrawRearmsOnlyAfterItDropsWellerBelowTheThreshold() {
        var engine = AlertEngine()
        var prefs = Preferences.default
        prefs.notifyOnHighDraw = true
        prefs.highDrawWatts = 30

        _ = engine.evaluate(snapshot: snapshot(percent: 80, draw: 45), preferences: prefs, isPro: true, now: start)
        // 26 W is below the threshold but inside the 80% hysteresis band.
        _ = engine.evaluate(snapshot: snapshot(percent: 80, draw: 26), preferences: prefs, isPro: true, now: start.addingTimeInterval(60))
        let stillQuiet = engine.evaluate(
            snapshot: snapshot(percent: 80, draw: 45), preferences: prefs, isPro: true,
            now: start.addingTimeInterval(60 * 60)
        )
        XCTAssertTrue(stillQuiet.isEmpty)

        _ = engine.evaluate(snapshot: snapshot(percent: 80, draw: 10), preferences: prefs, isPro: true, now: start.addingTimeInterval(61 * 60))
        let refired = engine.evaluate(snapshot: snapshot(percent: 80, draw: 45), preferences: prefs, isPro: true, now: start.addingTimeInterval(62 * 60))
        XCTAssertEqual(refired.map(\.kind), [.highDraw])
    }

    func testQuietHoursSuppressNonCriticalAlertsOnly() {
        var prefs = Preferences.default
        prefs.quietHoursEnabled = true
        prefs.quietHoursStartHour = 22
        prefs.quietHoursEndHour = 8

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try! XCTUnwrap(TimeZone(identifier: "UTC"))
        let midnight = try! XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 3, day: 1, hour: 0, minute: 30)))

        XCTAssertTrue(AlertEngine.isQuietTime(midnight, preferences: prefs, isPro: true, calendar: calendar))

        var engine = AlertEngine()
        _ = engine.evaluate(snapshot: snapshot(percent: 60), preferences: prefs, isPro: true, now: midnight, calendar: calendar)
        let low = engine.evaluate(snapshot: snapshot(percent: 15), preferences: prefs, isPro: true, now: midnight.addingTimeInterval(60), calendar: calendar)
        XCTAssertTrue(low.isEmpty)

        let critical = engine.evaluate(snapshot: snapshot(percent: 4), preferences: prefs, isPro: true, now: midnight.addingTimeInterval(120), calendar: calendar)
        XCTAssertEqual(critical.map(\.kind), [.criticalBattery], "a dying machine still gets to speak")
    }

    func testQuietHoursSpanningMidnightAndDaytimeRanges() {
        var prefs = Preferences.default
        prefs.quietHoursEnabled = true

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try! XCTUnwrap(TimeZone(identifier: "UTC"))
        func date(hour: Int) -> Date {
            (try? XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 3, day: 1, hour: hour)))) ?? Date()
        }

        prefs.quietHoursStartHour = 22
        prefs.quietHoursEndHour = 8
        XCTAssertTrue(AlertEngine.isQuietTime(date(hour: 23), preferences: prefs, isPro: true, calendar: calendar))
        XCTAssertTrue(AlertEngine.isQuietTime(date(hour: 3), preferences: prefs, isPro: true, calendar: calendar))
        XCTAssertFalse(AlertEngine.isQuietTime(date(hour: 12), preferences: prefs, isPro: true, calendar: calendar))

        prefs.quietHoursStartHour = 9
        prefs.quietHoursEndHour = 17
        XCTAssertTrue(AlertEngine.isQuietTime(date(hour: 12), preferences: prefs, isPro: true, calendar: calendar))
        XCTAssertFalse(AlertEngine.isQuietTime(date(hour: 3), preferences: prefs, isPro: true, calendar: calendar))

        // Quiet hours are a Pro feature and a no-op for free users.
        XCTAssertFalse(AlertEngine.isQuietTime(date(hour: 12), preferences: prefs, isPro: false, calendar: calendar))
    }

    func testAlertsDisabledSilencesEverything() {
        var prefs = Preferences.default
        prefs.alertsEnabled = false
        var engine = AlertEngine()
        _ = engine.evaluate(snapshot: snapshot(percent: 60), preferences: prefs, isPro: true, now: start)
        XCTAssertTrue(engine.evaluate(snapshot: snapshot(percent: 2), preferences: prefs, isPro: true, now: start.addingTimeInterval(60)).isEmpty)
    }

    func testChargingPausedIsExplainedOnce() {
        var engine = AlertEngine()
        _ = engine.evaluate(snapshot: snapshot(percent: 80, state: .charging), preferences: .default, isPro: false, now: start)
        let paused = engine.evaluate(snapshot: snapshot(percent: 80, state: .chargingPaused), preferences: .default, isPro: false, now: start.addingTimeInterval(30))
        XCTAssertEqual(paused.map(\.kind), [.chargingPaused])
        XCTAssertTrue(try XCTUnwrap(paused.first).body.contains("Nothing is wrong"))
    }

    func testFirstEvaluationDoesNotFireTransitionAlerts() {
        var engine = AlertEngine()
        var prefs = Preferences.default
        prefs.notifyOnPowerSourceChange = true
        // With no previous state there is no transition — launching the app while
        // plugged in must not immediately announce "plugged in".
        XCTAssertTrue(engine.evaluate(snapshot: snapshot(percent: 90, state: .charging), preferences: prefs, isPro: true, now: start).isEmpty)
    }
}
