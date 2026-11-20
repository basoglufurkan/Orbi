import SwiftUI

/// The opening moment. Picks up exactly where the static launch screen
/// leaves off (Pell asleep, centred, on deep space; `LaunchPell` is that
/// frame, drawn by Tools/LaunchImage.swift) and wakes Pell up: eyes open,
/// stars come out, the gold orbit draws itself around Pell, Lumora's star
/// lands on it, Pell beams, and the whole sky fades into the app.
/// Tap to skip. With Reduce Motion it's a short cross-fade.
struct PellSplash: View {
    var onFinish: () -> Void

    /// Pell's radius on the launch image (points); keep in step with the tool.
    static let moonRadius: CGFloat = 56
    static let duration = 2.6

    @Environment(\.motionLevel) private var motion
    @State private var start = Date.now
    @State private var leaving = false

    var body: some View {
        let reduced = motion == .reduced
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduced)) { tl in
            let t = reduced ? 0 : tl.date.timeIntervalSince(start)
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: Palette.deepSpace)))
                Self.draw(&ctx, size: size, t: reduced ? 1.6 : t)
            }
            .overlay(alignment: .center) {
                Text(verbatim: "Orbi")
                    .font(LMFont.voice(.title))
                    .tracking(4)
                    .foregroundStyle(Color(hex: Palette.softWhite))
                    .opacity(reduced ? 1 : LMCurve.easeOutCubic.value((t - 1.25) / 0.6))
                    .offset(y: Self.moonRadius * 2.4 + (reduced ? 0 : 10 * (1 - LMCurve.easeOutCubic.value((t - 1.25) / 0.6))))
            }
        }
        .ignoresSafeArea()
        .opacity(leaving ? 0 : 1)
        .scaleEffect(leaving && !reduced ? 1.08 : 1)
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "Orbi"))
        .accessibilityAddTraits(.isImage)
        .task {
            start = .now
            try? await Task.sleep(for: .seconds(reduced ? 0.5 : Self.duration))
            finish()
        }
    }

    private func finish() {
        guard !leaving else { return }
        withAnimation(.easeInOut(duration: motion == .reduced ? 0.3 : 0.55)) { leaving = true }
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            onFinish()
        }
    }

    /// One frame of the opening at `t` seconds.
    static func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        func ease(_ curve: LMCurve, _ from: Double, _ length: Double) -> Double { curve.value((t - from) / length) }
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = moonRadius

        // Stars come out, each in its own moment, then twinkle.
        var seed: UInt64 = 11
        func rand() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
        for i in 0..<60 {
            let x = rand() * size.width, y = rand() * size.height, rr = 0.5 + rand() * 1.3, a = 0.3 + rand() * 0.55
            let born = ease(.easeOutCubic, 0.3 + rand() * 0.9, 0.5)
            let twinkle = 0.8 + 0.2 * sin(t * 3 + Double(i))
            guard born > 0 else { continue }
            ctx.fill(Path(ellipseIn: CGRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2)),
                     with: .color(.white.opacity(a * born * twinkle)))
        }
        CelestialPainter.glow(&ctx, at: c, radius: r * 4, color: Color(hex: Palette.cosmicViolet),
                              intensity: 0.28 * ease(.easeOutCubic, 0.3, 1))

        // The orbit: a tilted ellipse that draws itself, behind Pell, then over the front.
        let tilt = -0.22, ox = r * 2.3, oy = r * 0.52, drop = r * 0.36
        let place = CGAffineTransform(rotationAngle: tilt).concatenating(CGAffineTransform(translationX: c.x, y: c.y + drop))
        let drawn = ease(.easeInOutCubic, 0.55, 0.85)
        let orbit = Path(ellipseIn: CGRect(x: -ox, y: -oy, width: ox * 2, height: oy * 2)).applying(place)
            .trimmedPath(from: 0, to: drawn)
        let gold = Color(hex: Palette.warmGold)
        let ring = StrokeStyle(lineWidth: r * 0.075, lineCap: .round)
        if drawn > 0 { ctx.stroke(orbit, with: .color(gold), style: ring) }

        // Pell: asleep (as on the launch screen), wakes, then beams.
        let bob = sin(max(0, t - 0.4) * 2 * .pi / 3) * r * 0.05 * ease(.easeOutCubic, 0.4, 0.6)
        let pell = CGPoint(x: c.x, y: c.y + bob)
        let open = ease(.easeOutCubic, 0.35, 0.35)
        let beaming = t > 1.55 && t < 2.35
        PellPainter.draw(&ctx, center: pell, radius: r, expression: beaming ? .happy : .calm, blink: beaming ? 0 : 1 - open)

        if drawn > 0 {
            var front = ctx
            let lower = Path(CGRect(x: -size.width * 2, y: 0, width: size.width * 4, height: size.height * 2)).applying(place)
            front.clip(to: lower)
            front.clip(to: Path(ellipseIn: CGRect(x: pell.x - r - 4, y: pell.y - r - 4, width: r * 2 + 8, height: r * 2 + 8)))
            front.stroke(orbit, with: .color(gold), style: ring)
        }

        // Lumora's star lands on the ring with a little overshoot.
        let pop = ease(.release, 1.25, 0.5)
        if pop > 0 {
            let a = -0.5
            let star = CGPoint(x: cos(a) * ox, y: sin(a) * oy).applying(place)
            let k = pop * (1 + 0.25 * sin(min(1, (t - 1.25) / 0.5) * .pi))
            CelestialPainter.glow(&ctx, at: star, radius: r * 0.8 * k, color: gold, intensity: 0.7)
            sparkle(&ctx, at: star, size: r * 0.42 * k)
        }
    }

    private static func sparkle(_ ctx: inout GraphicsContext, at c: CGPoint, size r: CGFloat) {
        let w = r * 0.2
        var s = Path()
        s.move(to: CGPoint(x: c.x, y: c.y - r))
        s.addLine(to: CGPoint(x: c.x + w, y: c.y - w)); s.addLine(to: CGPoint(x: c.x + r, y: c.y))
        s.addLine(to: CGPoint(x: c.x + w, y: c.y + w)); s.addLine(to: CGPoint(x: c.x, y: c.y + r))
        s.addLine(to: CGPoint(x: c.x - w, y: c.y + w)); s.addLine(to: CGPoint(x: c.x - r, y: c.y))
        s.addLine(to: CGPoint(x: c.x - w, y: c.y - w)); s.closeSubpath()
        ctx.fill(s, with: .color(.white))
    }
}
