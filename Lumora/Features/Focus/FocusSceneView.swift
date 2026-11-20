import SwiftUI

/// The living star during focus. Every visual quantity is a pure function of
/// normalized progress p ∈ [0, 1] (Active focus · state model):
/// core = 56 + 40p pt, glow = 30 + 60p, ambient sky = 0.35 + 0.65p,
/// orbit motes accumulate with p, the halo warms past p = 0.8, and the ring
/// blends violet → gold in the final stretch. Nothing orbits faster than 40 s.
///
/// The timer never depends on this view: it only *reads* the segment.
struct FocusSceneView: View {
    var segment: TimerSegment
    var category: FocusCategory

    @Environment(\.motionLevel) private var motion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let paused = segment.isPaused
        let animate = !paused && motion.animatesContinuously && scenePhase == .active
        // Calm scenes don't need 60 fps; 30 fps keeps GPU use low during focus.
        TimelineView(.animation(minimumInterval: motion.frameInterval(20), paused: !animate)) { timeline in
            Canvas { ctx, size in
                Self.draw(&ctx, size: size, segment: segment, category: category,
                          date: timeline.date, animate: animate, motion: motion, dark: colorScheme == .dark)
            }
        }
        .accessibilityHidden(true)
    }

    nonisolated static func ringRadius(for size: CGSize) -> CGFloat { min(130, size.width * 0.34) }
    nonisolated static func center(for size: CGSize) -> CGPoint { CGPoint(x: size.width / 2, y: size.height * 0.36) }

    nonisolated static func draw(_ ctx: inout GraphicsContext, size: CGSize, segment: TimerSegment, category: FocusCategory,
                     date: Date, animate: Bool, motion: MotionLevel, dark: Bool) {
        let p = segment.progress(at: date)
        let remaining = segment.remaining(at: date)
        let paused = segment.isPaused
        let dim = paused ? 0.55 : 1.0
        let t = date.timeIntervalSinceReferenceDate
        let c = center(for: size)
        let R = ringRadius(for: size)

        var scene = ctx
        scene.opacity = dim

        // Orbit guides.
        let track = (dark ? Color.white : Color(hex: Palette.midnightIndigo)).opacity(0.08)
        scene.stroke(Path(ellipseIn: CGRect(x: c.x - R * 0.62, y: c.y - R * 0.62, width: R * 1.24, height: R * 1.24)),
                     with: .color(track), lineWidth: 1)

        // Orbit motes: fade in over the first 90 s, accumulate with progress.
        if motion != .reduced {
            let elapsedWall = date.timeIntervalSince(segment.startedAt) - segment.pausedSeconds(at: date)
            let fadeIn = min(1, max(0, elapsedWall * segment.timeScale / 90))
            let count = motion == .full ? 4 + Int(10 * p) : 3 + Int(5 * p)
            for i in 0..<count {
                var rng = SeededRandom(seed: UInt64(i) &* 0x9E37 &+ 17)
                let radius = R * rng.range(0.55, 0.98)
                let period = rng.range(40, 80)
                let phase = rng.range(0, 2 * .pi)
                let angle = phase + (animate || paused ? t : 0) * 2 * .pi / period
                let pos = CGPoint(x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius)
                let alpha = fadeIn * rng.range(0.35, 0.8)
                let r = rng.range(1.2, 2.4)
                let tint = i % 3 == 0 ? category.color : Color.white
                scene.fill(Path(ellipseIn: CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)),
                           with: .color(tint.opacity(alpha * (dark ? 1 : 0.7))))
            }
        }

        // Progress ring with comet head.
        OrbitalProgressView.draw(&scene, center: c, radius: R, progress: p, lineWidth: 2.5, trackWidth: 1.5,
                                 headSize: 10, trackColor: track)

        // The core: breath slows to 6 s in the final minute.
        let breathPeriod = remaining <= 60 ? 6.0 : 4.0
        let breath = animate ? 1 + 0.03 * sin(t * 2 * .pi / breathPeriod) : 1
        let warmth = p >= 0.8 ? (p - 0.8) / 0.2 : 0
        GlowingCelestialBodyView.draw(&scene, center: c, progress: p, tint: category.color, warmth: warmth,
                                      breath: breath, dimmed: false)
    }
}
