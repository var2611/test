import Foundation

/// Raw battery current jitters by a watt or two between reads, which makes a live
/// wattage readout flicker unpleasantly. This applies an exponential moving average
/// to the wattage fields only — percentages, states and health pass through untouched.
///
/// The average is reset whenever the charge state changes, so unplugging the machine
/// snaps to the new value instead of gliding down to it over ten seconds.
public struct SnapshotSmoother: Sendable {

    /// 0 = never update, 1 = no smoothing. 0.35 settles in roughly four samples.
    public let alpha: Double

    private var smoothedDraw: Double?
    private var smoothedFlow: Double?
    private var lastState: ChargeState?

    public init(alpha: Double = 0.35) {
        self.alpha = alpha.clamped(to: 0.05...1.0)
    }

    public mutating func reset() {
        smoothedDraw = nil
        smoothedFlow = nil
        lastState = nil
    }

    public mutating func smooth(_ snapshot: PowerSnapshot) -> PowerSnapshot {
        if lastState != snapshot.chargeState {
            smoothedDraw = nil
            smoothedFlow = nil
            lastState = snapshot.chargeState
        }

        var result = snapshot
        result.systemDrawWatts = blend(previous: &smoothedDraw, next: snapshot.systemDrawWatts)
        result.batteryFlowWatts = blend(previous: &smoothedFlow, next: snapshot.batteryFlowWatts)
        return result
    }

    private func blend(previous: inout Double?, next: Double?) -> Double? {
        guard let next, next.isFinite else {
            // Keep the last good value out of the way; a missing reading should not
            // poison the average, but it also must not be presented as current.
            return nil
        }
        guard let current = previous else {
            previous = next
            return next
        }
        let blended = current + alpha * (next - current)
        previous = blended
        return blended
    }
}
