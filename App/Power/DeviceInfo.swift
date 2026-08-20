import Foundation

/// Facts about the machine that never change while the app is running.
/// Read once at launch — `sysctl` is cheap, but not free, and none of this moves.
struct DeviceInfo: Sendable, Equatable {

    let chipName: String
    let isAppleSilicon: Bool
    let performanceCoreCount: Int?
    let efficiencyCoreCount: Int?
    let memoryGigabytes: Double?
    let modelIdentifier: String?
    let systemVersion: String

    static let current: DeviceInfo = {
        let brand = DeviceInfo.sysctlString("machdep.cpu.brand_string")
        let isARM = DeviceInfo.sysctlInt("hw.optional.arm64") == 1
        let version = ProcessInfo.processInfo.operatingSystemVersion

        return DeviceInfo(
            chipName: brand ?? (isARM ? "Apple silicon" : "Intel"),
            isAppleSilicon: isARM,
            performanceCoreCount: DeviceInfo.sysctlInt("hw.perflevel0.logicalcpu"),
            efficiencyCoreCount: DeviceInfo.sysctlInt("hw.perflevel1.logicalcpu"),
            memoryGigabytes: DeviceInfo.sysctlInt("hw.memsize").map { Double($0) / 1_073_741_824.0 },
            modelIdentifier: DeviceInfo.sysctlString("hw.model"),
            systemVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        )
    }()

    /// "Apple M3 Pro · 12 cores · 18 GB · macOS 14.4.1"
    var summaryLine: String {
        var parts: [String] = [chipName]
        if let performanceCoreCount, let efficiencyCoreCount {
            parts.append("\(performanceCoreCount)P + \(efficiencyCoreCount)E cores")
        }
        if let memoryGigabytes {
            parts.append(String(format: "%.0f GB", memoryGigabytes))
        }
        parts.append("macOS \(systemVersion)")
        return parts.joined(separator: " · ")
    }

    // MARK: - sysctl helpers

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0, size < 4096 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let value = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}
