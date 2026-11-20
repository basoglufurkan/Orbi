import SwiftUI

/// Pell's moods. Drawn from the "Pell" component set in Figma
/// ("Lumora — Pell character"), one variant per case; `resting` is the
/// breathing-out face (eyes closed, soft smile).
enum PellExpression: String, CaseIterable, Sendable {
    case calm, happy, focused, sleepy, proud, curious, resting

    /// Eyes that can blink (closed-eye faces don't).
    var hasOpenEyes: Bool { [.calm, .focused, .curious].contains(self) }

    var spokenName: String {
        switch self {
        case .calm: String(localized: "calm")
        case .happy: String(localized: "happy")
        case .focused: String(localized: "focused")
        case .sleepy: String(localized: "sleepy")
        case .proud: String(localized: "proud")
        case .curious: String(localized: "curious")
        case .resting: String(localized: "resting")
        }
    }
}

/// Draws Pell. Geometry is the Figma drawing's 200 × 200 box (moon radius 64)
/// scaled to `radius`; `blink` closes open eyes (0 open … 1 shut).
enum PellPainter {
    static let ink = Color(hex: 0x2A2F4E)

    nonisolated static func draw(_ ctx: inout GraphicsContext, center c: CGPoint, radius r: CGFloat,
                                 expression: PellExpression, blink: Double = 0) {
        let s = r / 64
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: c.x + (x - 100) * s, y: c.y + (y - 100) * s) }
        func oval(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) -> Path {
            Path(ellipseIn: CGRect(x: c.x + (x - 100 - rx) * s, y: c.y + (y - 100 - ry) * s, width: rx * 2 * s, height: ry * 2 * s))
        }
        func line(_ points: [(Double, Double)], quad control: (Double, Double)? = nil, width: Double = 3.2) {
            var path = Path()
            path.move(to: p(points[0].0, points[0].1))
            if let control {
                path.addQuadCurve(to: p(points[1].0, points[1].1), control: p(control.0, control.1))
            } else {
                for q in points.dropFirst() { path.addLine(to: p(q.0, q.1)) }
            }
            ctx.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: width * s, lineCap: .round, lineJoin: .round))
        }
        func eye(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, light: (Double, Double) = (1.8, -2.2)) {
            let open = max(0.08, 1 - blink)
            if open < 0.25 {
                line([(x - rx - 1, y), (x + rx + 1, y)], quad: (x, y + 3), width: 3)
                return
            }
            ctx.fill(oval(x, y, rx, ry * open), with: .color(ink))
            ctx.fill(oval(x + light.0, y + light.1 * open, 1.8, 1.8 * open), with: .color(.white))
        }

        // Halo, body, craters, cheeks.
        CelestialPainter.glow(&ctx, at: c, radius: r * 1.5, color: Color(hex: 0xCFE3FF), intensity: 0.38)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .radialGradient(
            Gradient(stops: [.init(color: .white, location: 0), .init(color: Color(hex: 0xDCE3EE), location: 0.55),
                             .init(color: Color(hex: 0x8D97AE), location: 1)]),
            center: p(78, 76), startRadius: 0, endRadius: r * 1.56))
        for (x, y, rr, a) in [(72.0, 68.0, 9.0, 0.35), (134, 124, 6, 0.35), (127, 64, 4, 0.3)] {
            ctx.fill(oval(x, y, rr, rr), with: .color(Color(hex: 0x8D97AE).opacity(a)))
        }
        for x in [70.0, 130] { ctx.fill(oval(x, 114, 10, 6), with: .color(Color(hex: 0xFF9BB8).opacity(0.45))) }

        switch expression {
        case .calm:
            eye(82, 98, 5, 6.5); eye(118, 98, 5, 6.5)
            line([(92, 116), (108, 116)], quad: (100, 122))
        case .happy:
            line([(75, 101), (89, 101)], quad: (82, 91), width: 3.6)
            line([(111, 101), (125, 101)], quad: (118, 91), width: 3.6)
            var mouth = Path()
            mouth.move(to: p(88, 113)); mouth.addQuadCurve(to: p(112, 113), control: p(100, 130)); mouth.closeSubpath()
            ctx.fill(mouth, with: .color(ink))
            var tongue = Path()
            tongue.move(to: p(94, 121)); tongue.addQuadCurve(to: p(106, 121), control: p(100, 126))
            tongue.addQuadCurve(to: p(94, 121), control: p(100, 118))
            ctx.fill(tongue, with: .color(Color(hex: 0xFF9BB8)))
        case .focused:
            eye(82, 99, 5, 7, light: (1.2, -3)); eye(118, 99, 5, 7, light: (1.2, -3))
            line([(75, 88), (89, 87)], width: 2.6); line([(111, 87), (125, 88)], width: 2.6)
            line([(94, 118), (106, 118)])
        case .sleepy:
            line([(75, 98), (89, 98)], quad: (82, 105), width: 3.4)
            line([(111, 98), (125, 98)], quad: (118, 105), width: 3.4)
            ctx.fill(oval(100, 119, 3.2, 3.8), with: .color(ink))
            // The "z"s float off the moon, so they're light, not ink.
            for (x, y, size, w) in [(142.0, 48.0, 10.0, 2.6), (156, 34, 7, 2.2)] {
                var z = Path()
                z.move(to: p(x, y)); z.addLine(to: p(x + size, y)); z.addLine(to: p(x, y + size)); z.addLine(to: p(x + size, y + size))
                ctx.stroke(z, with: .color(Color(hex: 0xCFE3FF).opacity(0.85)),
                           style: StrokeStyle(lineWidth: w * s, lineCap: .round, lineJoin: .round))
            }
        case .proud:
            line([(76, 99), (88, 99)], quad: (82, 93), width: 3.4)
            line([(112, 99), (124, 99)], quad: (118, 93), width: 3.4)
            line([(86, 113), (114, 113)], quad: (100, 127), width: 3.4)
            var sparkle = Path()
            let pts: [(Double, Double)] = [(152, 54), (155, 63), (164, 66), (155, 69), (152, 78), (149, 69), (140, 66), (149, 63)]
            sparkle.move(to: p(pts[0].0, pts[0].1))
            for q in pts.dropFirst() { sparkle.addLine(to: p(q.0, q.1)) }
            sparkle.closeSubpath()
            ctx.fill(sparkle, with: .color(Color(hex: Palette.warmGold)))
        case .curious:
            eye(81, 98, 6, 8, light: (2, -2.6)); eye(119, 99, 4.5, 5.5)
            line([(110, 85), (127, 85)], quad: (118, 80), width: 3)
            ctx.fill(oval(103, 119, 3.4, 4), with: .color(ink))
        case .resting:
            line([(75, 99), (89, 99)], quad: (82, 105), width: 3.4)
            line([(111, 99), (125, 99)], quad: (118, 105), width: 3.4)
            line([(93, 116), (107, 116)], quad: (100, 121))
        }
    }
}

/// Pell, alive: floats, blinks now and then, and changes face with a soft
/// cross-fade. Still (no blink, no bob) with Reduce Motion or in the background.
struct PellFace: View {
    var expression: PellExpression
    /// Extra scale, e.g. a breath.
    var swell: CGFloat = 1
    /// Moon radius as a share of the smaller side (the rest is halo).
    var fill: CGFloat = 0.32

    @Environment(\.motionLevel) private var motion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let live = motion.animatesContinuously && scenePhase == .active
        TimelineView(.animation(minimumInterval: motion.frameInterval(20), paused: !live)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let bob = live ? sin(t * 2 * .pi / 9) * size.height * 0.03 : 0
                let radius = min(size.width, size.height) * fill * swell
                PellPainter.draw(&ctx, center: CGPoint(x: size.width / 2, y: size.height / 2 + bob), radius: radius,
                                 expression: expression, blink: live && expression.hasOpenEyes ? Self.blink(at: t) : 0)
            }
        }
        .id(expression)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.35), value: expression)
        .accessibilityHidden(true)
    }

    /// A quick blink every few seconds, at irregular but repeatable times.
    static func blink(at t: Double) -> Double {
        let period = 4.7
        let k = floor(t / period)
        let offset = (sin(k * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
        let at = k * period + abs(offset) * 2.5
        let d = t - at
        guard d >= 0, d < 0.18 else { return 0 }
        return sin(d / 0.18 * .pi)
    }
}
