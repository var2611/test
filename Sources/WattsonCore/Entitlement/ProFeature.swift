import Foundation

/// Everything that can be gated. Adding a case here forces every switch that
/// decides availability to be updated, which is exactly the property we want when
/// money is involved.
public enum ProFeature: String, Codable, Sendable, CaseIterable {
    case mascotSkins
    case runnerCharacters
    case extendedHistory
    case customAlerts
    case quietHours
    case deepDiagnostics
    case dataExport
    case menuBarCustomisation
    case runnerPlayground

    public var title: String {
        switch self {
        case .mascotSkins: return "Mascot skins"
        case .runnerCharacters: return "Runner characters"
        case .extendedHistory: return "30-day history & trends"
        case .customAlerts: return "Custom alerts"
        case .quietHours: return "Quiet hours"
        case .deepDiagnostics: return "Deep diagnostics"
        case .dataExport: return "CSV & JSON export"
        case .menuBarCustomisation: return "Menu bar customisation"
        case .runnerPlayground: return "Runner playground"
        }
    }

    public var blurb: String {
        switch self {
        case .mascotSkins: return "Six extra personalities for Wattson, from Pixel to Vaporwave."
        case .runnerCharacters: return "Five more characters for the corner sprint."
        case .extendedHistory: return "A month of power history, energy totals and discharge trends."
        case .customAlerts: return "Alert at your thresholds — low battery, heavy draw, charge limit, heat."
        case .quietHours: return "Silence notifications during the hours you choose."
        case .deepDiagnostics: return "Adapter negotiation, temperature history and a live IOKit inspector."
        case .dataExport: return "Export any window of history as CSV or JSON."
        case .menuBarCustomisation: return "Pick exactly which figures ride in your menu bar."
        case .runnerPlayground: return "Corner, size, speed multiplier and confetti density."
        }
    }

    public var systemImage: String {
        switch self {
        case .mascotSkins: return "paintpalette.fill"
        case .runnerCharacters: return "figure.run"
        case .extendedHistory: return "chart.xyaxis.line"
        case .customAlerts: return "bell.badge.fill"
        case .quietHours: return "moon.zzz.fill"
        case .deepDiagnostics: return "stethoscope"
        case .dataExport: return "square.and.arrow.up.on.square.fill"
        case .menuBarCustomisation: return "menubar.rectangle"
        case .runnerPlayground: return "slider.horizontal.3"
        }
    }
}

/// The free/paid boundary in one testable place.
public struct EntitlementMatrix: Sendable {

    public let isPro: Bool

    public init(isPro: Bool) {
        self.isPro = isPro
    }

    public func isAvailable(_ feature: ProFeature) -> Bool { isPro }

    /// Features that are visible but locked, for the paywall's "what you get" list.
    public var lockedFeatures: [ProFeature] {
        isPro ? [] : ProFeature.allCases
    }

    /// What the free tier always keeps. Written down explicitly because App Review
    /// checks that the free tier is not a demo, and because it is a product promise.
    public static let freeTierPromise: [String] = [
        "Live power source, charge level and charge state",
        "Measured battery flow and system draw in watts",
        "Time to empty and time to full",
        "The animated menu bar mascot with every mood",
        "The corner runner with the default character",
        "Battery health: cycle count and maximum capacity"
    ]
}
