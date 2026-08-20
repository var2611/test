import Foundation

/// Where the machine is currently drawing its power from.
public enum PowerSource: String, Codable, Sendable, CaseIterable {
    case battery
    case wallAdapter
    case unknown

    public var isExternal: Bool { self == .wallAdapter }
}

/// What the battery is doing right now.
public enum ChargeState: String, Codable, Sendable, CaseIterable {
    /// Running off the cell.
    case discharging
    /// Energy is flowing into the cell.
    case charging
    /// Plugged in and at (or effectively at) 100%.
    case fullyCharged
    /// Plugged in but not charging — optimized charging, charge limit, or too hot/cold.
    case chargingPaused
    /// No battery present (external display Mac, or a battery that failed to enumerate).
    case noBattery
    case unknown

    public var isPluggedIn: Bool {
        switch self {
        case .charging, .fullyCharged, .chargingPaused: return true
        case .discharging, .noBattery, .unknown: return false
        }
    }
}

/// How much a wattage figure can be trusted. Wattson never shows an estimate
/// without saying that it is one.
public enum MeasurementConfidence: String, Codable, Sendable {
    /// Derived directly from the battery's own voltage and current sensors.
    case measured
    /// Derived from adapter negotiation values, which are ceilings rather than
    /// instantaneous readings.
    case estimated
    /// Not enough information to produce a number worth showing.
    case unavailable

    public var badge: String {
        switch self {
        case .measured: return "measured"
        case .estimated: return "estimated"
        case .unavailable: return "unavailable"
        }
    }
}

/// The power adapter as described by the system, when one is attached.
public struct AdapterInfo: Codable, Sendable, Equatable {
    public var name: String?
    /// The adapter's rated (nameplate) wattage.
    public var ratedWatts: Double?
    /// Negotiated voltage in volts.
    public var volts: Double?
    /// Negotiated current in amps.
    public var amps: Double?
    public var isWireless: Bool
    public var familyCode: Int?

    public init(
        name: String? = nil,
        ratedWatts: Double? = nil,
        volts: Double? = nil,
        amps: Double? = nil,
        isWireless: Bool = false,
        familyCode: Int? = nil
    ) {
        self.name = name
        self.ratedWatts = ratedWatts
        self.volts = volts
        self.amps = amps
        self.isWireless = isWireless
        self.familyCode = familyCode
    }

    /// The negotiated power envelope, preferring the negotiated V×A pair over the
    /// nameplate rating because a 96 W brick negotiated down to 60 W is a 60 W brick.
    public var negotiatedWatts: Double? {
        if let volts, let amps, volts > 0, amps > 0 {
            return volts * amps
        }
        if let ratedWatts, ratedWatts > 0 { return ratedWatts }
        return nil
    }

    public var displayName: String {
        if let name, !name.isEmpty { return name }
        if let watts = negotiatedWatts { return "\(Int(watts.rounded())) W adapter" }
        return "Power adapter"
    }
}

/// Long-lived facts about the cell itself.
public struct BatteryHealth: Codable, Sendable, Equatable {
    public var cycleCount: Int?
    public var designCapacityMilliampHours: Double?
    public var fullChargeCapacityMilliampHours: Double?
    public var currentCapacityMilliampHours: Double?
    public var temperatureCelsius: Double?
    public var conditionRaw: String?
    public var isPermanentFailure: Bool

    public init(
        cycleCount: Int? = nil,
        designCapacityMilliampHours: Double? = nil,
        fullChargeCapacityMilliampHours: Double? = nil,
        currentCapacityMilliampHours: Double? = nil,
        temperatureCelsius: Double? = nil,
        conditionRaw: String? = nil,
        isPermanentFailure: Bool = false
    ) {
        self.cycleCount = cycleCount
        self.designCapacityMilliampHours = designCapacityMilliampHours
        self.fullChargeCapacityMilliampHours = fullChargeCapacityMilliampHours
        self.currentCapacityMilliampHours = currentCapacityMilliampHours
        self.temperatureCelsius = temperatureCelsius
        self.conditionRaw = conditionRaw
        self.isPermanentFailure = isPermanentFailure
    }

    /// Maximum capacity as a percentage of the design capacity — the number
    /// System Settings shows as "Maximum Capacity".
    public var maximumCapacityPercent: Double? {
        guard
            let design = designCapacityMilliampHours, design > 0,
            let full = fullChargeCapacityMilliampHours, full > 0
        else { return nil }
        return min((full / design) * 100.0, 200.0)
    }

    /// A coarse, human-facing judgement used for the health chip colour.
    public var grade: HealthGrade {
        if isPermanentFailure { return .serviceNeeded }
        if let raw = conditionRaw?.lowercased() {
            if raw.contains("service") || raw.contains("replace now") { return .serviceNeeded }
            if raw.contains("replace soon") || raw.contains("fair") { return .fair }
        }
        guard let percent = maximumCapacityPercent else { return .unknown }
        switch percent {
        case 90...: return .excellent
        case 80..<90: return .good
        case 65..<80: return .fair
        default: return .serviceNeeded
        }
    }
}

public enum HealthGrade: String, Codable, Sendable {
    case excellent, good, fair, serviceNeeded, unknown

    public var label: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .serviceNeeded: return "Service recommended"
        case .unknown: return "Unknown"
        }
    }
}

/// One complete observation of the machine's power situation.
///
/// Every optional field is independently optional on purpose: a MacBook that does
/// not expose, say, `Temperature` must still produce a fully useful snapshot.
public struct PowerSnapshot: Codable, Sendable, Equatable {
    public var timestamp: Date
    public var isBatteryPresent: Bool
    /// 0...100.
    public var percentage: Double
    public var source: PowerSource
    public var chargeState: ChargeState
    /// Battery terminal voltage, volts.
    public var volts: Double?
    /// Battery current, amps. Positive flows *into* the cell.
    public var amps: Double?
    /// Signed battery power, watts. Positive charges, negative discharges.
    public var batteryFlowWatts: Double?
    /// What the whole machine is burning, watts. See `drawConfidence`.
    public var systemDrawWatts: Double?
    public var drawConfidence: MeasurementConfidence
    public var timeToEmpty: TimeInterval?
    public var timeToFull: TimeInterval?
    public var isLowPowerMode: Bool
    public var adapter: AdapterInfo?
    public var health: BatteryHealth
    /// True when the machine is an Apple Silicon Mac.
    public var isAppleSilicon: Bool

    public init(
        timestamp: Date = Date(),
        isBatteryPresent: Bool = true,
        percentage: Double = 0,
        source: PowerSource = .unknown,
        chargeState: ChargeState = .unknown,
        volts: Double? = nil,
        amps: Double? = nil,
        batteryFlowWatts: Double? = nil,
        systemDrawWatts: Double? = nil,
        drawConfidence: MeasurementConfidence = .unavailable,
        timeToEmpty: TimeInterval? = nil,
        timeToFull: TimeInterval? = nil,
        isLowPowerMode: Bool = false,
        adapter: AdapterInfo? = nil,
        health: BatteryHealth = BatteryHealth(),
        isAppleSilicon: Bool = true
    ) {
        self.timestamp = timestamp
        self.isBatteryPresent = isBatteryPresent
        self.percentage = percentage.clamped(to: 0...100)
        self.source = source
        self.chargeState = chargeState
        self.volts = volts
        self.amps = amps
        self.batteryFlowWatts = batteryFlowWatts
        self.systemDrawWatts = systemDrawWatts
        self.drawConfidence = drawConfidence
        self.timeToEmpty = timeToEmpty
        self.timeToFull = timeToFull
        self.isLowPowerMode = isLowPowerMode
        self.adapter = adapter
        self.health = health
        self.isAppleSilicon = isAppleSilicon
    }

    /// Fraction 0...1, convenient for gauges.
    public var fraction: Double { (percentage / 100.0).clamped(to: 0...1) }

    /// Remaining energy in the cell, watt-hours, when capacity and voltage are known.
    public var remainingWattHours: Double? {
        guard
            let mAh = health.currentCapacityMilliampHours, mAh > 0,
            let volts, volts > 0
        else { return nil }
        return (mAh / 1000.0) * volts
    }

    /// A snapshot used by SwiftUI previews and by the UI before the first real read.
    public static let placeholder = PowerSnapshot(
        isBatteryPresent: true,
        percentage: 67,
        source: .battery,
        chargeState: .discharging,
        volts: 12.6,
        amps: -0.95,
        batteryFlowWatts: -11.97,
        systemDrawWatts: 11.97,
        drawConfidence: .measured,
        timeToEmpty: 4 * 3600 + 12 * 60,
        health: BatteryHealth(
            cycleCount: 142,
            designCapacityMilliampHours: 8694,
            fullChargeCapacityMilliampHours: 8320,
            currentCapacityMilliampHours: 5574,
            temperatureCelsius: 31.4,
            conditionRaw: "Normal"
        )
    )
}

extension Comparable {
    /// Small shared helper — clamping shows up in nearly every calculation here.
    public func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
