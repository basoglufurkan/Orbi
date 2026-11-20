import SwiftUI

/// Orbital progress ring (Components · Orbital progress ring): hairline
/// track, 3pt progress arc with round cap, and a "comet head" leading the
/// arc. Completion swaps to a gold halo; near the end the arc blends violet → gold.
struct OrbitalProgressView: View {
    var progress: Double
    var lineWidth: CGFloat = 3
    var trackWidth: CGFloat = 1.5
    var headSize: CGFloat = 10
    var showsHead = true

    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2 - headSize / 2 - 1
            Self.draw(&ctx, center: CGPoint(x: size.width / 2, y: size.height / 2), radius: r,
                      progress: progress, lineWidth: lineWidth, trackWidth: trackWidth,
                      headSize: showsHead ? headSize : 0)
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Progress"))
        .accessibilityValue(Text("\(Int((progress * 100).rounded())) percent"))
    }

    nonisolated static func arcColor(progress p: Double) -> Color {
        if p >= 1 { return Color(hex: Palette.warmGold) }
        let t = max(0, (p - 0.9) / 0.1)
        return t <= 0 ? Color(hex: Palette.cosmicViolet) : Color(hex: Palette.cosmicViolet).blended(with: Color(hex: Palette.warmGold), by: t)
    }

    nonisolated static func draw(_ ctx: inout GraphicsContext, center: CGPoint, radius r: CGFloat, progress: Double,
                     lineWidth: CGFloat = 3, trackWidth: CGFloat = 1.5, headSize: CGFloat = 10,
                     trackColor: Color = Color.primary.opacity(0.10), opacity: Double = 1) {
        let p = max(0, min(1, progress))
        var c = ctx
        c.opacity *= opacity
        c.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                 with: .color(trackColor), lineWidth: trackWidth)
        guard p > 0.001 else {
            if headSize > 0 { drawHead(&c, at: CGPoint(x: center.x, y: center.y - r), size: headSize, color: arcColor(progress: 0)) }
            return
        }
        let color = arcColor(progress: p)
        var arc = Path()
        arc.addArc(center: center, radius: r, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * p), clockwise: false)
        if p >= 1 {
            CelestialPainter.glow(&c, at: center, radius: r + 18, color: color, intensity: 0.0)
            c.stroke(arc, with: .color(color.opacity(0.35)), style: StrokeStyle(lineWidth: lineWidth * 3, lineCap: .round))
        }
        c.stroke(arc, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        if headSize > 0, p < 1 {
            let angle = (-90 + 360 * p) * .pi / 180
            drawHead(&c, at: CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r), size: headSize, color: color)
        }
    }

    nonisolated private static func drawHead(_ ctx: inout GraphicsContext, at p: CGPoint, size: CGFloat, color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - size * 1.1, y: p.y - size * 1.1, width: size * 2.2, height: size * 2.2)),
                 with: .color(color.opacity(0.28)))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)), with: .color(.white))
    }
}

extension Color {
    /// Linear sRGB blend (iOS 17-compatible; `Color.mix` needs iOS 18).
    func blended(with other: Color, by t: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let k = CGFloat(max(0, min(1, t)))
        return Color(.sRGB, red: r1 + (r2 - r1) * k, green: g1 + (g2 - g1) * k,
                     blue: b1 + (b2 - b1) * k, opacity: a1 + (a2 - a1) * k)
    }
}
