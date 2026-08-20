import Foundation

/// The mascot's personality states. The mapping from a snapshot to a mood is pure
/// and deterministic so that it can be tested, and so that the menu bar art, the
/// dashboard art and the corner runner never disagree about how Wattson feels.
public enum MascotMood: String, Codable, Sendable, CaseIterable {
    /// Plugged in, drinking electricity through a straw.
    case sipping
    /// Plugged in and charging fast — the straw became a firehose.
    case guzzling
    /// Full, plugged in, wearing sunglasses.
    case fullAndSmug
    /// Plugged in but not charging: optimized charging or a charge limit. Napping.
    case napping
    /// On battery, comfortable, low draw.
    case chill
    /// On battery, working hard. Sweatband on, doing reps.
    case working
    /// On battery, burning a lot of watts. On fire, in a good way.
    case turbo
    /// Under 20%. Sweating.
    case sweating
    /// Under 8%. Full panic.
    case panicking
    /// Low Power Mode: wearing a tiny nightcap, moving slowly.
    case powerSaver
    /// No battery detected at all.
    case ghost

    /// Ordered by urgency; used when two conditions could both apply.
    public var urgency: Int {
        switch self {
        case .panicking: return 100
        case .sweating: return 80
        case .turbo: return 60
        case .working: return 40
        case .powerSaver: return 35
        case .guzzling: return 30
        case .sipping: return 25
        case .napping: return 20
        case .fullAndSmug: return 15
        case .chill: return 10
        case .ghost: return 0
        }
    }

    /// True for moods that should pulse/animate energetically.
    public var isEnergetic: Bool {
        switch self {
        case .turbo, .guzzling, .panicking, .working: return true
        default: return false
        }
    }

    public var accessibilityDescription: String {
        switch self {
        case .sipping: return "Charging steadily"
        case .guzzling: return "Charging fast"
        case .fullAndSmug: return "Fully charged and plugged in"
        case .napping: return "Plugged in, charging on hold"
        case .chill: return "On battery, light load"
        case .working: return "On battery, moderate load"
        case .turbo: return "On battery, heavy load"
        case .sweating: return "Battery low"
        case .panicking: return "Battery critically low"
        case .powerSaver: return "Low Power Mode"
        case .ghost: return "No battery detected"
        }
    }
}

/// Thresholds that decide moods, kept in one place so the UI, the alerts and the
/// tests all agree on what "low" means.
public struct MoodThresholds: Sendable, Equatable {
    public var lowPercent: Double
    public var criticalPercent: Double
    public var heavyDrawWatts: Double
    public var moderateDrawWatts: Double
    public var fastChargeWatts: Double

    public init(
        lowPercent: Double = 20,
        criticalPercent: Double = 8,
        heavyDrawWatts: Double = 28,
        moderateDrawWatts: Double = 14,
        fastChargeWatts: Double = 30
    ) {
        self.lowPercent = lowPercent
        self.criticalPercent = criticalPercent
        self.heavyDrawWatts = heavyDrawWatts
        self.moderateDrawWatts = moderateDrawWatts
        self.fastChargeWatts = fastChargeWatts
    }

    public static let standard = MoodThresholds()
}

public enum MascotMoodResolver {

    /// The single source of truth for "how does Wattson feel about this snapshot?".
    public static func mood(
        for snapshot: PowerSnapshot,
        thresholds: MoodThresholds = .standard
    ) -> MascotMood {
        guard snapshot.isBatteryPresent, snapshot.chargeState != .noBattery else {
            return .ghost
        }

        switch snapshot.chargeState {
        case .charging:
            let chargeWatts = max(snapshot.batteryFlowWatts ?? 0, 0)
            // Panic outranks everything: charging at 3% is still an emergency.
            if snapshot.percentage <= thresholds.criticalPercent { return .panicking }
            return chargeWatts >= thresholds.fastChargeWatts ? .guzzling : .sipping

        case .fullyCharged:
            return .fullAndSmug

        case .chargingPaused:
            return .napping

        case .discharging, .unknown, .noBattery:
            if snapshot.percentage <= thresholds.criticalPercent { return .panicking }
            if snapshot.percentage <= thresholds.lowPercent { return .sweating }
            if snapshot.isLowPowerMode { return .powerSaver }
            let draw = snapshot.systemDrawWatts ?? 0
            if draw >= thresholds.heavyDrawWatts { return .turbo }
            if draw >= thresholds.moderateDrawWatts { return .working }
            return .chill
        }
    }

    /// A line of dialogue for the dashboard speech bubble.
    ///
    /// `seed` makes the choice deterministic for a given minute, so the bubble does
    /// not reshuffle on every 2-second refresh — it changes when there is a reason to.
    public static func line(for mood: MascotMood, seed: Int) -> String {
        let lines = dialogue[mood] ?? ["..."]
        let index = abs(seed) % lines.count
        return lines[index]
    }

    /// A deterministic seed that rolls over roughly once a minute.
    public static func dialogueSeed(at date: Date = Date()) -> Int {
        Int(date.timeIntervalSince1970 / 60)
    }

    static let dialogue: [MascotMood: [String]] = [
        .sipping: [
            "Mmm. Electrons. My favourite.",
            "Sipping politely. Don't mind me.",
            "Refilling the tank, one watt at a time.",
            "This charger and I have a beautiful relationship."
        ],
        .guzzling: [
            "CHUG CHUG CHUG!",
            "Fast charging! Hold my straw.",
            "I am inhaling this power brick.",
            "Someone brought the big adapter. Respect."
        ],
        .fullAndSmug: [
            "100%. Nothing to prove. Deal with it.",
            "Full. Powerful. Unbothered.",
            "You may unplug me. I dare you.",
            "Maximum juice achieved. Sunglasses deployed."
        ],
        .napping: [
            "Charging's on hold. I'm having a lie-down.",
            "macOS says wait, so I wait. Zzz.",
            "Optimised charging: fancy words for a nap.",
            "Holding at this level on purpose. Relax."
        ],
        .chill: [
            "Cruising. Barely breaking a sweat.",
            "This is basically a spa day.",
            "Low draw, long runtime, no notes.",
            "I could do this all afternoon."
        ],
        .working: [
            "Alright, we're actually doing work now.",
            "Moderate load. I've got this.",
            "Feel that? That's productivity.",
            "Warming up nicely."
        ],
        .turbo: [
            "TURBO MODE. Everything is fine. Probably.",
            "We are absolutely melting watts right now.",
            "Whatever you just opened — wow.",
            "I'm running. Physically running. Watch the corner."
        ],
        .sweating: [
            "Getting a bit low here, friend...",
            "A charger would be lovely. Just saying.",
            "I'm rationing. This is my rationing face.",
            "20% is a lifestyle, not a crisis. Right? Right?"
        ],
        .panicking: [
            "PLUG ME IN PLUG ME IN PLUG ME IN",
            "This is not a drill!",
            "I can see the light. It's a charging cable.",
            "Tell my story."
        ],
        .powerSaver: [
            "Low Power Mode. I'm in energy-saving pyjamas.",
            "Moving slowly. Conserving everything.",
            "Shhh. We're being frugal.",
            "Every watt counts today."
        ],
        .ghost: [
            "No battery here. I'm just vibes.",
            "Desktop life. Endless power. Slightly boring.",
            "I float. I observe. I have no cell."
        ]
    ]
}
