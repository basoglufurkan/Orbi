import SwiftUI

/// Infinite procedural background stars, generated per screen-space cell from
/// a stable hash so nothing is stored and panning reveals consistent stars.
/// Three depth layers move at different rates for parallax.
struct StarFieldLayer: Sendable {
    var cellSize: CGFloat
    var density: Int
    var parallax: CGFloat
    var maxRadius: CGFloat
    var salt: UInt64

    static let far = StarFieldLayer(cellSize: 120, density: 4, parallax: 0.2, maxRadius: 0.9, salt: 11)
    static let mid = StarFieldLayer(cellSize: 170, density: 3, parallax: 0.5, maxRadius: 1.3, salt: 23)
    static let near = StarFieldLayer(cellSize: 260, density: 2, parallax: 1.0, maxRadius: 1.7, salt: 37)
    static let standard: [StarFieldLayer] = [.far, .mid, .near]
}

enum StarFieldPainter {
    /// Draws all layers. `offset` is the camera translation in points and
    /// `tilt` the gyro parallax shift at depth 1.0; both scale per layer.
    /// `time` drives twinkle (pass nil for static).
    static func draw(_ ctx: inout GraphicsContext, size: CGSize, offset: CGPoint = .zero, tilt: CGPoint = .zero,
                     layers: [StarFieldLayer] = StarFieldLayer.standard, opacity: Double = 1,
                     time: Double?, tint: Color = .white) {
        guard opacity > 0.01 else { return }
        // Dots are batched into one path per brightness level: a handful of
        // fills per frame instead of one for every star.
        let levels = 8
        var paths = [Path](repeating: Path(), count: levels)
        for layer in layers {
            let ox = (offset.x + tilt.x) * layer.parallax, oy = (offset.y + tilt.y) * layer.parallax
            let minCX = Int(floor((-ox) / layer.cellSize)) - 1
            let maxCX = Int(floor((size.width - ox) / layer.cellSize)) + 1
            let minCY = Int(floor((-oy) / layer.cellSize)) - 1
            let maxCY = Int(floor((size.height - oy) / layer.cellSize)) + 1
            guard (maxCX - minCX) * (maxCY - minCY) < 900 else { continue }
            for cx in minCX...maxCX {
                for cy in minCY...maxCY {
                    var rng = SeededRandom(seed: StableHash.mix(cx, cy, layer.salt))
                    for _ in 0..<layer.density {
                        let x = (CGFloat(cx) + rng.unit()) * layer.cellSize + ox
                        let y = (CGFloat(cy) + rng.unit()) * layer.cellSize + oy
                        let r = 0.3 + rng.unit() * layer.maxRadius
                        var a = 0.25 + rng.unit() * 0.6
                        let speed = 0.6 + rng.unit() * 1.4
                        let phase = rng.unit() * 6.28
                        if let time { a *= 0.65 + 0.35 * sin(time * speed + phase) }
                        guard x > -4, y > -4, x < size.width + 4, y < size.height + 4 else { continue }
                        let level = min(levels - 1, Int(a / 0.85 * Double(levels)))
                        paths[level].addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    }
                }
            }
        }
        for (level, path) in paths.enumerated() where !path.isEmpty {
            let a = (Double(level) + 0.5) / Double(levels) * 0.85
            ctx.fill(path, with: .color(tint.opacity(a * opacity)))
        }
    }
}

/// Self-animating star field for backgrounds. Twinkles slowly when motion is
/// allowed and the view is visible, and its layers follow the device tilt
/// while gyro parallax runs; otherwise renders once.
struct StarFieldView: View {
    var opacity: Double = 1
    var offset: CGPoint = .zero
    var tint: Color = .white
    @Environment(\.motionLevel) private var motion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.parallax) private var parallax

    var body: some View {
        let animate = motion.animatesContinuously && scenePhase == .active
        let tilting = parallax?.isRunning ?? false
        TimelineView(.animation(minimumInterval: tilting ? 1.0 / 30 : motion.frameInterval(15), paused: !animate)) { timeline in
            let tilt = parallax?.offset(depth: 1) ?? .zero
            Canvas(rendersAsynchronously: true) { ctx, size in
                let t = animate ? timeline.date.timeIntervalSinceReferenceDate : nil
                StarFieldPainter.draw(&ctx, size: size, offset: offset, tilt: tilt, opacity: opacity, time: t,
                                      tint: colorScheme == .dark ? tint : Color(hex: 0x5B4BE0))
            }
        }
        .parallaxConsumer()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
