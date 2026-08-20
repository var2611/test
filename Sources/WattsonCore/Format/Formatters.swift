import Foundation

public enum TemperatureUnit: String, Codable, Sendable, CaseIterable {
    case celsius, fahrenheit
    public var symbol: String { self == .celsius ? "°C" : "°F" }
}

/// Every user-facing string that contains a number is produced here, so that
/// rounding, units and edge cases ("--" versus "0 W" versus "<1 W") are consistent
/// across the menu bar, the dashboard, the notifications and the overlay.
public enum Fmt {

    public static let placeholder = "—"

    // MARK: - Power

    /// e.g. "12.4 W", "0.8 W", "—"
    public static func watts(_ value: Double?, decimals: Int? = nil) -> String {
        guard let value, value.isFinite else { return placeholder }
        let magnitude = abs(value)
        let places = decimals ?? (magnitude < 10 ? 1 : (magnitude < 100 ? 1 : 0))
        return String(format: "%.\(places)f W", value)
    }

    /// Compact form for the menu bar, where every pixel is rented.
    public static func compactWatts(_ value: Double?) -> String {
        guard let value, value.isFinite else { return placeholder }
        if abs(value) >= 10 { return String(format: "%.0fW", value) }
        return String(format: "%.1fW", value)
    }

    /// Signed flow, with an explicit direction arrow.
    public static func flow(_ value: Double?) -> String {
        guard let value, value.isFinite else { return placeholder }
        if abs(value) < 0.05 { return "0 W" }
        let arrow = value > 0 ? "↑" : "↓"
        return "\(arrow) " + String(format: "%.1f W", abs(value))
    }

    public static func amps(_ value: Double?) -> String {
        guard let value, value.isFinite else { return placeholder }
        return String(format: "%.2f A", value)
    }

    public static func volts(_ value: Double?) -> String {
        guard let value, value.isFinite else { return placeholder }
        return String(format: "%.2f V", value)
    }

    public static func wattHours(_ value: Double?) -> String {
        guard let value, value.isFinite else { return placeholder }
        if abs(value) < 10 { return String(format: "%.2f Wh", value) }
        return String(format: "%.1f Wh", value)
    }

    // MARK: - Battery

    public static func percent(_ value: Double?, decimals: Int = 0) -> String {
        guard let value, value.isFinite else { return placeholder }
        return String(format: "%.\(decimals)f%%", value)
    }

    public static func milliampHours(_ value: Double?) -> String {
        guard let value, value.isFinite else { return placeholder }
        return String(format: "%.0f mAh", value)
    }

    public static func temperature(_ celsius: Double?, unit: TemperatureUnit) -> String {
        guard let celsius, celsius.isFinite else { return placeholder }
        switch unit {
        case .celsius: return String(format: "%.1f °C", celsius)
        case .fahrenheit: return String(format: "%.1f °F", celsius * 9.0 / 5.0 + 32.0)
        }
    }

    // MARK: - Time

    /// "4h 12m", "48m", "—". Never "0h 0m".
    public static func duration(_ interval: TimeInterval?) -> String {
        guard let interval, interval.isFinite, interval > 0 else { return placeholder }
        let totalMinutes = Int((interval / 60).rounded())
        guard totalMinutes > 0 else { return "< 1m" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes)m"
    }

    /// Longer form used in sentences: "about 4 hours 12 minutes".
    public static func longDuration(_ interval: TimeInterval?) -> String {
        guard let interval, interval.isFinite, interval > 0 else { return "an unknown amount of time" }
        let totalMinutes = Int((interval / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hour\(hours == 1 ? "" : "s")") }
        if minutes > 0 { parts.append("\(minutes) minute\(minutes == 1 ? "" : "s")") }
        return parts.isEmpty ? "less than a minute" : parts.joined(separator: " ")
    }

    // MARK: - States

    public static func stateTitle(_ state: ChargeState) -> String {
        switch state {
        case .charging: return "Charging"
        case .discharging: return "On battery"
        case .fullyCharged: return "Fully charged"
        case .chargingPaused: return "Plugged in, on hold"
        case .noBattery: return "No battery"
        case .unknown: return "Checking…"
        }
    }

    public static func sourceTitle(_ source: PowerSource) -> String {
        switch source {
        case .battery: return "Battery power"
        case .wallAdapter: return "Adapter power"
        case .unknown: return "Unknown source"
        }
    }

    /// The headline sentence at the top of the dashboard.
    public static func headline(for snapshot: PowerSnapshot) -> String {
        switch snapshot.chargeState {
        case .charging:
            if let full = snapshot.timeToFull {
                return "Charging — full in \(duration(full))"
            }
            return "Charging from the adapter"
        case .fullyCharged:
            return "Fully charged — running on adapter power"
        case .chargingPaused:
            return "Plugged in — charging paused by macOS"
        case .discharging:
            if let empty = snapshot.timeToEmpty {
                return "On battery — \(duration(empty)) left"
            }
            return "On battery power"
        case .noBattery:
            return "Running on adapter power — no battery installed"
        case .unknown:
            return "Reading power state…"
        }
    }
}
