import SwiftUI

/// Artifact card: locked (dashed, progress arc), earned, or holographic.
struct AchievementCardView: View {
    let definition: AchievementDefinition
    var unlockedAt: Date?
    var progress: Double

    @Environment(\.motionLevel) private var motion

    var isEarned: Bool { unlockedAt != nil }

    var body: some View {
        VStack(spacing: LMSpace.xs) {
            ArtifactMotifView(motif: definition.motif, earned: isEarned, progress: progress)
                .frame(height: 96)
            Text(definition.title)
                .font(LMFont.headline)
                .foregroundStyle(isEarned ? LMColor.textPrimary : LMColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(definition.detail)
                .font(LMFont.footnote.weight(.regular))
                .foregroundStyle(LMColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let unlockedAt {
                Text(footer(unlockedAt))
                    .font(LMFont.eyebrow).lmTracking(1.2)
                    .foregroundStyle(LMColor.reward)
            } else {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(LMFont.eyebrow)
                    .foregroundStyle(LMColor.textTertiary)
            }
        }
        .padding(LMSpace.m)
        .frame(maxWidth: .infinity, minHeight: 230)
        .background {
            if isEarned {
                RoundedRectangle(cornerRadius: LMRadius.card, style: .continuous)
                    .fill(Color.clear)
                    .glassCard(tint: definition.rarity == .holographic ? Color(hex: Palette.nebulaPink) : nil,
                               border: definition.rarity == .holographic ? Color(hex: Palette.nebulaPink).opacity(0.45) : nil)
            } else {
                RoundedRectangle(cornerRadius: LMRadius.card, style: .continuous)
                    .strokeBorder(LMColor.hairline, style: StrokeStyle(lineWidth: 1.2, dash: [5, 5]))
            }
        }
        .overlay {
            if isEarned, definition.rarity == .holographic, motion.animatesContinuously {
                HolographicSheen().clipShape(RoundedRectangle(cornerRadius: LMRadius.card, style: .continuous))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    private func footer(_ date: Date) -> String {
        let d = LMFormat.shortDate(date).localizedUppercase
        return definition.rarity == .holographic ? "\(d) · HOLO" : d
    }

    private var accessibilityText: String {
        if let unlockedAt {
            return String(localized: "\(definition.title), \(definition.rarity.label), earned \(LMFormat.shortDate(unlockedAt)). \(definition.detail)")
        }
        return String(localized: "\(definition.title), not yet earned, \(Int(progress * 100)) percent. \(definition.detail)")
    }
}

/// Slow iridescent sweep for holographic artifacts. A repeating animation
/// (no per-frame timeline), still with Reduce Motion.
private struct HolographicSheen: View {
    @Environment(\.motionLevel) private var motion
    @State private var swept = false

    var body: some View {
        let x: CGFloat = swept ? 1 : 0
        LinearGradient(colors: [.clear, Color(hex: Palette.starlightCyan).opacity(0.10),
                                Color(hex: Palette.nebulaPink).opacity(0.12), .clear],
                       startPoint: UnitPoint(x: x - 0.6, y: 0), endPoint: UnitPoint(x: x + 0.6, y: 1))
            .allowsHitTesting(false)
            .blendMode(.plusLighter)
            .onAppear {
                guard motion.animatesContinuously else { return }
                withAnimation(.easeInOut(duration: 3 * .pi).repeatForever(autoreverses: true)) { swept = true }
            }
    }
}

/// Procedural art for each artifact motif.
struct ArtifactMotifView: View {
    let motif: ArtifactMotif
    var earned: Bool
    var progress: Double = 1

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            guard earned else {
                // Locked: the artifact as a colourless ghost that firms up as
                // progress grows, inside a faint orbit with the progress arc.
                ctx.drawLayer { ghost in
                    ghost.addFilter(.saturation(0))
                    ghost.opacity = 0.14 + 0.22 * min(1, max(0, progress))
                    Self.drawMotif(&ghost, motif: motif, center: c)
                }
                let r = min(size.width, size.height) * 0.36
                OrbitalProgressView.draw(&ctx, center: c, radius: r, progress: progress, lineWidth: 2.5, trackWidth: 1,
                                         headSize: 0, trackColor: .white.opacity(0.12))
                return
            }
            Self.drawMotif(&ctx, motif: motif, center: c)
        }
        // Overdraw beyond the layout frame so soft glows fade out naturally
        // instead of being clipped into a visible square.
        .padding(-40)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func drawMotif(_ ctx: inout GraphicsContext, motif: ArtifactMotif, center c: CGPoint) {
        let gold = Color(hex: Palette.warmGold)
        switch motif {
        case .spark:
            CelestialPainter.star(&ctx, at: c, radius: 22, points: 4, color: gold, brightness: 1.1)
        case .constellation:
            let pts = [CGPoint(x: c.x - 34, y: c.y + 20), CGPoint(x: c.x - 12, y: c.y - 12), CGPoint(x: c.x + 10, y: c.y + 4), CGPoint(x: c.x + 34, y: c.y - 24)]
            var path = Path()
            path.addLines(pts)
            ctx.stroke(path, with: .color(.white.opacity(0.7)), lineWidth: 1.2)
            for (i, p) in pts.enumerated() {
                let r: CGFloat = i == 3 ? 6 : 4
                if i == 3 { CelestialPainter.glow(&ctx, at: p, radius: 16, color: Color(hex: Palette.cosmicViolet), intensity: 0.8) }
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(.white))
            }
        case .ring:
            OrbitalProgressView.draw(&ctx, center: c, radius: 32, progress: 1, lineWidth: 3, headSize: 0)
            CelestialPainter.star(&ctx, at: c, radius: 10, points: 4, color: gold)
        case .sun:
            CelestialPainter.glow(&ctx, at: c, radius: 52, color: gold, intensity: 0.6)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 26, y: c.y - 26, width: 52, height: 52)),
                     with: .radialGradient(Gradient(colors: [.white, gold]), center: CGPoint(x: c.x - 8, y: c.y - 8), startRadius: 0, endRadius: 34))
        case .planet:
            CelestialPainter.planet(&ctx, at: CGPoint(x: c.x, y: c.y + 8), radius: 30, palette: .named("violet"), showRing: false)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 14, y: c.y - 44, width: 18, height: 18)), with: .color(Color(hex: 0xFFF1D6)))
        case .orbit:
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 34, y: c.y - 34, width: 68, height: 68)), with: .color(.white.opacity(0.25)), lineWidth: 1)
            var arc = Path()
            arc.addArc(center: c, radius: 34, startAngle: .degrees(-90), endAngle: .degrees(40), clockwise: false)
            ctx.stroke(arc, with: .color(Color(hex: Palette.cosmicViolet)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            CelestialPainter.star(&ctx, at: c, radius: 9, points: 6, color: Color(hex: Palette.starlightCyan))
        case .nebula:
            let colors = [Palette.starlightCyan, Palette.nebulaPink, Palette.warmGold, Palette.cosmicViolet, Palette.starlightCyan, Palette.nebulaPink]
            for (i, hex) in colors.enumerated() {
                let a = Double(i) / Double(colors.count) * 2 * .pi
                let p = CGPoint(x: c.x + cos(a) * 34, y: c.y + sin(a) * 30)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(Color(hex: hex)))
            }
            CelestialPainter.glow(&ctx, at: c, radius: 26, color: .white, intensity: 0.6)
        case .comet:
            CelestialPainter.comet(&ctx, at: CGPoint(x: c.x + 24, y: c.y - 16), angle: -0.6, length: 70, color: gold)
        case .moon:
            CelestialPainter.moon(&ctx, at: c, radius: 28)
        case .tide:
            CelestialPainter.planet(&ctx, at: c, radius: 30, palette: .named("aqua"), showRing: false)
        }
    }
}
