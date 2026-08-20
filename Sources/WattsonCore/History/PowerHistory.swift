import Foundation

/// One recorded point. Deliberately tiny: history is kept for weeks and is written
/// to disk on every flush, so each sample is four numbers and a state.
public struct PowerSample: Codable, Sendable, Equatable {
    public var timestamp: Date
    public var percentage: Double
    public var drawWatts: Double?
    public var flowWatts: Double?
    public var state: ChargeState

    public init(
        timestamp: Date,
        percentage: Double,
        drawWatts: Double?,
        flowWatts: Double?,
        state: ChargeState
    ) {
        self.timestamp = timestamp
        self.percentage = percentage
        self.drawWatts = drawWatts
        self.flowWatts = flowWatts
        self.state = state
    }

    public init(snapshot: PowerSnapshot) {
        self.init(
            timestamp: snapshot.timestamp,
            percentage: snapshot.percentage,
            drawWatts: snapshot.systemDrawWatts,
            flowWatts: snapshot.batteryFlowWatts,
            state: snapshot.chargeState
        )
    }
}

/// Aggregate numbers for a window of history.
public struct HistoryStats: Sendable, Equatable {
    public var sampleCount: Int
    public var averageDrawWatts: Double?
    public var peakDrawWatts: Double?
    public var minimumDrawWatts: Double?
    public var energyWattHours: Double
    public var timeOnBattery: TimeInterval
    public var timeOnAdapter: TimeInterval
    /// Percentage points lost per hour while discharging.
    public var dischargeRatePerHour: Double?

    public static let empty = HistoryStats(
        sampleCount: 0,
        averageDrawWatts: nil,
        peakDrawWatts: nil,
        minimumDrawWatts: nil,
        energyWattHours: 0,
        timeOnBattery: 0,
        timeOnAdapter: 0,
        dischargeRatePerHour: nil
    )
}

/// A bounded, append-only ring of samples with the analysis the dashboard needs.
///
/// Bounded is the important word: this is a long-running menu bar process, so the
/// history structure must have a hard ceiling on memory regardless of uptime.
public struct PowerHistory: Codable, Sendable, Equatable {

    /// One sample every 10 s for 30 days would be 259 200 points; the store
    /// downsamples before it hands anything here, so 20 000 covers a month
    /// comfortably at one point per two minutes.
    public static let defaultCapacity = 20_000

    public private(set) var samples: [PowerSample]
    public let capacity: Int

    public init(capacity: Int = PowerHistory.defaultCapacity, samples: [PowerSample] = []) {
        self.capacity = max(capacity, 16)
        self.samples = Array(samples.suffix(self.capacity))
    }

    private enum CodingKeys: String, CodingKey { case samples, capacity }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedCapacity = try container.decodeIfPresent(Int.self, forKey: .capacity) ?? PowerHistory.defaultCapacity
        let decodedSamples = try container.decodeIfPresent([PowerSample].self, forKey: .samples) ?? []
        self.init(capacity: decodedCapacity, samples: decodedSamples)
    }

    public var isEmpty: Bool { samples.isEmpty }
    public var count: Int { samples.count }
    public var latest: PowerSample? { samples.last }

    public mutating func append(_ sample: PowerSample) {
        samples.append(sample)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    public mutating func append(snapshot: PowerSnapshot) {
        append(PowerSample(snapshot: snapshot))
    }

    /// Drops everything older than `interval` before now.
    public mutating func prune(olderThan interval: TimeInterval, now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-interval)
        // Samples are chronological, so the first surviving index bounds the drop.
        guard let firstKept = samples.firstIndex(where: { $0.timestamp >= cutoff }) else {
            samples.removeAll()
            return
        }
        if firstKept > 0 { samples.removeFirst(firstKept) }
    }

    public func samples(within interval: TimeInterval, now: Date = Date()) -> [PowerSample] {
        let cutoff = now.addingTimeInterval(-interval)
        return samples.filter { $0.timestamp >= cutoff }
    }

    /// Reduces a window to at most `buckets` points for drawing, averaging within
    /// each bucket so that spikes do not disappear between frames.
    public func downsampled(within interval: TimeInterval, buckets: Int, now: Date = Date()) -> [PowerSample] {
        let window = samples(within: interval, now: now)
        guard buckets > 0 else { return [] }
        guard window.count > buckets else { return window }

        let bucketSize = Double(window.count) / Double(buckets)
        var result: [PowerSample] = []
        result.reserveCapacity(buckets)

        for index in 0..<buckets {
            let start = Int(Double(index) * bucketSize)
            let end = min(Int(Double(index + 1) * bucketSize), window.count)
            guard start < end else { continue }
            let slice = window[start..<end]

            let draws = slice.compactMap(\.drawWatts)
            let flows = slice.compactMap(\.flowWatts)
            let midpoint = slice[slice.startIndex + slice.count / 2]

            result.append(
                PowerSample(
                    timestamp: midpoint.timestamp,
                    percentage: slice.reduce(0) { $0 + $1.percentage } / Double(slice.count),
                    drawWatts: draws.isEmpty ? nil : draws.reduce(0, +) / Double(draws.count),
                    flowWatts: flows.isEmpty ? nil : flows.reduce(0, +) / Double(flows.count),
                    state: midpoint.state
                )
            )
        }
        return result
    }

    /// Aggregate analysis over a window.
    public func stats(within interval: TimeInterval, now: Date = Date()) -> HistoryStats {
        let window = samples(within: interval, now: now)
        guard !window.isEmpty else { return .empty }

        let draws = window.compactMap(\.drawWatts).filter { $0.isFinite }
        var energy: Double = 0
        var onBattery: TimeInterval = 0
        var onAdapter: TimeInterval = 0
        var dischargePercent: Double = 0
        var dischargeSeconds: TimeInterval = 0

        for index in 1..<max(window.count, 1) {
            let previous = window[index - 1]
            let current = window[index]
            let seconds = current.timestamp.timeIntervalSince(previous.timestamp)
            guard seconds > 0, seconds < 3600 * 6 else { continue }

            if let a = previous.drawWatts, let b = current.drawWatts {
                energy += PowerMath.wattHours(fromWatts: a, to: b, seconds: seconds)
            }

            if current.state.isPluggedIn {
                onAdapter += seconds
            } else {
                onBattery += seconds
                if current.state == .discharging, previous.state == .discharging {
                    let delta = previous.percentage - current.percentage
                    if delta > 0 {
                        dischargePercent += delta
                        dischargeSeconds += seconds
                    }
                }
            }
        }

        var rate: Double?
        if dischargeSeconds > 60 {
            rate = dischargePercent / (dischargeSeconds / 3600.0)
        }

        return HistoryStats(
            sampleCount: window.count,
            averageDrawWatts: draws.isEmpty ? nil : draws.reduce(0, +) / Double(draws.count),
            peakDrawWatts: draws.max(),
            minimumDrawWatts: draws.min(),
            energyWattHours: energy,
            timeOnBattery: onBattery,
            timeOnAdapter: onAdapter,
            dischargeRatePerHour: rate
        )
    }

    /// CSV for the Pro export, RFC 4180 shaped and ISO-8601 timestamped.
    public func csv(within interval: TimeInterval, now: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var lines = ["timestamp,percentage,system_draw_w,battery_flow_w,state"]
        for sample in samples(within: interval, now: now) {
            let draw = sample.drawWatts.map { String(format: "%.2f", $0) } ?? ""
            let flow = sample.flowWatts.map { String(format: "%.2f", $0) } ?? ""
            lines.append(
                "\(formatter.string(from: sample.timestamp)),"
                + String(format: "%.1f", sample.percentage) + ","
                + draw + "," + flow + ","
                + sample.state.rawValue
            )
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
