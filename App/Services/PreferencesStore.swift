import Foundation
import Combine
import WattsonCore

/// Owns the single source of truth for user settings.
///
/// Everything lives under one defaults key as JSON, which keeps migration to a
/// single tolerant decode (see `Preferences.init(from:)`) instead of a growing pile
/// of individually-versioned keys.
@MainActor
final class PreferencesStore: ObservableObject {

    private enum Key {
        static let preferences = "com.wattson.preferences.v1"
        static let hasCompletedWelcome = "com.wattson.welcome.completed.v1"
        static let installDate = "com.wattson.installDate.v1"
    }

    @Published private(set) var preferences: Preferences
    @Published var hasCompletedWelcome: Bool {
        didSet { defaults.set(hasCompletedWelcome, forKey: Key.hasCompletedWelcome) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.preferences = PreferencesStore.load(from: defaults)
        self.hasCompletedWelcome = defaults.bool(forKey: Key.hasCompletedWelcome)

        if defaults.object(forKey: Key.installDate) == nil {
            defaults.set(Date(), forKey: Key.installDate)
        }
    }

    var installDate: Date {
        defaults.object(forKey: Key.installDate) as? Date ?? Date()
    }

    /// Mutate settings through here so that validation and persistence can never be
    /// skipped by a caller.
    func update(_ mutate: (inout Preferences) -> Void) {
        var copy = preferences
        mutate(&copy)
        apply(copy)
    }

    func apply(_ newValue: Preferences) {
        let validated = newValue.validated()
        guard validated != preferences else { return }
        preferences = validated
        persist(validated)
    }

    func resetToDefaults() {
        apply(.default)
    }

    /// Called when the Pro entitlement is absent or lapses. Paid settings fall back
    /// to their free equivalents so a lapsed subscriber gets a working free app.
    func enforceFreeTier() {
        apply(preferences.downgradedToFreeTier())
    }

    private func persist(_ value: Preferences) {
        do {
            let data = try JSONEncoder().encode(value)
            defaults.set(data, forKey: Key.preferences)
        } catch {
            // Losing a preference write is survivable; crashing over one is not.
            Log.settings.error("Could not encode preferences: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from defaults: UserDefaults) -> Preferences {
        guard let data = defaults.data(forKey: Key.preferences) else { return .default }
        do {
            return try JSONDecoder().decode(Preferences.self, from: data).validated()
        } catch {
            Log.settings.error("Preferences unreadable, falling back to defaults: \(error.localizedDescription, privacy: .public)")
            return .default
        }
    }
}
