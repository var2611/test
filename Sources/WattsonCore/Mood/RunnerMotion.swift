import Foundation

/// How the corner runner should move for a given power situation.
///
/// The whole point of the overlay is that it is a *readout*: the faster the
/// character runs, the more the machine is burning. That mapping is defined here,
/// away from the drawing code, so it can be reasoned about and tested.
public struct RunnerMotion: Sendable, Equatable {

    /// Strides per second — drives the leg cycle.
    public var strideRate: Double
    /// Points per second the character travels across the overlay.
    public var travelSpeed: Double
    /// 0...1 exertion, drives sweat, dust and lean angle.
    public var effort: Double
    /// Set when the character should be riding the lightning instead of running.
    public var isCharging: Bool
    /// Set when the character should be celebrating instead of moving.
    public var isCelebrating: Bool
    /// Set when the character should be trudging (Low Power Mode / very low battery).
    public var isTrudging: Bool

    public init(
        strideRate: Double,
        travelSpeed: Double,
        effort: Double,
        isCharging: Bool,
        isCelebrating: Bool,
        isTrudging: Bool
    ) {
        self.strideRate = strideRate
        self.travelSpeed = travelSpeed
        self.effort = effort
        self.isCharging = isCharging
        self.isCelebrating = isCelebrating
        self.isTrudging = isTrudging
    }

    /// Idle fallback used before the first reading arrives.
    public static let idle = RunnerMotion(
        strideRate: 1.2,
        travelSpeed: 40,
        effort: 0.2,
        isCharging: false,
        isCelebrating: false,
        isTrudging: false
    )

    /// 1.5 strides/s at 3 W up to 7 strides/s at 60 W, clamped at both ends so the
    /// animation is never a slideshow and never a strobe.
    public static func motion(
        for snapshot: PowerSnapshot,
        mood: MascotMood,
        speedMultiplier: Double = 1.0
    ) -> RunnerMotion {
        let watts = snapshot.systemDrawWatts ?? 6
        let normalized = ((watts - 3.0) / 57.0).clamped(to: 0...1)
        let multiplier = speedMultiplier.clamped(to: 0.5...2.5)

        var stride = (1.5 + normalized * 5.5) * multiplier
        var travel = (35.0 + normalized * 175.0) * multiplier
        var effort = normalized

        let trudging = mood == .powerSaver || mood == .sweating || mood == .panicking
        if trudging {
            stride *= 0.55
            travel *= 0.45
            effort = max(effort, 0.75)
        }

        let charging = snapshot.chargeState == .charging
        let celebrating = snapshot.chargeState == .fullyCharged

        if celebrating {
            stride = 2.4 * multiplier
            travel = 0
            effort = 0.1
        }

        return RunnerMotion(
            strideRate: stride.clamped(to: 0.5...9),
            travelSpeed: travel.clamped(to: 0...260),
            effort: effort.clamped(to: 0...1),
            isCharging: charging,
            isCelebrating: celebrating,
            isTrudging: trudging
        )
    }

    /// One-line caption shown on the overlay's HUD chip.
    public func caption(watts: Double?) -> String {
        if isCelebrating { return "100% • victory lap" }
        if isCharging { return "\(Fmt.compactWatts(watts)) • surfing the adapter" }
        if isTrudging { return "\(Fmt.compactWatts(watts)) • conserving" }
        return "\(Fmt.compactWatts(watts)) • \(String(format: "%.1f", strideRate)) strides/s"
    }
}
