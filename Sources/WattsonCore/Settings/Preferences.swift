import Foundation

public enum ScreenCorner: String, Codable, Sendable, CaseIterable {
    case bottomLeft, bottomRight

    public var title: String { self == .bottomLeft ? "Bottom left" : "Bottom right" }
}

public enum MascotSkin: String, Codable, Sendable, CaseIterable {
    case classic, retro, neon, pixel, vaporwave, ghostly, robot

    public var title: String {
        switch self {
        case .classic: return "Classic"
        case .retro: return "Retro"
        case .neon: return "Neon"
        case .pixel: return "Pixel"
        case .vaporwave: return "Vaporwave"
        case .ghostly: return "Ghostly"
        case .robot: return "Robot"
        }
    }

    public var requiresPro: Bool { self != .classic }
}

public enum RunnerCharacter: String, Codable, Sendable, CaseIterable {
    case wattson, dino, astronaut, corgi, toaster, skater

    public var title: String {
        switch self {
        case .wattson: return "Wattson"
        case .dino: return "Voltasaurus"
        case .astronaut: return "Astro-Amp"
        case .corgi: return "Cor-G"
        case .toaster: return "Sir Toasts-a-lot"
        case .skater: return "Kick-Flip Kilowatt"
        }
    }

    public var requiresPro: Bool { self != .wattson }
}

/// What rides in the menu bar next to the mascot.
public struct MenuBarDisplay: Codable, Sendable, Equatable {
    public var showPercentage: Bool
    public var showWatts: Bool
    public var showTimeRemaining: Bool

    public init(showPercentage: Bool = true, showWatts: Bool = true, showTimeRemaining: Bool = false) {
        self.showPercentage = showPercentage
        self.showWatts = showWatts
        self.showTimeRemaining = showTimeRemaining
    }

    public static let `default` = MenuBarDisplay()
}

/// User-configurable state. Codable so it round-trips through a single defaults key,
/// which keeps migration to one decode with per-field fallbacks.
public struct Preferences: Codable, Sendable, Equatable {

    // Appearance
    public var mascotSkin: MascotSkin
    public var runnerCharacter: RunnerCharacter
    public var runnerCorner: ScreenCorner
    public var runnerScale: Double          // 0.6...2.0
    public var runnerSpeedMultiplier: Double // 0.5...2.5
    public var runnerAutoHideSeconds: Double // 0 = stay until dismissed
    /// Clicking the menu bar mascot sends the runner out for a lap.
    public var showRunnerOnIconClick: Bool
    public var confettiEnabled: Bool
    public var menuBarDisplay: MenuBarDisplay
    public var temperatureUnit: TemperatureUnit

    // Behaviour
    public var refreshIntervalOnAdapter: Double // seconds
    public var refreshIntervalOnBattery: Double // seconds
    public var launchAtLogin: Bool
    public var historyRetentionDays: Int

    // Alerts
    public var alertsEnabled: Bool
    public var lowBatteryPercent: Double
    public var criticalBatteryPercent: Double
    public var notifyOnFullyCharged: Bool
    public var notifyOnPowerSourceChange: Bool
    public var notifyOnHighDraw: Bool
    public var highDrawWatts: Double
    public var notifyOnHighTemperature: Bool
    public var highTemperatureCelsius: Double
    public var quietHoursEnabled: Bool
    public var quietHoursStartHour: Int
    public var quietHoursEndHour: Int

    public init(
        mascotSkin: MascotSkin = .classic,
        runnerCharacter: RunnerCharacter = .wattson,
        runnerCorner: ScreenCorner = .bottomRight,
        runnerScale: Double = 1.0,
        runnerSpeedMultiplier: Double = 1.0,
        runnerAutoHideSeconds: Double = 15,
        showRunnerOnIconClick: Bool = true,
        confettiEnabled: Bool = true,
        menuBarDisplay: MenuBarDisplay = .default,
        temperatureUnit: TemperatureUnit = .celsius,
        refreshIntervalOnAdapter: Double = 2,
        refreshIntervalOnBattery: Double = 5,
        launchAtLogin: Bool = false,
        historyRetentionDays: Int = 30,
        alertsEnabled: Bool = true,
        lowBatteryPercent: Double = 20,
        criticalBatteryPercent: Double = 8,
        notifyOnFullyCharged: Bool = true,
        notifyOnPowerSourceChange: Bool = false,
        notifyOnHighDraw: Bool = false,
        highDrawWatts: Double = 35,
        notifyOnHighTemperature: Bool = false,
        highTemperatureCelsius: Double = 42,
        quietHoursEnabled: Bool = false,
        quietHoursStartHour: Int = 22,
        quietHoursEndHour: Int = 8
    ) {
        self.mascotSkin = mascotSkin
        self.runnerCharacter = runnerCharacter
        self.runnerCorner = runnerCorner
        self.runnerScale = runnerScale
        self.runnerSpeedMultiplier = runnerSpeedMultiplier
        self.runnerAutoHideSeconds = runnerAutoHideSeconds
        self.showRunnerOnIconClick = showRunnerOnIconClick
        self.confettiEnabled = confettiEnabled
        self.menuBarDisplay = menuBarDisplay
        self.temperatureUnit = temperatureUnit
        self.refreshIntervalOnAdapter = refreshIntervalOnAdapter
        self.refreshIntervalOnBattery = refreshIntervalOnBattery
        self.launchAtLogin = launchAtLogin
        self.historyRetentionDays = historyRetentionDays
        self.alertsEnabled = alertsEnabled
        self.lowBatteryPercent = lowBatteryPercent
        self.criticalBatteryPercent = criticalBatteryPercent
        self.notifyOnFullyCharged = notifyOnFullyCharged
        self.notifyOnPowerSourceChange = notifyOnPowerSourceChange
        self.notifyOnHighDraw = notifyOnHighDraw
        self.highDrawWatts = highDrawWatts
        self.notifyOnHighTemperature = notifyOnHighTemperature
        self.highTemperatureCelsius = highTemperatureCelsius
        self.quietHoursEnabled = quietHoursEnabled
        self.quietHoursStartHour = quietHoursStartHour
        self.quietHoursEndHour = quietHoursEndHour
    }

    public static let `default` = Preferences()

    /// Decoding never fails on a missing or added key: every field falls back to its
    /// default. This is what makes shipping a new preference a non-event.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences.default
        self.init(
            mascotSkin: (try? c.decodeIfPresent(MascotSkin.self, forKey: .mascotSkin)) ?? d.mascotSkin,
            runnerCharacter: (try? c.decodeIfPresent(RunnerCharacter.self, forKey: .runnerCharacter)) ?? d.runnerCharacter,
            runnerCorner: (try? c.decodeIfPresent(ScreenCorner.self, forKey: .runnerCorner)) ?? d.runnerCorner,
            runnerScale: (try? c.decodeIfPresent(Double.self, forKey: .runnerScale)) ?? d.runnerScale,
            runnerSpeedMultiplier: (try? c.decodeIfPresent(Double.self, forKey: .runnerSpeedMultiplier)) ?? d.runnerSpeedMultiplier,
            runnerAutoHideSeconds: (try? c.decodeIfPresent(Double.self, forKey: .runnerAutoHideSeconds)) ?? d.runnerAutoHideSeconds,
            showRunnerOnIconClick: (try? c.decodeIfPresent(Bool.self, forKey: .showRunnerOnIconClick)) ?? d.showRunnerOnIconClick,
            confettiEnabled: (try? c.decodeIfPresent(Bool.self, forKey: .confettiEnabled)) ?? d.confettiEnabled,
            menuBarDisplay: (try? c.decodeIfPresent(MenuBarDisplay.self, forKey: .menuBarDisplay)) ?? d.menuBarDisplay,
            temperatureUnit: (try? c.decodeIfPresent(TemperatureUnit.self, forKey: .temperatureUnit)) ?? d.temperatureUnit,
            refreshIntervalOnAdapter: (try? c.decodeIfPresent(Double.self, forKey: .refreshIntervalOnAdapter)) ?? d.refreshIntervalOnAdapter,
            refreshIntervalOnBattery: (try? c.decodeIfPresent(Double.self, forKey: .refreshIntervalOnBattery)) ?? d.refreshIntervalOnBattery,
            launchAtLogin: (try? c.decodeIfPresent(Bool.self, forKey: .launchAtLogin)) ?? d.launchAtLogin,
            historyRetentionDays: (try? c.decodeIfPresent(Int.self, forKey: .historyRetentionDays)) ?? d.historyRetentionDays,
            alertsEnabled: (try? c.decodeIfPresent(Bool.self, forKey: .alertsEnabled)) ?? d.alertsEnabled,
            lowBatteryPercent: (try? c.decodeIfPresent(Double.self, forKey: .lowBatteryPercent)) ?? d.lowBatteryPercent,
            criticalBatteryPercent: (try? c.decodeIfPresent(Double.self, forKey: .criticalBatteryPercent)) ?? d.criticalBatteryPercent,
            notifyOnFullyCharged: (try? c.decodeIfPresent(Bool.self, forKey: .notifyOnFullyCharged)) ?? d.notifyOnFullyCharged,
            notifyOnPowerSourceChange: (try? c.decodeIfPresent(Bool.self, forKey: .notifyOnPowerSourceChange)) ?? d.notifyOnPowerSourceChange,
            notifyOnHighDraw: (try? c.decodeIfPresent(Bool.self, forKey: .notifyOnHighDraw)) ?? d.notifyOnHighDraw,
            highDrawWatts: (try? c.decodeIfPresent(Double.self, forKey: .highDrawWatts)) ?? d.highDrawWatts,
            notifyOnHighTemperature: (try? c.decodeIfPresent(Bool.self, forKey: .notifyOnHighTemperature)) ?? d.notifyOnHighTemperature,
            highTemperatureCelsius: (try? c.decodeIfPresent(Double.self, forKey: .highTemperatureCelsius)) ?? d.highTemperatureCelsius,
            quietHoursEnabled: (try? c.decodeIfPresent(Bool.self, forKey: .quietHoursEnabled)) ?? d.quietHoursEnabled,
            quietHoursStartHour: (try? c.decodeIfPresent(Int.self, forKey: .quietHoursStartHour)) ?? d.quietHoursStartHour,
            quietHoursEndHour: (try? c.decodeIfPresent(Int.self, forKey: .quietHoursEndHour)) ?? d.quietHoursEndHour
        )
    }

    /// Forces every value into a range the app can actually render, so a corrupted
    /// defaults plist cannot produce a 400-pixel-tall runner or a 0.001 s timer.
    public func validated() -> Preferences {
        var p = self
        p.runnerScale = p.runnerScale.clamped(to: 0.6...2.0)
        p.runnerSpeedMultiplier = p.runnerSpeedMultiplier.clamped(to: 0.5...2.5)
        p.runnerAutoHideSeconds = p.runnerAutoHideSeconds.clamped(to: 0...600)
        p.refreshIntervalOnAdapter = p.refreshIntervalOnAdapter.clamped(to: 1...60)
        p.refreshIntervalOnBattery = p.refreshIntervalOnBattery.clamped(to: 2...120)
        p.historyRetentionDays = p.historyRetentionDays.clamped(to: 1...90)
        p.lowBatteryPercent = p.lowBatteryPercent.clamped(to: 5...50)
        p.criticalBatteryPercent = p.criticalBatteryPercent.clamped(to: 2...p.lowBatteryPercent - 1)
        p.highDrawWatts = p.highDrawWatts.clamped(to: 10...150)
        p.highTemperatureCelsius = p.highTemperatureCelsius.clamped(to: 30...60)
        p.quietHoursStartHour = p.quietHoursStartHour.clamped(to: 0...23)
        p.quietHoursEndHour = p.quietHoursEndHour.clamped(to: 0...23)
        return p
    }

    /// Applied whenever the Pro entitlement is absent or lapses, so a lapsed
    /// subscriber sees a working free app rather than a broken paid one.
    public func downgradedToFreeTier() -> Preferences {
        var p = self
        if p.mascotSkin.requiresPro { p.mascotSkin = .classic }
        if p.runnerCharacter.requiresPro { p.runnerCharacter = .wattson }
        p.runnerScale = 1.0
        p.runnerSpeedMultiplier = 1.0
        p.menuBarDisplay = .default
        p.historyRetentionDays = min(p.historyRetentionDays, 1)
        p.notifyOnHighDraw = false
        p.notifyOnHighTemperature = false
        p.quietHoursEnabled = false
        p.lowBatteryPercent = Preferences.default.lowBatteryPercent
        p.criticalBatteryPercent = Preferences.default.criticalBatteryPercent
        return p
    }

    public var moodThresholds: MoodThresholds {
        MoodThresholds(lowPercent: lowBatteryPercent, criticalPercent: criticalBatteryPercent)
    }

    public var historyRetentionInterval: TimeInterval {
        TimeInterval(historyRetentionDays) * 24 * 3600
    }
}
