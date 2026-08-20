import SwiftUI
import WattsonCore

/// Draws Wattson.
///
/// Everything is drawn procedurally in a single `Canvas`, in a normalised
/// 100 × 120 space that is scaled to whatever the caller asks for. That choice
/// matters for a menu bar app: there are no image assets to load, the art is crisp
/// at 18 pt and at 180 pt, it recolours instantly for skins and appearance changes,
/// and one draw call is cheap enough to run at 30 fps without registering on the
/// energy impact chart.
@MainActor
struct MascotView: View {

    let mood: MascotMood
    let skin: MascotSkin
    /// Charge level, 0...1, drives the fill height and colour.
    let level: Double
    /// 0...1 — how hard the machine is working. Drives bounce amplitude.
    var intensity: Double = 0.3
    /// Menu bar rendering: flatter, higher contrast, no drop shadow.
    var isCompact: Bool = false
    /// Frozen art for previews and for the paywall's skin picker.
    var staticPhase: Double?

    var body: some View {
        if let staticPhase {
            canvas(phase: staticPhase)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                canvas(phase: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func canvas(phase: Double) -> some View {
        // Built outside the renderer so the closure captures one plain value.
        let artist = MascotArtist(
            mood: mood,
            palette: skin.palette,
            isChunky: skin.isChunky,
            level: level.clamped(to: 0...1),
            intensity: intensity.clamped(to: 0...1),
            isCompact: isCompact,
            phase: phase
        )
        return Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            artist.draw(in: &context, size: size)
        }
        .accessibilityHidden(true)
    }
}

/// The drawing itself, split out of the view so it can also be used by the runner
/// overlay and by anything else that needs the character on screen.
struct MascotArtist {

    let mood: MascotMood
    let palette: MascotPalette
    let isChunky: Bool
    let level: Double
    let intensity: Double
    let isCompact: Bool
    let phase: Double

    /// The art is authored in this space and scaled to fit.
    private let designSize = CGSize(width: 100, height: 120)

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let scale = min(size.width / designSize.width, size.height / designSize.height)
        guard scale > 0, scale.isFinite else { return }

        let bounce = bounceOffset()

        context.translateBy(
            x: (size.width - designSize.width * scale) / 2,
            y: (size.height - designSize.height * scale) / 2
        )
        context.scaleBy(x: scale, y: scale)

        if !isCompact { drawShadow(in: &context, bounce: bounce) }

        context.translateBy(x: 0, y: bounce)
        if mood == .ghost { context.opacity = 0.75 }

        drawBody(in: &context)
        drawFill(in: &context)
        drawFace(in: &context)
        drawProps(in: &context)
    }

    // MARK: - Motion

    /// A gentle idle bob that becomes an anxious jitter under load, and a hard
    /// bounce when panicking. The mascot's motion is a readout too.
    private func bounceOffset() -> Double {
        switch mood {
        case .panicking:
            return sin(phase * 12) * 3.0
        case .turbo, .guzzling:
            return sin(phase * (6 + intensity * 4)) * (1.6 + intensity)
        case .working:
            return sin(phase * 4) * 1.2
        case .napping, .powerSaver:
            return sin(phase * 1.1) * 1.4
        case .ghost:
            return sin(phase * 1.6) * 3.0
        default:
            return sin(phase * 2.2) * 1.0
        }
    }

    private var blinkOpen: Bool {
        // A 4.3-second cycle keeps blinks from syncing with anything else on screen.
        let cycle = phase.truncatingRemainder(dividingBy: 4.3)
        return cycle > 0.14
    }

    // MARK: - Body

    private var bodyRect: CGRect { CGRect(x: 18, y: 26, width: 64, height: 78) }
    private var cornerRadius: CGFloat { isChunky ? 3 : 16 }
    private var lineWidth: CGFloat { isCompact ? 5 : 4 }

    private func drawShadow(in context: inout GraphicsContext, bounce: Double) {
        let squash = 1.0 - abs(bounce) / 40.0
        let width = 46 * squash
        let rect = CGRect(x: 50 - width / 2, y: 106, width: width, height: 8)
        context.fill(Path(ellipseIn: rect), with: .color(palette.outline.opacity(0.16)))
    }

    private func drawBody(in context: inout GraphicsContext) {
        // The terminal nub on top: the one detail that makes a rounded rectangle
        // read unmistakably as a battery.
        let nub = CGRect(x: 40, y: 16, width: 20, height: 12)
        context.fill(
            Path(roundedRect: nub, cornerRadius: isChunky ? 1 : 4),
            with: .color(palette.outline)
        )

        let body = Path(roundedRect: bodyRect, cornerRadius: cornerRadius)
        context.fill(body, with: .color(palette.shell))
        context.stroke(body, with: .color(palette.outline), lineWidth: lineWidth)

        if !isCompact {
            // A soft highlight down the left edge gives the shell some volume.
            let highlight = Path(
                roundedRect: CGRect(x: 24, y: 33, width: 9, height: 40),
                cornerRadius: 4.5
            )
            context.fill(highlight, with: .color(palette.shellHighlight.opacity(0.55)))
        }
    }

    /// The charge level, drawn as liquid with a surface that ripples while charging.
    private func drawFill(in context: inout GraphicsContext) {
        let inset = lineWidth / 2 + 3
        let inner = bodyRect.insetBy(dx: inset, dy: inset)
        let height = inner.height * level
        guard height > 1 else { return }

        let top = inner.maxY - height
        var path = Path()
        path.move(to: CGPoint(x: inner.minX, y: inner.maxY))
        path.addLine(to: CGPoint(x: inner.minX, y: top))

        if isChunky {
            path.addLine(to: CGPoint(x: inner.maxX, y: top))
        } else {
            // Two arcs make a wave; the amplitude follows how fast energy is moving.
            let amplitude: CGFloat = mood == .guzzling ? 3.0 : (mood == .sipping ? 2.0 : 1.0)
            let offset = sin(phase * 3) * amplitude
            path.addQuadCurve(
                to: CGPoint(x: inner.midX, y: top),
                control: CGPoint(x: inner.minX + inner.width * 0.25, y: top - offset)
            )
            path.addQuadCurve(
                to: CGPoint(x: inner.maxX, y: top),
                control: CGPoint(x: inner.minX + inner.width * 0.75, y: top + offset)
            )
        }

        path.addLine(to: CGPoint(x: inner.maxX, y: inner.maxY))
        path.closeSubpath()

        let clip = Path(roundedRect: inner, cornerRadius: max(cornerRadius - 4, 1))
        context.drawLayer { layer in
            layer.clip(to: clip)
            layer.fill(path, with: .linearGradient(
                Gradient(colors: [palette.fill(for: level), palette.fill(for: level).opacity(0.7)]),
                startPoint: CGPoint(x: inner.midX, y: top),
                endPoint: CGPoint(x: inner.midX, y: inner.maxY)
            ))

            // Charging bolts rising through the liquid.
            if mood == .sipping || mood == .guzzling {
                let count = mood == .guzzling ? 3 : 2
                for index in 0..<count {
                    let progress = (phase * Double(mood == .guzzling ? 1.6 : 1.0) + Double(index) / Double(count))
                        .truncatingRemainder(dividingBy: 1.0)
                    let y = inner.maxY - progress * height
                    let x = inner.minX + inner.width * (0.3 + 0.4 * Double(index) / Double(max(count - 1, 1)))
                    layer.fill(
                        boltPath(centre: CGPoint(x: x, y: y), size: 9),
                        with: .color(.white.opacity(0.5 * (1 - progress)))
                    )
                }
            }
        }
    }

    // MARK: - Face

    private func drawFace(in context: inout GraphicsContext) {
        let leftEye = CGPoint(x: 38, y: 58)
        let rightEye = CGPoint(x: 62, y: 58)

        switch mood {
        case .napping, .powerSaver:
            drawClosedEye(in: &context, at: leftEye)
            drawClosedEye(in: &context, at: rightEye)
        case .fullAndSmug:
            // Sunglasses hide the eyes entirely; they are drawn in `drawProps`.
            break
        default:
            drawEye(in: &context, at: leftEye)
            drawEye(in: &context, at: rightEye)
        }

        drawMouth(in: &context)
    }

    private func drawEye(in context: inout GraphicsContext, at centre: CGPoint) {
        guard blinkOpen else {
            drawClosedEye(in: &context, at: centre)
            return
        }

        let wide = mood == .panicking || mood == .turbo
        let size: CGFloat = wide ? 11 : 9
        let white = CGRect(x: centre.x - size / 2, y: centre.y - size / 2, width: size, height: size)
        context.fill(Path(ellipseIn: white), with: .color(palette.shellHighlight))
        context.stroke(Path(ellipseIn: white), with: .color(palette.outline), lineWidth: 1.5)

        // Pupils drift a little, which is most of what makes a face feel alive.
        let drift = mood == .panicking
            ? CGPoint(x: sin(phase * 14) * 1.6, y: cos(phase * 11) * 1.2)
            : CGPoint(x: sin(phase * 0.8) * 1.1, y: sin(phase * 0.5) * 0.7)

        let pupilSize: CGFloat = wide ? 5 : 4.5
        let pupil = CGRect(
            x: centre.x + drift.x - pupilSize / 2,
            y: centre.y + drift.y - pupilSize / 2,
            width: pupilSize,
            height: pupilSize
        )
        context.fill(Path(ellipseIn: pupil), with: .color(palette.eye))
        context.fill(
            Path(ellipseIn: CGRect(x: pupil.minX + 0.8, y: pupil.minY + 0.6, width: 1.6, height: 1.6)),
            with: .color(.white.opacity(0.9))
        )
    }

    private func drawClosedEye(in context: inout GraphicsContext, at centre: CGPoint) {
        var path = Path()
        path.move(to: CGPoint(x: centre.x - 5, y: centre.y))
        path.addQuadCurve(
            to: CGPoint(x: centre.x + 5, y: centre.y),
            control: CGPoint(x: centre.x, y: centre.y + 4)
        )
        context.stroke(path, with: .color(palette.outline), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    private func drawMouth(in context: inout GraphicsContext) {
        let centre = CGPoint(x: 50, y: 80)
        let stroke = StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)

        switch mood {
        case .chill, .sipping, .napping:
            var path = Path()
            path.move(to: CGPoint(x: centre.x - 8, y: centre.y - 1))
            path.addQuadCurve(
                to: CGPoint(x: centre.x + 8, y: centre.y - 1),
                control: CGPoint(x: centre.x, y: centre.y + 6)
            )
            context.stroke(path, with: .color(palette.outline), style: stroke)

        case .working, .fullAndSmug:
            var path = Path()
            path.move(to: CGPoint(x: centre.x - 9, y: centre.y - 2))
            path.addQuadCurve(
                to: CGPoint(x: centre.x + 9, y: centre.y - 2),
                control: CGPoint(x: centre.x, y: centre.y + 9)
            )
            context.stroke(path, with: .color(palette.outline), style: stroke)

        case .turbo, .guzzling:
            // An open, delighted grin.
            let rect = CGRect(x: centre.x - 10, y: centre.y - 5, width: 20, height: 14)
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control: CGPoint(x: rect.midX, y: rect.maxY + 4)
            )
            path.closeSubpath()
            context.fill(path, with: .color(palette.outline))
            context.fill(
                Path(ellipseIn: CGRect(x: centre.x - 4, y: rect.minY + 6, width: 8, height: 6)),
                with: .color(palette.fillLow.opacity(0.9))
            )

        case .sweating:
            var path = Path()
            path.move(to: CGPoint(x: centre.x - 8, y: centre.y + 2))
            path.addCurve(
                to: CGPoint(x: centre.x + 8, y: centre.y + 2),
                control1: CGPoint(x: centre.x - 3, y: centre.y - 3),
                control2: CGPoint(x: centre.x + 3, y: centre.y + 6)
            )
            context.stroke(path, with: .color(palette.outline), style: stroke)

        case .panicking:
            let wobble = 1 + sin(phase * 16) * 0.15
            let rect = CGRect(x: centre.x - 7 * wobble, y: centre.y - 5, width: 14 * wobble, height: 15)
            context.fill(Path(ellipseIn: rect), with: .color(palette.outline))

        case .powerSaver:
            var path = Path()
            path.move(to: CGPoint(x: centre.x - 7, y: centre.y + 1))
            path.addLine(to: CGPoint(x: centre.x + 7, y: centre.y + 1))
            context.stroke(path, with: .color(palette.outline), style: stroke)

        case .ghost:
            var path = Path()
            path.move(to: CGPoint(x: centre.x - 8, y: centre.y))
            path.addQuadCurve(to: CGPoint(x: centre.x, y: centre.y), control: CGPoint(x: centre.x - 4, y: centre.y + 5))
            path.addQuadCurve(to: CGPoint(x: centre.x + 8, y: centre.y), control: CGPoint(x: centre.x + 4, y: centre.y - 5))
            context.stroke(path, with: .color(palette.outline), style: stroke)
        }
    }

    // MARK: - Props

    private func drawProps(in context: inout GraphicsContext) {
        switch mood {
        case .sipping, .guzzling:
            drawDrink(in: &context)
        case .fullAndSmug:
            drawSunglasses(in: &context)
            drawSparkles(in: &context)
        case .sweating, .panicking:
            drawSweat(in: &context)
            if mood == .panicking { drawArmsUp(in: &context) }
        case .turbo:
            drawFlames(in: &context)
        case .napping, .powerSaver:
            drawNightcap(in: &context)
            drawSnooze(in: &context)
        case .ghost:
            drawGhostTail(in: &context)
        case .chill, .working:
            break
        }
    }

    /// The straw and cup: the joke that makes "charging" instantly readable.
    private func drawDrink(in context: inout GraphicsContext) {
        let cup = CGRect(x: 79, y: 74, width: 17, height: 22)
        var cupPath = Path()
        cupPath.move(to: CGPoint(x: cup.minX, y: cup.minY))
        cupPath.addLine(to: CGPoint(x: cup.maxX, y: cup.minY))
        cupPath.addLine(to: CGPoint(x: cup.maxX - 3, y: cup.maxY))
        cupPath.addLine(to: CGPoint(x: cup.minX + 3, y: cup.maxY))
        cupPath.closeSubpath()

        context.fill(cupPath, with: .color(palette.accent.opacity(0.35)))
        context.stroke(cupPath, with: .color(palette.outline), lineWidth: 2)
        context.fill(
            boltPath(centre: CGPoint(x: cup.midX, y: cup.midY + 2), size: 12),
            with: .color(palette.glow)
        )

        // Straw, bent towards the mouth. It wiggles faster when guzzling.
        let wiggle = sin(phase * (mood == .guzzling ? 10 : 4)) * 1.2
        var straw = Path()
        straw.move(to: CGPoint(x: 60, y: 80))
        straw.addQuadCurve(
            to: CGPoint(x: cup.midX, y: cup.minY - 5),
            control: CGPoint(x: 74 + wiggle, y: 66)
        )
        context.stroke(
            straw,
            with: .color(palette.fillLow),
            style: StrokeStyle(lineWidth: 3, lineCap: .round)
        )

        if mood == .guzzling {
            // Gulp bubbles travelling up the straw.
            for index in 0..<3 {
                let progress = (phase * 1.8 + Double(index) / 3).truncatingRemainder(dividingBy: 1.0)
                let point = CGPoint(x: 60 + (cup.midX - 60) * progress, y: 80 - 12 * progress)
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)),
                    with: .color(.white.opacity(0.7 * (1 - progress)))
                )
            }
        }
    }

    private func drawSunglasses(in context: inout GraphicsContext) {
        let left = CGRect(x: 30, y: 52, width: 17, height: 12)
        let right = CGRect(x: 53, y: 52, width: 17, height: 12)
        for rect in [left, right] {
            let lens = Path(roundedRect: rect, cornerRadius: 4)
            context.fill(lens, with: .color(palette.outline))
            // A moving glint across the lens sells the smugness.
            let glintX = rect.minX + rect.width * ((phase * 0.35).truncatingRemainder(dividingBy: 1.0))
            context.fill(
                Path(CGRect(x: glintX, y: rect.minY + 2, width: 2, height: rect.height - 4)),
                with: .color(.white.opacity(0.35))
            )
        }
        var bridge = Path()
        bridge.move(to: CGPoint(x: left.maxX, y: left.midY))
        bridge.addLine(to: CGPoint(x: right.minX, y: right.midY))
        context.stroke(bridge, with: .color(palette.outline), lineWidth: 2.5)
    }

    private func drawSparkles(in context: inout GraphicsContext) {
        for index in 0..<3 {
            let seed = Double(index) * 2.1
            let twinkle = (sin(phase * 2 + seed) + 1) / 2
            let point = CGPoint(x: 20 + Double(index) * 30, y: 20 + sin(seed) * 6)
            let size = 3 + twinkle * 3
            context.fill(
                sparklePath(centre: point, size: size),
                with: .color(palette.glow.opacity(0.4 + twinkle * 0.6))
            )
        }
    }

    private func drawSweat(in context: inout GraphicsContext) {
        let count = mood == .panicking ? 3 : 2
        for index in 0..<count {
            let progress = (phase * 1.1 + Double(index) / Double(count)).truncatingRemainder(dividingBy: 1.0)
            let x = 84.0 - Double(index) * 6
            let y = 40.0 + progress * 30
            var drop = Path()
            drop.move(to: CGPoint(x: x, y: y - 5))
            drop.addQuadCurve(to: CGPoint(x: x, y: y + 3), control: CGPoint(x: x + 4, y: y + 1))
            drop.addQuadCurve(to: CGPoint(x: x, y: y - 5), control: CGPoint(x: x - 4, y: y + 1))
            context.fill(drop, with: .color(palette.accent.opacity(0.75 * (1 - progress))))
        }
    }

    private func drawArmsUp(in context: inout GraphicsContext) {
        let flail = sin(phase * 14) * 8
        for side in [-1.0, 1.0] {
            var arm = Path()
            let startX = 50 + side * 32
            arm.move(to: CGPoint(x: startX, y: 70))
            arm.addQuadCurve(
                to: CGPoint(x: startX + side * 10, y: 44 + flail * side),
                control: CGPoint(x: startX + side * 12, y: 58)
            )
            context.stroke(
                arm,
                with: .color(palette.outline),
                style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
            )
        }
    }

    private func drawFlames(in context: inout GraphicsContext) {
        for index in 0..<3 {
            let seed = Double(index) * 1.7
            let flicker = (sin(phase * 9 + seed) + 1) / 2
            let x = 34.0 + Double(index) * 16
            let height = 10 + flicker * 10
            var flame = Path()
            flame.move(to: CGPoint(x: x - 5, y: 106))
            flame.addQuadCurve(to: CGPoint(x: x, y: 106 - height), control: CGPoint(x: x - 6, y: 106 - height * 0.6))
            flame.addQuadCurve(to: CGPoint(x: x + 5, y: 106), control: CGPoint(x: x + 6, y: 106 - height * 0.6))
            flame.closeSubpath()
            context.fill(
                flame,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 1.0, green: 0.75, blue: 0.2).opacity(0.95),
                        Color(red: 1.0, green: 0.35, blue: 0.15).opacity(0.55)
                    ]),
                    startPoint: CGPoint(x: x, y: 106 - height),
                    endPoint: CGPoint(x: x, y: 106)
                )
            )
        }
    }

    private func drawNightcap(in context: inout GraphicsContext) {
        var cap = Path()
        cap.move(to: CGPoint(x: 22, y: 34))
        cap.addQuadCurve(to: CGPoint(x: 78, y: 30), control: CGPoint(x: 50, y: 12))
        cap.addQuadCurve(to: CGPoint(x: 22, y: 34), control: CGPoint(x: 50, y: 40))
        cap.closeSubpath()
        context.fill(cap, with: .color(palette.accent.opacity(0.85)))
        context.stroke(cap, with: .color(palette.outline), lineWidth: 2)

        let swayX = 84 + sin(phase * 1.4) * 4
        context.fill(
            Path(ellipseIn: CGRect(x: swayX - 4, y: 24, width: 8, height: 8)),
            with: .color(palette.shellHighlight)
        )
    }

    private func drawSnooze(in context: inout GraphicsContext) {
        for index in 0..<2 {
            let progress = (phase * 0.5 + Double(index) / 2).truncatingRemainder(dividingBy: 1.0)
            let point = CGPoint(x: 78 + progress * 10, y: 30 - progress * 22)
            let size = 8 + Double(index) * 3
            context.draw(
                Text("z")
                    .font(.system(size: size, weight: .black, design: .rounded))
                    .foregroundColor(palette.outline.opacity(0.8 * (1 - progress))),
                at: point
            )
        }
    }

    private func drawGhostTail(in context: inout GraphicsContext) {
        var tail = Path()
        tail.move(to: CGPoint(x: 18, y: 100))
        for index in 0...4 {
            let x = 18.0 + Double(index) * 16
            let y = 104.0 + sin(phase * 2 + Double(index)) * 4
            tail.addQuadCurve(to: CGPoint(x: x + 16, y: 104), control: CGPoint(x: x + 8, y: y + 8))
        }
        tail.addLine(to: CGPoint(x: 82, y: 96))
        tail.addLine(to: CGPoint(x: 18, y: 96))
        tail.closeSubpath()
        context.fill(tail, with: .color(palette.shell.opacity(0.7)))
    }

    // MARK: - Shapes

    private func boltPath(centre: CGPoint, size: CGFloat) -> Path {
        var path = Path()
        let halfWidth = size * 0.28
        let halfHeight = size * 0.5
        path.move(to: CGPoint(x: centre.x + halfWidth * 0.2, y: centre.y - halfHeight))
        path.addLine(to: CGPoint(x: centre.x - halfWidth, y: centre.y + halfHeight * 0.15))
        path.addLine(to: CGPoint(x: centre.x - halfWidth * 0.1, y: centre.y + halfHeight * 0.15))
        path.addLine(to: CGPoint(x: centre.x - halfWidth * 0.2, y: centre.y + halfHeight))
        path.addLine(to: CGPoint(x: centre.x + halfWidth, y: centre.y - halfHeight * 0.15))
        path.addLine(to: CGPoint(x: centre.x + halfWidth * 0.1, y: centre.y - halfHeight * 0.15))
        path.closeSubpath()
        return path
    }

    private func sparklePath(centre: CGPoint, size: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: centre.x, y: centre.y - size))
        path.addQuadCurve(to: CGPoint(x: centre.x + size, y: centre.y), control: centre)
        path.addQuadCurve(to: CGPoint(x: centre.x, y: centre.y + size), control: centre)
        path.addQuadCurve(to: CGPoint(x: centre.x - size, y: centre.y), control: centre)
        path.addQuadCurve(to: CGPoint(x: centre.x, y: centre.y - size), control: centre)
        path.closeSubpath()
        return path
    }
}
