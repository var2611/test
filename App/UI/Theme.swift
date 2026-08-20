import SwiftUI
import WattsonCore

/// Colours for one mascot skin. Kept as plain values (not asset catalog entries) so
/// a skin can be added in one place and used by the menu bar, the dashboard and the
/// overlay without touching a resource bundle.
struct MascotPalette {
    var shell: Color
    var shellHighlight: Color
    var outline: Color
    var fillHigh: Color
    var fillMedium: Color
    var fillLow: Color
    var accent: Color
    var eye: Color
    var glow: Color

    /// The fill colour for a charge level, so the character reads at a glance even
    /// with the numbers hidden.
    func fill(for level: Double) -> Color {
        switch level {
        case ..<0.10: return fillLow
        case ..<0.25: return fillMedium
        default: return fillHigh
        }
    }

    func gradient(for level: Double) -> LinearGradient {
        LinearGradient(
            colors: [fill(for: level).opacity(0.95), fill(for: level).opacity(0.65)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension MascotSkin {

    var palette: MascotPalette {
        switch self {
        case .classic:
            return MascotPalette(
                shell: Color(red: 0.98, green: 0.98, blue: 1.0),
                shellHighlight: .white,
                outline: Color(red: 0.13, green: 0.14, blue: 0.20),
                fillHigh: Color(red: 0.29, green: 0.84, blue: 0.47),
                fillMedium: Color(red: 0.98, green: 0.72, blue: 0.20),
                fillLow: Color(red: 0.95, green: 0.33, blue: 0.35),
                accent: Color(red: 0.36, green: 0.55, blue: 0.98),
                eye: Color(red: 0.10, green: 0.11, blue: 0.16),
                glow: Color(red: 0.29, green: 0.84, blue: 0.47)
            )
        case .retro:
            return MascotPalette(
                shell: Color(red: 0.95, green: 0.91, blue: 0.80),
                shellHighlight: Color(red: 0.99, green: 0.97, blue: 0.90),
                outline: Color(red: 0.24, green: 0.19, blue: 0.15),
                fillHigh: Color(red: 0.85, green: 0.62, blue: 0.24),
                fillMedium: Color(red: 0.80, green: 0.45, blue: 0.20),
                fillLow: Color(red: 0.70, green: 0.24, blue: 0.20),
                accent: Color(red: 0.36, green: 0.44, blue: 0.36),
                eye: Color(red: 0.20, green: 0.16, blue: 0.13),
                glow: Color(red: 0.90, green: 0.70, blue: 0.35)
            )
        case .neon:
            return MascotPalette(
                shell: Color(red: 0.09, green: 0.10, blue: 0.18),
                shellHighlight: Color(red: 0.16, green: 0.18, blue: 0.30),
                outline: Color(red: 0.55, green: 0.95, blue: 1.0),
                fillHigh: Color(red: 0.20, green: 1.0, blue: 0.80),
                fillMedium: Color(red: 1.0, green: 0.85, blue: 0.25),
                fillLow: Color(red: 1.0, green: 0.30, blue: 0.55),
                accent: Color(red: 0.55, green: 0.95, blue: 1.0),
                eye: Color(red: 0.85, green: 1.0, blue: 1.0),
                glow: Color(red: 0.30, green: 1.0, blue: 0.90)
            )
        case .pixel:
            return MascotPalette(
                shell: Color(red: 0.85, green: 0.87, blue: 0.90),
                shellHighlight: Color(red: 0.96, green: 0.97, blue: 1.0),
                outline: .black,
                fillHigh: Color(red: 0.22, green: 0.75, blue: 0.30),
                fillMedium: Color(red: 0.95, green: 0.78, blue: 0.15),
                fillLow: Color(red: 0.86, green: 0.20, blue: 0.20),
                accent: Color(red: 0.25, green: 0.35, blue: 0.85),
                eye: .black,
                glow: Color(red: 0.30, green: 0.85, blue: 0.40)
            )
        case .vaporwave:
            return MascotPalette(
                shell: Color(red: 0.98, green: 0.85, blue: 0.95),
                shellHighlight: Color(red: 1.0, green: 0.95, blue: 0.99),
                outline: Color(red: 0.35, green: 0.15, blue: 0.45),
                fillHigh: Color(red: 0.45, green: 0.85, blue: 0.95),
                fillMedium: Color(red: 0.98, green: 0.70, blue: 0.85),
                fillLow: Color(red: 0.95, green: 0.35, blue: 0.60),
                accent: Color(red: 0.70, green: 0.45, blue: 0.95),
                eye: Color(red: 0.30, green: 0.12, blue: 0.40),
                glow: Color(red: 0.85, green: 0.55, blue: 1.0)
            )
        case .ghostly:
            return MascotPalette(
                shell: Color.white.opacity(0.88),
                shellHighlight: .white,
                outline: Color(red: 0.35, green: 0.40, blue: 0.55).opacity(0.8),
                fillHigh: Color(red: 0.60, green: 0.80, blue: 0.95).opacity(0.8),
                fillMedium: Color(red: 0.80, green: 0.80, blue: 0.95).opacity(0.8),
                fillLow: Color(red: 0.85, green: 0.60, blue: 0.75).opacity(0.8),
                accent: Color(red: 0.55, green: 0.65, blue: 0.90),
                eye: Color(red: 0.25, green: 0.30, blue: 0.45),
                glow: Color(red: 0.75, green: 0.85, blue: 1.0)
            )
        case .robot:
            return MascotPalette(
                shell: Color(red: 0.72, green: 0.75, blue: 0.80),
                shellHighlight: Color(red: 0.90, green: 0.92, blue: 0.96),
                outline: Color(red: 0.18, green: 0.20, blue: 0.24),
                fillHigh: Color(red: 0.30, green: 0.78, blue: 0.95),
                fillMedium: Color(red: 0.95, green: 0.70, blue: 0.25),
                fillLow: Color(red: 0.92, green: 0.30, blue: 0.30),
                accent: Color(red: 0.30, green: 0.78, blue: 0.95),
                eye: Color(red: 0.10, green: 0.90, blue: 1.0),
                glow: Color(red: 0.35, green: 0.85, blue: 1.0)
            )
        }
    }

    /// Pixel skins draw with hard edges; everything else is smooth.
    var isChunky: Bool { self == .pixel }
}

extension MascotMood {

    /// The tint used for status chips, gauges and the runner's trail.
    var tint: Color {
        switch self {
        case .panicking: return Color(red: 0.95, green: 0.26, blue: 0.30)
        case .sweating: return Color(red: 0.98, green: 0.65, blue: 0.18)
        case .turbo: return Color(red: 1.0, green: 0.45, blue: 0.20)
        case .working: return Color(red: 0.42, green: 0.60, blue: 0.98)
        case .chill: return Color(red: 0.29, green: 0.80, blue: 0.55)
        case .sipping, .guzzling: return Color(red: 0.25, green: 0.72, blue: 0.95)
        case .fullAndSmug: return Color(red: 0.35, green: 0.82, blue: 0.45)
        case .napping: return Color(red: 0.55, green: 0.58, blue: 0.75)
        case .powerSaver: return Color(red: 0.60, green: 0.55, blue: 0.90)
        case .ghost: return Color(red: 0.62, green: 0.66, blue: 0.75)
        }
    }

    var badgeTitle: String {
        switch self {
        case .sipping: return "Sipping"
        case .guzzling: return "Guzzling"
        case .fullAndSmug: return "Smug"
        case .napping: return "Napping"
        case .chill: return "Chill"
        case .working: return "Working"
        case .turbo: return "Turbo"
        case .sweating: return "Sweating"
        case .panicking: return "Panic"
        case .powerSaver: return "Saving"
        case .ghost: return "Ghost"
        }
    }
}

/// Shared visual constants, so spacing and corner radii do not drift between screens.
enum Design {
    static let cardRadius: CGFloat = 14
    static let cardPadding: CGFloat = 14
    static let panelWidth: CGFloat = 380
    static let sectionSpacing: CGFloat = 12

    static func cardBackground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.035)
    }

    static func cardStroke(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07)
    }
}

/// A rounded, quietly tinted container used for every block in the dashboard.
struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var tint: Color = .clear
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Design.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous)
                    .fill(Design.cardBackground(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous)
                            .fill(tint.opacity(0.07))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous)
                    .strokeBorder(Design.cardStroke(colorScheme), lineWidth: 1)
            )
    }
}
