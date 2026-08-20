import Foundation

/// A notification the app should post. The engine produces these; the app layer is
/// responsible only for handing them to `UNUserNotificationCenter`.
public struct AlertRequest: Sendable, Equatable {

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case lowBattery
        case criticalBattery
        case fullyCharged
        case pluggedIn
        case unplugged
        case highDraw
        case highTemperature
        case chargingPaused

        /// Minimum time between two notifications of the same kind.
        public var cooldown: TimeInterval {
            switch self {
            case .criticalBattery: return 5 * 60
            case .lowBattery: return 15 * 60
            case .fullyCharged: return 30 * 60
            case .pluggedIn, .unplugged: return 30
            case .highDraw: return 20 * 60
            case .highTemperature: return 20 * 60
            case .chargingPaused: return 6 * 3600
            }
        }

        /// Critical alerts ignore quiet hours — a machine about to die is worth waking for.
        public var ignoresQuietHours: Bool { self == .criticalBattery }

        public var requiresPro: Bool {
            switch self {
            case .highDraw, .highTemperature: return true
            default: return false
            }
        }
    }

    public var kind: Kind
    public var title: String
    public var body: String
    public var isTimeSensitive: Bool

    public init(kind: Kind, title: String, body: String, isTimeSensitive: Bool = false) {
        self.kind = kind
        self.title = title
        self.body = body
        self.isTimeSensitive = isTimeSensitive
    }
}

/// Decides *whether* to notify. Pure, deterministic and fully testable: the engine
/// owns hysteresis, cooldowns, quiet hours and edge detection so that the app layer
/// cannot accidentally spam a user with "battery low" every two seconds.
public struct AlertEngine: Sendable {

    /// How far the level must recover before a level alert can fire again.
    public static let rearmMargin: Double = 5

    private var lastFired: [AlertRequest.Kind: Date] = [:]
    private var lowArmed = true
    private var criticalArmed = true
    private var highDrawArmed = true
    private var highTemperatureArmed = true
    private var previousState: ChargeState?
    private var previousSource: PowerSource?

    public init() {}

    public mutating func reset() {
        lastFired.removeAll()
        lowArmed = true
        criticalArmed = true
        highDrawArmed = true
        highTemperatureArmed = true
        previousState = nil
        previousSource = nil
    }

    /// Evaluates one snapshot and returns everything worth telling the user about.
    public mutating func evaluate(
        snapshot: PowerSnapshot,
        preferences: Preferences,
        isPro: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [AlertRequest] {

        defer {
            previousState = snapshot.chargeState
            previousSource = snapshot.source
        }

        guard preferences.alertsEnabled else { return [] }

        var candidates: [AlertRequest] = []
        let onBattery = !snapshot.chargeState.isPluggedIn

        // MARK: Level alerts, with hysteresis in both directions.

        if snapshot.percentage <= preferences.criticalBatteryPercent, onBattery, criticalArmed {
            criticalArmed = false
            candidates.append(
                AlertRequest(
                    kind: .criticalBattery,
                    title: "Wattson is panicking",
                    body: "\(Fmt.percent(snapshot.percentage)) left"
                        + (snapshot.timeToEmpty.map { " — about \(Fmt.longDuration($0))." } ?? ".")
                        + " Find a charger.",
                    isTimeSensitive: true
                )
            )
        } else if snapshot.percentage <= preferences.lowBatteryPercent, onBattery, lowArmed {
            lowArmed = false
            candidates.append(
                AlertRequest(
                    kind: .lowBattery,
                    title: "Battery getting low",
                    body: "\(Fmt.percent(snapshot.percentage)) left"
                        + (snapshot.timeToEmpty.map { ", roughly \(Fmt.longDuration($0))" } ?? "")
                        + " at the current \(Fmt.watts(snapshot.systemDrawWatts)) draw."
                )
            )
        }

        if snapshot.percentage >= preferences.lowBatteryPercent + AlertEngine.rearmMargin || !onBattery {
            lowArmed = true
        }
        if snapshot.percentage >= preferences.criticalBatteryPercent + AlertEngine.rearmMargin || !onBattery {
            criticalArmed = true
        }

        // MARK: State transitions.

        if let previousState, previousState != snapshot.chargeState {
            switch snapshot.chargeState {
            case .fullyCharged where preferences.notifyOnFullyCharged:
                candidates.append(
                    AlertRequest(
                        kind: .fullyCharged,
                        title: "100% — Wattson is smug",
                        body: "Fully charged. The machine is now running on adapter power"
                            + (snapshot.systemDrawWatts.map { " at about \(Fmt.watts($0))." } ?? ".")
                    )
                )
            case .chargingPaused:
                candidates.append(
                    AlertRequest(
                        kind: .chargingPaused,
                        title: "Charging on hold",
                        body: "macOS paused charging at \(Fmt.percent(snapshot.percentage)) to protect the battery. Nothing is wrong."
                    )
                )
            default:
                break
            }
        }

        if preferences.notifyOnPowerSourceChange,
           let previousSource, previousSource != snapshot.source, snapshot.source != .unknown {
            switch snapshot.source {
            case .wallAdapter:
                candidates.append(
                    AlertRequest(
                        kind: .pluggedIn,
                        title: "Plugged in",
                        body: "\(snapshot.adapter?.displayName ?? "Adapter") connected at \(Fmt.percent(snapshot.percentage))."
                    )
                )
            case .battery:
                candidates.append(
                    AlertRequest(
                        kind: .unplugged,
                        title: "Running on battery",
                        body: "Unplugged at \(Fmt.percent(snapshot.percentage))"
                            + (snapshot.timeToEmpty.map { " — about \(Fmt.longDuration($0)) at this rate." } ?? ".")
                    )
                )
            case .unknown:
                break
            }
        }

        // MARK: Pro threshold alerts.

        if preferences.notifyOnHighDraw, isPro, onBattery, let draw = snapshot.systemDrawWatts {
            if draw >= preferences.highDrawWatts, highDrawArmed {
                highDrawArmed = false
                candidates.append(
                    AlertRequest(
                        kind: .highDraw,
                        title: "Heavy power draw",
                        body: "\(Fmt.watts(draw)) on battery. At this rate you have about \(Fmt.longDuration(snapshot.timeToEmpty ?? 0))."
                    )
                )
            } else if draw < preferences.highDrawWatts * 0.8 {
                highDrawArmed = true
            }
        } else if !onBattery {
            highDrawArmed = true
        }

        if preferences.notifyOnHighTemperature, isPro, let temperature = snapshot.health.temperatureCelsius {
            if temperature >= preferences.highTemperatureCelsius, highTemperatureArmed {
                highTemperatureArmed = false
                candidates.append(
                    AlertRequest(
                        kind: .highTemperature,
                        title: "Battery running warm",
                        body: "The cell is at \(Fmt.temperature(temperature, unit: preferences.temperatureUnit)). Sustained heat is what ages a battery fastest."
                    )
                )
            } else if temperature < preferences.highTemperatureCelsius - 3 {
                highTemperatureArmed = true
            }
        }

        // MARK: Suppression — quiet hours, entitlement, cooldown.

        var approved: [AlertRequest] = []
        for candidate in candidates {
            if candidate.kind.requiresPro, !isPro { continue }
            if !candidate.kind.ignoresQuietHours,
               AlertEngine.isQuietTime(now, preferences: preferences, isPro: isPro, calendar: calendar) {
                continue
            }
            if let last = lastFired[candidate.kind], now.timeIntervalSince(last) < candidate.kind.cooldown {
                continue
            }
            lastFired[candidate.kind] = now
            approved.append(candidate)
        }
        return approved
    }

    /// Quiet hours, correct across midnight (22 → 8 means "22:00 to 07:59").
    public static func isQuietTime(
        _ date: Date,
        preferences: Preferences,
        isPro: Bool,
        calendar: Calendar = .current
    ) -> Bool {
        guard preferences.quietHoursEnabled, isPro else { return false }
        let start = preferences.quietHoursStartHour
        let end = preferences.quietHoursEndHour
        guard start != end else { return false }
        let hour = calendar.component(.hour, from: date)
        if start < end { return hour >= start && hour < end }
        return hour >= start || hour < end
    }
}
