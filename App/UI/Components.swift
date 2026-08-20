import SwiftUI
import WattsonCore

/// The charge ring. Reads as a battery level from across the room, which is the
/// whole job of the top of the dashboard.
@MainActor
struct RingGauge: View {

    let fraction: Double
    let tint: Color
    let centreTop: String
    let centreBottom: String
    var lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.15), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(fraction.clamped(to: 0...1), 0.005))
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.65), tint, tint.opacity(0.85)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.45), value: fraction)

            VStack(spacing: 0) {
                Text(centreTop)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(centreBottom)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(centreTop) \(centreBottom)")
    }
}

/// The live wattage readout, with the confidence badge that keeps the app honest.
@MainActor
struct FlowMeter: View {

    let watts: Double?
    let confidence: MeasurementConfidence
    let tint: Color
    let explanation: String
    /// Scale ceiling for the bar, in watts.
    var ceiling: Double = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.watts(watts))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: watts)

                ConfidenceBadge(confidence: confidence)
                    .help(explanation)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.15))
                    Capsule()
                        .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * barFraction)
                        .animation(.easeInOut(duration: 0.4), value: barFraction)
                }
            }
            .frame(height: 8)

            Text("System draw")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .help(explanation)
    }

    private var barFraction: Double {
        guard let watts, watts.isFinite, ceiling > 0 else { return 0 }
        return (watts / ceiling).clamped(to: 0...1)
    }
}

@MainActor
struct ConfidenceBadge: View {
    let confidence: MeasurementConfidence

    var body: some View {
        Text(confidence.badge)
            .font(.system(size: 9, weight: .semibold))
            .textCase(.uppercase)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch confidence {
        case .measured: return Color(red: 0.20, green: 0.70, blue: 0.45)
        case .estimated: return Color(red: 0.95, green: 0.62, blue: 0.15)
        case .unavailable: return .secondary
        }
    }
}

/// A small labelled figure. Used in rows of three or four across the dashboard.
@MainActor
struct StatTile: View {
    let title: String
    let value: String
    var systemImage: String?
    var tint: Color = .secondary
    var help: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(help ?? "")
    }
}

/// Draw history over time. Two series in one plot: wattage as an area, charge level
/// as a thin line, with plugged-in stretches shaded so the shape of a day is legible.
@MainActor
struct PowerSparkline: View {

    let samples: [PowerSample]
    let tint: Color
    var showsLevel: Bool = true

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let maxWatts = max(samples.compactMap(\.drawWatts).max() ?? 1, 1)

            ZStack {
                if samples.count < 2 {
                    Text("Collecting data…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Canvas { context, canvasSize in
                        draw(in: &context, size: canvasSize, maxWatts: maxWatts)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, maxWatts: Double) {
        let count = samples.count
        guard count > 1, size.width > 1, size.height > 1 else { return }

        func x(_ index: Int) -> CGFloat {
            size.width * CGFloat(index) / CGFloat(count - 1)
        }

        // Shade the stretches spent on the adapter.
        var index = 0
        while index < count {
            guard samples[index].state.isPluggedIn else {
                index += 1
                continue
            }
            let start = index
            while index < count, samples[index].state.isPluggedIn { index += 1 }
            let rect = CGRect(x: x(start), y: 0, width: max(x(index - 1) - x(start), 1), height: size.height)
            context.fill(Path(rect), with: .color(tint.opacity(0.10)))
        }

        // Wattage area.
        var area = Path()
        area.move(to: CGPoint(x: 0, y: size.height))
        for (position, sample) in samples.enumerated() {
            let watts = sample.drawWatts ?? 0
            let y = size.height - (watts / maxWatts) * size.height * 0.92
            area.addLine(to: CGPoint(x: x(position), y: y))
        }
        area.addLine(to: CGPoint(x: size.width, y: size.height))
        area.closeSubpath()

        context.fill(
            area,
            with: .linearGradient(
                Gradient(colors: [tint.opacity(0.45), tint.opacity(0.05)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )

        var line = Path()
        for (position, sample) in samples.enumerated() {
            let watts = sample.drawWatts ?? 0
            let point = CGPoint(x: x(position), y: size.height - (watts / maxWatts) * size.height * 0.92)
            position == 0 ? line.move(to: point) : line.addLine(to: point)
        }
        context.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))

        guard showsLevel else { return }
        var level = Path()
        for (position, sample) in samples.enumerated() {
            let point = CGPoint(x: x(position), y: size.height - (sample.percentage / 100) * size.height * 0.92)
            position == 0 ? level.move(to: point) : level.addLine(to: point)
        }
        context.stroke(
            level,
            with: .color(.secondary.opacity(0.55)),
            style: StrokeStyle(lineWidth: 1.2, dash: [3, 2])
        )
    }
}

/// A labelled row inside the health and adapter cards.
@MainActor
struct DetailRow: View {
    let label: String
    let value: String
    var tint: Color?

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint ?? .primary)
        }
    }
}

/// The "Pro" marker used on locked controls.
@MainActor
struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 8, weight: .heavy))
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.98, green: 0.72, blue: 0.20), Color(red: 0.96, green: 0.45, blue: 0.30)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Capsule()
            )
            .foregroundStyle(.white)
    }
}

/// A speech bubble, because a mascot without dialogue is just a graph.
@MainActor
struct SpeechBubble: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(tint.opacity(0.25), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
    }
}
