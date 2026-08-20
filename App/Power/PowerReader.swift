import Foundation
import IOKit
import IOKit.ps
import WattsonCore

/// Anything that can produce a snapshot of the machine's power state.
/// The protocol exists so the UI can be driven by a simulator during development
/// and by the real hardware in production, with no `#if DEBUG` inside the views.
protocol PowerReading: AnyObject {
    func read() -> PowerSnapshot
}

/// Reads the real machine.
///
/// Two public, sandbox-safe sources are combined:
///
/// 1. `IOPowerSources` — the same API the system menu bar uses. Always present,
///    gives level, source, charging flags and macOS's own time estimates.
/// 2. The `AppleSmartBattery` IORegistry node — gives the sensor values that make
///    a wattage readout possible: terminal voltage, signed current, capacities,
///    cycle count, temperature and the attached adapter's negotiation.
///
/// Every single property is treated as optional. A machine that does not publish
/// `Temperature`, or an OS release that renames `AppleRawCurrentCapacity`, degrades
/// one row of the UI — it never blanks the app and never crashes it.
final class IOKitPowerReader: PowerReading {

    private let device: DeviceInfo

    init(device: DeviceInfo = .current) {
        self.device = device
    }

    func read() -> PowerSnapshot {
        let powerSources = readPowerSources()
        let battery = readSmartBattery()
        return assemble(powerSources: powerSources, battery: battery)
    }

    // MARK: - IOPowerSources

    private struct PowerSourceReading {
        var percentage: Double?
        var isCharging: Bool?
        var isCharged: Bool?
        var isPresent: Bool?
        var isExternal: Bool?
        var timeToEmpty: TimeInterval?
        var timeToFull: TimeInterval?
    }

    private func readPowerSources() -> PowerSourceReading {
        var reading = PowerSourceReading()

        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return reading }
        guard let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return reading }

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
            else { continue }

            // Ignore UPSs and Bluetooth mice; only the internal battery matters here.
            if let type = description[kIOPSTypeKey] as? String, type != kIOPSInternalBatteryType { continue }

            reading.isPresent = description[kIOPSIsPresentKey] as? Bool ?? true
            reading.isCharging = description[kIOPSIsChargingKey] as? Bool
            reading.isCharged = description[kIOPSIsChargedKey] as? Bool

            if let current = IOKitPowerReader.number(description, kIOPSCurrentCapacityKey),
               let maximum = IOKitPowerReader.number(description, kIOPSMaxCapacityKey),
               maximum > 0 {
                reading.percentage = (current / maximum) * 100.0
            }

            // macOS reports −1 while it is still calculating an estimate.
            if let minutes = IOKitPowerReader.number(description, kIOPSTimeToEmptyKey), minutes > 0 {
                reading.timeToEmpty = minutes * 60
            }
            if let minutes = IOKitPowerReader.number(description, kIOPSTimeToFullChargeKey), minutes > 0 {
                reading.timeToFull = minutes * 60
            }

            if let state = description[kIOPSPowerSourceStateKey] as? String {
                reading.isExternal = (state == kIOPSACPowerValue)
            }
            break
        }

        return reading
    }

    // MARK: - AppleSmartBattery

    private struct SmartBatteryReading {
        var volts: Double?
        var amps: Double?
        var designCapacity: Double?
        var maxCapacity: Double?
        var currentCapacity: Double?
        var cycleCount: Int?
        var temperatureCelsius: Double?
        var isCharging: Bool?
        var isFullyCharged: Bool?
        var isExternalConnected: Bool?
        var isBatteryInstalled: Bool?
        var isPermanentFailure: Bool
        var adapter: AdapterInfo?
        var rawProperties: [String: String]

        init() {
            isPermanentFailure = false
            rawProperties = [:]
        }
    }

    private func readSmartBattery() -> SmartBatteryReading {
        var reading = SmartBatteryReading()

        guard let matching = IOServiceMatching("AppleSmartBattery") else { return reading }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return reading }
        defer { IOObjectRelease(service) }

        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        let status = IORegistryEntryCreateCFProperties(service, &unmanagedProperties, kCFAllocatorDefault, 0)
        guard status == KERN_SUCCESS,
              let properties = unmanagedProperties?.takeRetainedValue() as? [String: Any]
        else { return reading }

        reading.rawProperties = IOKitPowerReader.flatten(properties)

        reading.isCharging = properties["IsCharging"] as? Bool
        reading.isFullyCharged = properties["FullyCharged"] as? Bool
        reading.isExternalConnected = properties["ExternalConnected"] as? Bool
        reading.isBatteryInstalled = properties["BatteryInstalled"] as? Bool
        reading.cycleCount = (properties["CycleCount"] as? NSNumber)?.intValue
        reading.isPermanentFailure = ((properties["PermanentFailureStatus"] as? NSNumber)?.intValue ?? 0) != 0

        reading.volts = PowerMath.volts(
            fromMillivolts: IOKitPowerReader.number(properties, "Voltage", "AppleRawBatteryVoltage")
        )

        // `Amperage` is signed on Apple silicon. Some firmware publishes it as an
        // unsigned 64-bit value, in which case the two's-complement reading through
        // `int64Value` is the correct negative number.
        if let rawAmperage = IOKitPowerReader.number(properties, "Amperage", "InstantAmperage") {
            reading.amps = PowerMath.amps(fromMilliamps: rawAmperage)
        }

        // Capacities: newer firmware reports `MaxCapacity` as a percentage (100),
        // with the real milliamp-hour figures under the `AppleRaw…` keys.
        reading.designCapacity = IOKitPowerReader.number(properties, "DesignCapacity")
        let rawMax = IOKitPowerReader.number(properties, "AppleRawMaxCapacity")
        let reportedMax = IOKitPowerReader.number(properties, "MaxCapacity")
        reading.maxCapacity = rawMax ?? ((reportedMax ?? 0) > 200 ? reportedMax : nil)

        let rawCurrent = IOKitPowerReader.number(properties, "AppleRawCurrentCapacity")
        let reportedCurrent = IOKitPowerReader.number(properties, "CurrentCapacity")
        reading.currentCapacity = rawCurrent ?? ((reportedCurrent ?? 0) > 200 ? reportedCurrent : nil)

        reading.temperatureCelsius = IOKitPowerReader.temperature(
            from: IOKitPowerReader.number(properties, "Temperature", "VirtualTemperature")
        )

        if let details = properties["AdapterDetails"] as? [String: Any], !details.isEmpty {
            reading.adapter = IOKitPowerReader.adapter(from: details)
        }

        return reading
    }

    // MARK: - Assembly

    private func assemble(powerSources: PowerSourceReading, battery: SmartBatteryReading) -> PowerSnapshot {
        let isBatteryPresent = battery.isBatteryInstalled
            ?? powerSources.isPresent
            ?? (battery.volts != nil)

        let isExternal = battery.isExternalConnected ?? powerSources.isExternal ?? false
        let isCharging = battery.isCharging ?? powerSources.isCharging ?? false
        let percentage = powerSources.percentage ?? percentFromCapacities(battery) ?? 0

        // `FullyCharged` is the authoritative flag; the 100% check is a safety net
        // for firmware that reports 100% with the flag still settling.
        let isFull = (battery.isFullyCharged ?? powerSources.isCharged ?? false)
            || (isExternal && percentage >= 99.5 && !isCharging)

        let chargeState: ChargeState
        if !isBatteryPresent {
            chargeState = .noBattery
        } else if isCharging {
            chargeState = .charging
        } else if isExternal {
            // Plugged in and not charging: either finished, or macOS is deliberately
            // holding the level (optimised charging, charge limit, thermal guard).
            chargeState = isFull ? .fullyCharged : .chargingPaused
        } else {
            chargeState = .discharging
        }

        let amps = signedAmps(battery.amps, chargeState: chargeState)
        let flow = PowerMath.batteryFlowWatts(volts: battery.volts, amps: amps)
        let draw = PowerMath.systemDraw(
            chargeState: chargeState,
            batteryFlowWatts: flow,
            adapter: battery.adapter
        )

        let health = BatteryHealth(
            cycleCount: battery.cycleCount,
            designCapacityMilliampHours: battery.designCapacity,
            fullChargeCapacityMilliampHours: battery.maxCapacity,
            currentCapacityMilliampHours: battery.currentCapacity,
            temperatureCelsius: battery.temperatureCelsius,
            conditionRaw: battery.rawProperties["BatteryHealth"] ?? battery.rawProperties["BatteryHealthCondition"],
            isPermanentFailure: battery.isPermanentFailure
        )

        return PowerSnapshot(
            timestamp: Date(),
            isBatteryPresent: isBatteryPresent,
            percentage: percentage,
            source: isExternal ? .wallAdapter : (isBatteryPresent ? .battery : .unknown),
            chargeState: chargeState,
            volts: battery.volts,
            amps: amps,
            batteryFlowWatts: flow,
            systemDrawWatts: draw.watts,
            drawConfidence: draw.confidence,
            timeToEmpty: chargeState == .discharging ? powerSources.timeToEmpty : nil,
            timeToFull: chargeState == .charging ? powerSources.timeToFull : nil,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            adapter: battery.adapter,
            health: health,
            isAppleSilicon: device.isAppleSilicon
        )
    }

    /// Firmware disagrees about whether the current is signed. The charge state is
    /// the ground truth, so the magnitude is trusted and the sign is imposed.
    private func signedAmps(_ amps: Double?, chargeState: ChargeState) -> Double? {
        guard let amps else { return nil }
        let magnitude = abs(amps)
        switch chargeState {
        case .charging: return magnitude
        case .discharging: return -magnitude
        case .fullyCharged, .chargingPaused, .noBattery, .unknown: return amps
        }
    }

    private func percentFromCapacities(_ battery: SmartBatteryReading) -> Double? {
        guard
            let current = battery.currentCapacity,
            let maximum = battery.maxCapacity,
            maximum > 0
        else { return nil }
        return (current / maximum) * 100.0
    }

    // MARK: - Property helpers

    /// First non-nil numeric value among the candidate keys, read through
    /// `NSNumber` so that unsigned 64-bit values reinterpret correctly.
    private static func number(_ properties: [String: Any], _ keys: String...) -> Double? {
        for key in keys {
            guard let value = properties[key] else { continue }
            if let number = value as? NSNumber { return Double(number.int64Value) }
            if let double = value as? Double { return double }
            if let int = value as? Int { return Double(int) }
        }
        return nil
    }

    /// `Temperature` is published in hundredths of a degree Celsius on every Mac
    /// seen so far, but a Kelvin-shaped value is accepted rather than shown as 3000 °C.
    private static func temperature(from raw: Double?) -> Double? {
        guard let raw, raw.isFinite, raw != 0 else { return nil }
        let asCelsius = raw / 100.0
        if (-20...80).contains(asCelsius) { return asCelsius }
        let asKelvin = raw / 100.0 - 273.15
        if (-20...80).contains(asKelvin) { return asKelvin }
        return nil
    }

    private static func adapter(from details: [String: Any]) -> AdapterInfo {
        let name = (details["Name"] as? String)
            ?? (details["Description"] as? String)
            ?? (details["Manufacturer"] as? String)

        let watts = number(details, "Watts").flatMap { $0 > 0 ? $0 : nil }
        let volts = PowerMath.volts(fromMillivolts: number(details, "AdapterVoltage", "Voltage"))
        let amps = number(details, "Current").flatMap { $0 > 0 ? $0 / 1000.0 : nil }

        return AdapterInfo(
            name: name,
            ratedWatts: watts,
            volts: volts,
            amps: amps,
            isWireless: (details["IsWireless"] as? Bool) ?? false,
            familyCode: (details["FamilyCode"] as? NSNumber)?.intValue
        )
    }

    /// A printable view of the whole registry node, used by the Pro diagnostics
    /// inspector. Values are stringified here so the UI never touches CoreFoundation.
    private static func flatten(_ properties: [String: Any], prefix: String = "") -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in properties {
            let path = prefix.isEmpty ? key : "\(prefix).\(key)"
            switch value {
            case let nested as [String: Any]:
                result.merge(flatten(nested, prefix: path)) { current, _ in current }
            case let number as NSNumber:
                result[path] = number.stringValue
            case let string as String:
                result[path] = string
            case let data as Data:
                result[path] = "<\(data.count) bytes>"
            case let array as [Any]:
                result[path] = "[\(array.count) items]"
            default:
                result[path] = String(describing: value)
            }
        }
        return result
    }

    /// Exposed for the diagnostics inspector: the raw registry node, stringified.
    func readRawProperties() -> [String: String] {
        readSmartBattery().rawProperties
    }
}

/// Deterministic fake used by SwiftUI previews and by `--simulate` runs during
/// development, so the animations can be exercised without draining a real battery.
final class SimulatedPowerReader: PowerReading {

    private var percentage: Double = 82
    private var elapsed: Double = 0
    private let script: [(ChargeState, Double)] = [
        (.discharging, 12), (.discharging, 34), (.charging, 45), (.fullyCharged, 9)
    ]

    func read() -> PowerSnapshot {
        elapsed += 1
        let step = script[Int(elapsed / 12) % script.count]
        let state = step.0
        let draw = step.1 + sin(elapsed / 3) * 2

        switch state {
        case .charging: percentage = min(percentage + 0.4, 100)
        case .discharging: percentage = max(percentage - 0.2, 3)
        default: percentage = 100
        }

        let adapter = AdapterInfo(name: "70W USB-C Power Adapter", ratedWatts: 70, volts: 20, amps: 3.5)
        let flow: Double? = state == .charging ? 38 : (state == .discharging ? -draw : 0)

        return PowerSnapshot(
            isBatteryPresent: true,
            percentage: percentage,
            source: state.isPluggedIn ? .wallAdapter : .battery,
            chargeState: state,
            volts: 12.6,
            amps: flow.map { $0 / 12.6 },
            batteryFlowWatts: flow,
            systemDrawWatts: draw,
            drawConfidence: state == .discharging ? .measured : .estimated,
            timeToEmpty: state == .discharging ? 3600 * 4 : nil,
            timeToFull: state == .charging ? 3600 : nil,
            isLowPowerMode: false,
            adapter: state.isPluggedIn ? adapter : nil,
            health: BatteryHealth(
                cycleCount: 142,
                designCapacityMilliampHours: 8694,
                fullChargeCapacityMilliampHours: 8320,
                currentCapacityMilliampHours: 8320 * percentage / 100,
                temperatureCelsius: 30 + sin(elapsed / 20) * 4,
                conditionRaw: "Normal"
            ),
            isAppleSilicon: true
        )
    }
}
