import SwiftUI
import WattsonCore

/// The corner overlay: a character whose stride rate *is* the machine's power draw.
///
/// The whole surface is decorative and click-through — it is a readout, not a
/// control, and a window that eats clicks at the bottom of the screen would be
/// intolerable. It is dismissed from the menu, the dashboard, or by its auto-hide.
@MainActor
struct RunnerView: View {

    @ObservedObject var monitor: PowerMonitor
    @ObservedObject var preferencesStore: PreferencesStore

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45.0)) { timeline in
            // Everything the drawing needs is read once, here, as plain values: the
            // canvas closure then touches no observable state at all.
            let phase = timeline.date.timeIntervalSinceReferenceDate
            let preferences = preferencesStore.preferences
            let motion = monitor.motion
            let mood = monitor.mood
            let artist = RunnerArtist(
                character: preferences.runnerCharacter,
                palette: preferences.mascotSkin.palette,
                motion: motion,
                mood: mood,
                confettiEnabled: preferences.confettiEnabled,
                phase: phase
            )

            ZStack(alignment: .bottomLeading) {
                Canvas(opaque: false, rendersAsynchronously: false) { context, size in
                    artist.draw(in: &context, size: size)
                }

                hud(motion: motion)
                    .padding(.leading, 8)
                    .padding(.bottom, 4)
            }
        }
        .allowsHitTesting(false)
    }

    private func hud(motion: RunnerMotion) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(monitor.mood.tint)
                .frame(width: 7, height: 7)
            Text(motion.caption(watts: monitor.snapshot.systemDrawWatts))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(monitor.mood.tint.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }
}

/// Procedural cartoon runners. Same reasoning as the mascot: no sprite sheets, so
/// the characters are crisp at any size, recolour with the skin, and cost one draw
/// call each.
struct RunnerArtist {

    let character: RunnerCharacter
    let palette: MascotPalette
    let motion: RunnerMotion
    let mood: MascotMood
    let confettiEnabled: Bool
    let phase: Double

    private let groundInset: CGFloat = 26
    private let bodyHeight: CGFloat = 46

    func draw(in context: inout GraphicsContext, size: CGSize) {
        guard size.width > 40, size.height > 40 else { return }

        let groundY = size.height - groundInset
        let travelWidth = max(size.width - 90, 40)

        // Ping-pong across the strip: the character runs to the far side, turns, and
        // comes back, so it never leaves the overlay and never teleports.
        let lap = motion.isCelebrating ? 0 : (phase * motion.travelSpeed / travelWidth)
        let cycle = lap.truncatingRemainder(dividingBy: 2)
        let goingRight = cycle < 1
        let progress = goingRight ? cycle : 2 - cycle
        let x = 45 + travelWidth * progress

        drawGround(in: &context, size: size, groundY: groundY)
        if motion.effort > 0.45 { drawDust(in: &context, at: CGPoint(x: x, y: groundY), goingRight: goingRight) }
        if motion.isCharging { drawSparks(in: &context, at: CGPoint(x: x, y: groundY)) }
        if motion.isCelebrating, confettiEnabled { drawConfetti(in: &context, size: size) }

        context.drawLayer { layer in
            layer.translateBy(x: x, y: groundY)
            if !goingRight { layer.scaleBy(x: -1, y: 1) }
            drawCharacter(in: &layer)
        }
    }

    // MARK: - Scenery

    private func drawGround(in context: inout GraphicsContext, size: CGSize, groundY: CGFloat) {
        var line = Path()
        line.move(to: CGPoint(x: 12, y: groundY + 2))
        line.addLine(to: CGPoint(x: size.width - 12, y: groundY + 2))
        context.stroke(
            line,
            with: .linearGradient(
                Gradient(colors: [
                    mood.tint.opacity(0),
                    mood.tint.opacity(0.55),
                    mood.tint.opacity(0)
                ]),
                startPoint: CGPoint(x: 0, y: groundY),
                endPoint: CGPoint(x: size.width, y: groundY)
            ),
            style: StrokeStyle(lineWidth: 2, lineCap: .round)
        )
    }

    private func drawDust(in context: inout GraphicsContext, at point: CGPoint, goingRight: Bool) {
        let direction: CGFloat = goingRight ? -1 : 1
        for index in 0..<3 {
            let progress = (phase * 2.2 + Double(index) / 3).truncatingRemainder(dividingBy: 1.0)
            let radius = 2 + progress * 6 * motion.effort
            let centre = CGPoint(
                x: point.x + direction * (10 + progress * 40),
                y: point.y - progress * 10
            )
            context.fill(
                Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(palette.outline.opacity(0.18 * (1 - progress)))
            )
        }
    }

    private func drawSparks(in context: inout GraphicsContext, at point: CGPoint) {
        for index in 0..<4 {
            let seed = Double(index) * 1.9
            let progress = (phase * 1.4 + Double(index) / 4).truncatingRemainder(dividingBy: 1.0)
            let centre = CGPoint(
                x: point.x + sin(seed + phase) * 26,
                y: point.y - 20 - progress * 34
            )
            context.fill(
                boltPath(centre: centre, size: 10 * (1 - progress * 0.4)),
                with: .color(palette.glow.opacity(0.85 * (1 - progress)))
            )
        }
    }

    private func drawConfetti(in context: inout GraphicsContext, size: CGSize) {
        let colors: [Color] = [palette.fillHigh, palette.accent, palette.glow, palette.fillMedium]
        for index in 0..<18 {
            let seed = Double(index) * 3.13
            let progress = (phase * 0.5 + Double(index) / 18).truncatingRemainder(dividingBy: 1.0)
            let x = (sin(seed) * 0.5 + 0.5) * size.width
            let y = progress * size.height
            let rect = CGRect(x: x, y: y, width: 5, height: 3)
            context.drawLayer { layer in
                layer.translateBy(x: rect.midX, y: rect.midY)
                layer.rotate(by: .radians(seed + phase * 3))
                layer.fill(
                    Path(CGRect(x: -2.5, y: -1.5, width: 5, height: 3)),
                    with: .color(colors[index % colors.count].opacity(0.9 * (1 - progress)))
                )
            }
        }
    }

    // MARK: - Character

    /// Drawn with the origin at the character's feet, facing right.
    private func drawCharacter(in context: inout GraphicsContext) {
        let stridePhase = phase * motion.strideRate * 2 * .pi
        let bob = motion.isCelebrating
            ? abs(sin(phase * motion.strideRate * 3)) * 10
            : abs(sin(stridePhase)) * (2 + motion.effort * 4)
        let lean = motion.isTrudging ? -0.06 : motion.effort * 0.18

        context.drawLayer { layer in
            layer.translateBy(x: 0, y: -bob)
            layer.rotate(by: .radians(lean))

            drawLegs(in: &layer, stridePhase: stridePhase)

            switch character {
            case .wattson: drawWattsonBody(in: &layer)
            case .dino: drawDinoBody(in: &layer)
            case .astronaut: drawAstronautBody(in: &layer)
            case .corgi: drawCorgiBody(in: &layer, stridePhase: stridePhase)
            case .toaster: drawToasterBody(in: &layer)
            case .skater: drawSkaterBody(in: &layer)
            }

            drawArms(in: &layer, stridePhase: stridePhase)
            if motion.isCelebrating { drawVictoryFlag(in: &layer) }
        }
    }

    private func drawLegs(in context: inout GraphicsContext, stridePhase: Double) {
        // Four-legged characters get their legs from their own body routine.
        guard character != .corgi else { return }
        // The skater keeps both feet planted on the board.
        if character == .skater {
            drawSkateboard(in: &context)
            for offset in [-8.0, 8.0] {
                var leg = Path()
                leg.move(to: CGPoint(x: offset * 0.5, y: -18))
                leg.addLine(to: CGPoint(x: offset, y: -4))
                context.stroke(leg, with: .color(palette.outline), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            return
        }

        let swing = sin(stridePhase) * (10 + motion.effort * 10)
        let lift = max(cos(stridePhase), 0) * 6

        for (index, direction) in [1.0, -1.0].enumerated() {
            let thisSwing = index == 0 ? swing : -swing
            let thisLift = index == 0 ? lift : max(-cos(stridePhase), 0) * 6
            var leg = Path()
            leg.move(to: CGPoint(x: 0, y: -18))
            leg.addQuadCurve(
                to: CGPoint(x: thisSwing, y: -thisLift),
                control: CGPoint(x: thisSwing * 0.4 + direction, y: -10)
            )
            context.stroke(
                leg,
                with: .color(palette.outline),
                style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
            )
            // A shoe, so the leg reads as a leg rather than a wire.
            context.fill(
                Path(ellipseIn: CGRect(x: thisSwing - 4, y: -thisLift - 3, width: 9, height: 5)),
                with: .color(palette.accent)
            )
        }
    }

    private func drawArms(in context: inout GraphicsContext, stridePhase: Double) {
        guard character != .corgi else { return }
        let swing = sin(stridePhase + .pi) * (9 + motion.effort * 8)

        for (index, side) in [-1.0, 1.0].enumerated() {
            let thisSwing = index == 0 ? swing : -swing
            var arm = Path()
            let shoulder = CGPoint(x: side * 6, y: -bodyHeight + 12)
            arm.move(to: shoulder)
            if motion.isCelebrating {
                arm.addQuadCurve(
                    to: CGPoint(x: side * 18, y: -bodyHeight - 8),
                    control: CGPoint(x: side * 16, y: -bodyHeight)
                )
            } else {
                arm.addQuadCurve(
                    to: CGPoint(x: thisSwing, y: -bodyHeight + 24),
                    control: CGPoint(x: side * 12, y: -bodyHeight + 18)
                )
            }
            context.stroke(
                arm,
                with: .color(palette.outline),
                style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
            )
        }
    }

    private func drawWattsonBody(in context: inout GraphicsContext) {
        let rect = CGRect(x: -13, y: -bodyHeight, width: 26, height: bodyHeight - 16)
        let body = Path(roundedRect: rect, cornerRadius: 8)
        context.fill(body, with: .color(palette.shell))
        context.stroke(body, with: .color(palette.outline), lineWidth: 3)
        context.fill(
            Path(roundedRect: CGRect(x: -5, y: -bodyHeight - 5, width: 10, height: 6), cornerRadius: 2),
            with: .color(palette.outline)
        )
        // A charge bar that fills as the real battery does.
        let inner = rect.insetBy(dx: 5, dy: 5)
        let fillHeight = inner.height * 0.7
        context.fill(
            Path(roundedRect: CGRect(x: inner.minX, y: inner.maxY - fillHeight, width: inner.width, height: fillHeight), cornerRadius: 3),
            with: .color(mood.tint.opacity(0.85))
        )
        drawFace(in: &context, at: CGPoint(x: 0, y: rect.minY + 12))
    }

    private func drawDinoBody(in context: inout GraphicsContext) {
        let green = Color(red: 0.35, green: 0.72, blue: 0.42)
        let body = Path(ellipseIn: CGRect(x: -14, y: -bodyHeight, width: 28, height: bodyHeight - 14))
        context.fill(body, with: .color(green))
        context.stroke(body, with: .color(palette.outline), lineWidth: 2.5)

        // Tail with a swish that follows the stride.
        var tail = Path()
        tail.move(to: CGPoint(x: -12, y: -24))
        tail.addQuadCurve(
            to: CGPoint(x: -34, y: -14 + sin(phase * motion.strideRate * 6) * 4),
            control: CGPoint(x: -26, y: -30)
        )
        context.stroke(tail, with: .color(green), style: StrokeStyle(lineWidth: 7, lineCap: .round))

        for index in 0..<3 {
            var spike = Path()
            let y = -bodyHeight + 8 + Double(index) * 8
            spike.move(to: CGPoint(x: -12, y: y))
            spike.addLine(to: CGPoint(x: -20, y: y + 4))
            spike.addLine(to: CGPoint(x: -12, y: y + 8))
            spike.closeSubpath()
            context.fill(spike, with: .color(palette.fillMedium))
        }
        drawFace(in: &context, at: CGPoint(x: 3, y: -bodyHeight + 12))
    }

    private func drawAstronautBody(in context: inout GraphicsContext) {
        let suit = Path(roundedRect: CGRect(x: -12, y: -bodyHeight + 4, width: 24, height: bodyHeight - 22), cornerRadius: 9)
        context.fill(suit, with: .color(.white.opacity(0.95)))
        context.stroke(suit, with: .color(palette.outline), lineWidth: 2.5)

        let helmet = Path(ellipseIn: CGRect(x: -13, y: -bodyHeight - 12, width: 26, height: 24))
        context.fill(helmet, with: .color(palette.accent.opacity(0.35)))
        context.stroke(helmet, with: .color(palette.outline), lineWidth: 2.5)
        context.fill(
            Path(ellipseIn: CGRect(x: -6, y: -bodyHeight - 6, width: 8, height: 6)),
            with: .color(.white.opacity(0.7))
        )
        drawFace(in: &context, at: CGPoint(x: 0, y: -bodyHeight))
    }

    private func drawCorgiBody(in context: inout GraphicsContext, stridePhase: Double) {
        let fur = Color(red: 0.90, green: 0.66, blue: 0.35)
        // Four legs, front pair and back pair out of phase.
        for (index, offset) in [-10.0, -6.0, 8.0, 12.0].enumerated() {
            let swing = sin(stridePhase + Double(index) * .pi / 2) * 7
            var leg = Path()
            leg.move(to: CGPoint(x: offset, y: -16))
            leg.addLine(to: CGPoint(x: offset + swing, y: -2))
            context.stroke(leg, with: .color(fur), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }

        let body = Path(roundedRect: CGRect(x: -16, y: -30, width: 34, height: 16), cornerRadius: 8)
        context.fill(body, with: .color(fur))
        context.stroke(body, with: .color(palette.outline), lineWidth: 2)

        let head = Path(ellipseIn: CGRect(x: 12, y: -42, width: 18, height: 17))
        context.fill(head, with: .color(fur))
        context.stroke(head, with: .color(palette.outline), lineWidth: 2)

        for x in [14.0, 24.0] {
            var ear = Path()
            ear.move(to: CGPoint(x: x, y: -40))
            ear.addLine(to: CGPoint(x: x + 3, y: -50))
            ear.addLine(to: CGPoint(x: x + 7, y: -40))
            ear.closeSubpath()
            context.fill(ear, with: .color(fur))
            context.stroke(ear, with: .color(palette.outline), lineWidth: 1.5)
        }

        context.fill(Path(ellipseIn: CGRect(x: 26, y: -34, width: 4, height: 4)), with: .color(palette.outline))
        context.fill(Path(ellipseIn: CGRect(x: 18, y: -37, width: 3, height: 3)), with: .color(palette.eye))
    }

    private func drawToasterBody(in context: inout GraphicsContext) {
        let chrome = Path(roundedRect: CGRect(x: -15, y: -bodyHeight + 6, width: 30, height: bodyHeight - 24), cornerRadius: 6)
        context.fill(
            chrome,
            with: .linearGradient(
                Gradient(colors: [palette.shellHighlight, palette.shell.opacity(0.8)]),
                startPoint: CGPoint(x: -15, y: -bodyHeight),
                endPoint: CGPoint(x: 15, y: -18)
            )
        )
        context.stroke(chrome, with: .color(palette.outline), lineWidth: 2.5)

        // Toast, launched a little higher the harder the machine is working.
        let launch = 6 + motion.effort * 16 + abs(sin(phase * motion.strideRate)) * 5
        let toast = Path(roundedRect: CGRect(x: -7, y: -bodyHeight - launch, width: 14, height: 12), cornerRadius: 3)
        context.fill(toast, with: .color(Color(red: 0.88, green: 0.68, blue: 0.38)))
        context.stroke(toast, with: .color(palette.outline), lineWidth: 1.5)

        var slot = Path()
        slot.move(to: CGPoint(x: -9, y: -bodyHeight + 8))
        slot.addLine(to: CGPoint(x: 9, y: -bodyHeight + 8))
        context.stroke(slot, with: .color(palette.outline), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        drawFace(in: &context, at: CGPoint(x: 0, y: -bodyHeight + 20))
    }

    private func drawSkaterBody(in context: inout GraphicsContext) {
        let rect = CGRect(x: -11, y: -bodyHeight, width: 22, height: bodyHeight - 20)
        let body = Path(roundedRect: rect, cornerRadius: 9)
        context.fill(body, with: .color(palette.fillHigh.opacity(0.9)))
        context.stroke(body, with: .color(palette.outline), lineWidth: 2.5)

        // A cap, worn backwards, because of course it is.
        var cap = Path()
        cap.move(to: CGPoint(x: -12, y: -bodyHeight + 2))
        cap.addQuadCurve(to: CGPoint(x: 12, y: -bodyHeight + 2), control: CGPoint(x: 0, y: -bodyHeight - 10))
        cap.closeSubpath()
        context.fill(cap, with: .color(palette.accent))
        context.fill(
            Path(roundedRect: CGRect(x: -18, y: -bodyHeight + 1, width: 8, height: 4), cornerRadius: 2),
            with: .color(palette.accent)
        )
        drawFace(in: &context, at: CGPoint(x: 0, y: -bodyHeight + 14))
    }

    private func drawSkateboard(in context: inout GraphicsContext) {
        let deck = Path(roundedRect: CGRect(x: -20, y: -6, width: 40, height: 5), cornerRadius: 2.5)
        context.fill(deck, with: .color(palette.outline))
        for x in [-12.0, 12.0] {
            context.fill(
                Path(ellipseIn: CGRect(x: x - 3.5, y: -3, width: 7, height: 7)),
                with: .color(palette.fillMedium)
            )
        }
    }

    private func drawFace(in context: inout GraphicsContext, at centre: CGPoint) {
        let squint = motion.effort > 0.7 || motion.isTrudging
        for side in [-1.0, 1.0] {
            let eye = CGPoint(x: centre.x + side * 5, y: centre.y)
            if squint {
                var line = Path()
                line.move(to: CGPoint(x: eye.x - 3, y: eye.y))
                line.addLine(to: CGPoint(x: eye.x + 3, y: eye.y))
                context.stroke(line, with: .color(palette.eye), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            } else {
                context.fill(
                    Path(ellipseIn: CGRect(x: eye.x - 2, y: eye.y - 2.5, width: 4, height: 5)),
                    with: .color(palette.eye)
                )
            }
        }

        var mouth = Path()
        mouth.move(to: CGPoint(x: centre.x - 4, y: centre.y + 7))
        if motion.isTrudging {
            mouth.addQuadCurve(
                to: CGPoint(x: centre.x + 4, y: centre.y + 7),
                control: CGPoint(x: centre.x, y: centre.y + 3)
            )
        } else {
            mouth.addQuadCurve(
                to: CGPoint(x: centre.x + 4, y: centre.y + 7),
                control: CGPoint(x: centre.x, y: centre.y + 12)
            )
        }
        context.stroke(mouth, with: .color(palette.eye), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
    }

    private func drawVictoryFlag(in context: inout GraphicsContext) {
        var pole = Path()
        pole.move(to: CGPoint(x: 18, y: -bodyHeight - 6))
        pole.addLine(to: CGPoint(x: 18, y: -bodyHeight - 34))
        context.stroke(pole, with: .color(palette.outline), style: StrokeStyle(lineWidth: 2, lineCap: .round))

        var flag = Path()
        flag.move(to: CGPoint(x: 18, y: -bodyHeight - 34))
        flag.addQuadCurve(
            to: CGPoint(x: 18, y: -bodyHeight - 20),
            control: CGPoint(x: 38 + sin(phase * 6) * 4, y: -bodyHeight - 27)
        )
        context.fill(flag, with: .color(palette.fillHigh))
    }

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
}
