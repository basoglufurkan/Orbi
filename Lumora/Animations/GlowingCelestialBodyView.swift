import SwiftUI

/// The luminous sphere at the heart of setup, focus and onboarding.
/// Size and glow are pure functions of `progress` (Active focus · state
/// model): core = 56 + 40p pt, glow = 30 + 60p.
struct GlowingCelestialBodyView: View {
    var progress: Double = 0
    var tint: Color = Color(hex: Palette.starlightCyan)
    var warmth: Double = 0
    var breathing = true
    var dimmed = false

    @Environment(\.motionLevel) private var motion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let animate = breathing && motion.animatesContinuously && scenePhase == .active && !dimmed
        TimelineView(.animation(minimumInterval: motion.frameInterval(30), paused: !animate)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let breath = animate ? 1 + 0.03 * sin(t * 2 * .pi / 4) : 1
                Self.draw(&ctx, center: CGPoint(x: size.width / 2, y: size.height / 2),
                          progress: progress, tint: tint, warmth: warmth, breath: breath, dimmed: dimmed)
            }
        }
        .accessibilityHidden(true)
    }

    nonisolated static func coreRadius(progress p: Double) -> CGFloat { (56 + 40 * p) / 2 }

    nonisolated static func draw(_ ctx: inout GraphicsContext, center: CGPoint, progress p: Double, tint: Color,
                     warmth: Double, breath: Double, dimmed: Bool, scale: CGFloat = 1, brightness: Double = 1) {
        let core = coreRadius(progress: p) * breath * scale
        let glowRadius = (30 + 60 * p) * scale
        let alpha = (dimmed ? 0.55 : 1.0) * (0.75 + 0.25 * min(1, p * 2)) * brightness
        CelestialPainter.glow(&ctx, at: center, radius: core + glowRadius * 1.6, color: tint, intensity: 0.32 * alpha)
        if warmth > 0 {
            CelestialPainter.glow(&ctx, at: center, radius: core + glowRadius * 1.2,
                                  color: Color(hex: Palette.warmGold), intensity: 0.28 * warmth * alpha)
        }
        let sphere = Path(ellipseIn: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2))
        var c = ctx
        c.opacity = alpha
        c.fill(sphere, with: .radialGradient(
            Gradient(stops: [
                .init(color: .white, location: 0),
                .init(color: Color(hex: 0xE8E6FF), location: 0.35),
                .init(color: tint.opacity(0.95), location: 0.75),
                .init(color: Color(hex: Palette.cosmicViolet), location: 1),
            ]), center: CGPoint(x: center.x - core * 0.25, y: center.y - core * 0.3), startRadius: 0, endRadius: core * 1.35))
    }
}
