import Foundation

/// The result of asking "what is this machine burning right now?".
public struct DrawEstimate: Sendable, Equatable {
    public let watts: Double?
    public let confidence: MeasurementConfidence
    /// Plain-language description of how the number was produced, surfaced as a tooltip.
    public let explanation: String

    public init(watts: Double?, confidence: MeasurementConfidence, explanation: String) {
        self.watts = watts
        self.confidence = confidence
        self.explanation = explanation
    }

    public static let unavailable = DrawEstimate(
        watts: nil,
        confidence: .unavailable,
        explanation: "macOS is not reporting enough sensor data to compute system draw right now."
    )
}

/// All wattage arithmetic lives here so it can be tested without a Mac attached.
public enum PowerMath {

    /// Below this, a reading is noise rather than a measurement.
    public static let minimumPlausibleWatts: Double = 0.1
    /// A MacBook Pro 16" with a 140 W brick cannot plausibly exceed this.
    public static let maximumPlausibleWatts: Double = 250.0

    // MARK: - Primitive conversions

    /// Battery power in watts from terminal voltage and signed current.
    /// Positive means energy is flowing *into* the cell.
    public static func batteryFlowWatts(volts: Double?, amps: Double?) -> Double? {
        guard
            let volts, let amps,
            volts.isFinite, amps.isFinite,
            volts > 0, volts < 60,
            abs(amps) < 30
        else { return nil }
        return volts * amps
    }

    /// Millivolts as reported by IOKit, converted to volts, rejecting nonsense.
    public static func volts(fromMillivolts millivolts: Double?) -> Double? {
        guard let millivolts, millivolts.isFinite, millivolts > 1000, millivolts < 60_000 else { return nil }
        return millivolts / 1000.0
    }

    /// Milliamps as reported by IOKit, converted to amps, rejecting nonsense.
    /// IOKit reports this as a signed value on Apple Silicon; some Intel machines
    /// report an unsigned magnitude, which the reader corrects before calling here.
    public static func amps(fromMilliamps milliamps: Double?) -> Double? {
        guard let milliamps, milliamps.isFinite, abs(milliamps) < 30_000 else { return nil }
        return milliamps / 1000.0
    }

    // MARK: - System draw

    /// Total machine consumption, with an honest confidence level attached.
    ///
    /// - On battery the answer is exact: everything the machine burns leaves the cell.
    /// - While charging we can only subtract the charge power from what the adapter
    ///   is negotiated to supply, and adapter negotiation is a ceiling, not a meter.
    /// - When the cell is full the battery contributes nothing to the measurement, so
    ///   the negotiated adapter envelope is all that is left.
    public static func systemDraw(
        chargeState: ChargeState,
        batteryFlowWatts: Double?,
        adapter: AdapterInfo?
    ) -> DrawEstimate {
        switch chargeState {
        case .discharging:
            guard let flow = batteryFlowWatts, flow < 0 else { return .unavailable }
            let watts = clampPlausible(-flow)
            return DrawEstimate(
                watts: watts,
                confidence: .measured,
                explanation: "Measured directly from the battery: terminal voltage × discharge current."
            )

        case .charging:
            guard let adapterWatts = adapter?.negotiatedWatts else { return .unavailable }
            let chargePower = max(batteryFlowWatts ?? 0, 0)
            let watts = clampPlausible(adapterWatts - chargePower)
            return DrawEstimate(
                watts: watts,
                confidence: .estimated,
                explanation: String(
                    format: "Estimated: %.0f W negotiated from the adapter − %.1f W going into the battery. Adapter figures are a negotiated ceiling, so this is an upper bound.",
                    adapterWatts, chargePower
                )
            )

        case .fullyCharged, .chargingPaused:
            guard let adapterWatts = adapter?.negotiatedWatts else { return .unavailable }
            let chargePower = max(batteryFlowWatts ?? 0, 0)
            let watts = clampPlausible(adapterWatts - chargePower)
            return DrawEstimate(
                watts: watts,
                confidence: .estimated,
                explanation: "Estimated from the adapter's negotiated envelope. With the battery full there is no current through the cell to measure, so this is an upper bound on what the machine is using."
            )

        case .noBattery, .unknown:
            guard let adapterWatts = adapter?.negotiatedWatts else { return .unavailable }
            return DrawEstimate(
                watts: clampPlausible(adapterWatts),
                confidence: .estimated,
                explanation: "Estimated from the adapter's negotiated envelope; no battery sensor is available on this machine."
            )
        }
    }

    /// Keeps a computed wattage inside the range of physically believable values.
    public static func clampPlausible(_ watts: Double) -> Double {
        guard watts.isFinite else { return minimumPlausibleWatts }
        return watts.clamped(to: minimumPlausibleWatts...maximumPlausibleWatts)
    }

    // MARK: - Projections

    /// Hours of runtime left, from remaining energy and current draw.
    /// Returns nil rather than infinity when the draw is negligible.
    public static func projectedRuntime(remainingWattHours: Double?, drawWatts: Double?) -> TimeInterval? {
        guard
            let remainingWattHours, remainingWattHours > 0,
            let drawWatts, drawWatts >= 0.5
        else { return nil }
        let hours = remainingWattHours / drawWatts
        guard hours.isFinite, hours < 72 else { return nil }
        return hours * 3600
    }

    /// Time to reach `targetPercent` at the current charge rate.
    public static func projectedTimeToCharge(
        currentPercent: Double,
        targetPercent: Double,
        fullChargeCapacityMilliampHours: Double?,
        volts: Double?,
        chargeWatts: Double?
    ) -> TimeInterval? {
        guard
            targetPercent > currentPercent,
            let capacity = fullChargeCapacityMilliampHours, capacity > 0,
            let volts, volts > 0,
            let chargeWatts, chargeWatts >= 0.5
        else { return nil }
        let fullWattHours = (capacity / 1000.0) * volts
        let missingWattHours = fullWattHours * ((targetPercent - currentPercent) / 100.0)
        let hours = missingWattHours / chargeWatts
        guard hours.isFinite, hours < 48 else { return nil }
        return hours * 3600
    }

    /// Energy consumed between two samples, watt-hours, by the trapezoid rule.
    public static func wattHours(fromWatts a: Double, to b: Double, seconds: TimeInterval) -> Double {
        guard seconds > 0, seconds < 3600 * 6, a.isFinite, b.isFinite else { return 0 }
        return ((a + b) / 2.0) * (seconds / 3600.0)
    }

    /// How hard the machine is working, 0...1, used to drive animation intensity.
    /// 3 W is an idle, lid-dimmed machine; 45 W is a compile with the GPU pinned.
    public static func intensity(forWatts watts: Double?) -> Double {
        guard let watts, watts.isFinite else { return 0.25 }
        let normalized = (watts - 3.0) / (45.0 - 3.0)
        return normalized.clamped(to: 0...1)
    }
}
