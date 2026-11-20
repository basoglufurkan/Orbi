import SwiftUI
import WidgetKit

/// A stylized snapshot of the user's universe.
struct UniverseSnapshotWidget: Widget {
    let kind = "LumoraUniverseSnapshot"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            UniverseSnapshotView(entry: entry)
                .containerBackground(for: .widget) { UniverseBackdrop() }
                .widgetURL(DeepLink.screen(.universe).appURL)
        }
        .configurationDisplayName("Your universe")
        .description("A window onto the sky you've built.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct UniverseSnapshotView: View {
    var entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let s = entry.snapshot
        // The sky gets its own band above the caption so labels never sit on stars.
        VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 8) {
            if s.stars.isEmpty {
                Text("Your first star is waiting.")
                    .font(.caption).foregroundStyle(WidgetStyle.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MiniSky(stars: s.stars, glyphScale: family == .systemSmall ? 0.8 : 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(summary(s))
                    .font(.caption.weight(.semibold)).foregroundStyle(WidgetStyle.text)
                    .lineLimit(1).minimumScaleFactor(0.75)
                if let world = s.expeditionWorld, let f = s.expeditionFraction, family != .systemSmall {
                    HStack(spacing: 6) {
                        Text(String(localized: "Ship → \(world) · \(Int((f * 100).rounded()))%"))
                            .font(.caption2.weight(.semibold)).foregroundStyle(WidgetStyle.cyan).lineLimit(1)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.12))
                                Capsule().fill(WidgetStyle.cyan).frame(width: max(4, geo.size.width * f))
                            }
                        }
                        .frame(height: 4)
                    }
                } else if let next = s.nextWorldName, let n = s.sessionsToNextWorld, family != .systemSmall {
                    Text(n == 1 ? String(localized: "\(next) · 1 session away") : String(localized: "\(next) · \(n) sessions away"))
                        .font(.caption2).foregroundStyle(WidgetStyle.secondary).lineLimit(1)
                }
            }
        }
    }

    private func summary(_ s: WidgetSnapshot) -> String {
        var parts = [s.totalStars == 1 ? String(localized: "1 star") : String(localized: "\(s.totalStars) stars"),
                     s.planets == 1 ? String(localized: "1 planet") : String(localized: "\(s.planets) planets")]
        if family == .systemLarge, s.constellations > 0 {
            parts.append(s.constellations == 1 ? String(localized: "1 constellation") : String(localized: "\(s.constellations) constellations"))
        }
        return parts.joined(separator: " · ")
    }
}

/// Full-bleed Deep Space backdrop with a violet glow and ambient specks.
/// Lives in the container background so it reaches the widget's edges.
struct UniverseBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                WidgetStyle.space
                RadialGradient(colors: [WidgetStyle.violet.opacity(0.32), .clear], center: UnitPoint(x: 0.5, y: 0.42),
                               startRadius: 0, endRadius: max(geo.size.width, geo.size.height) * 0.6)
                ForEach(0..<28, id: \.self) { i in
                    let x = Double((i * 7919) % 100) / 100, y = Double((i * 104_729) % 97) / 97
                    Circle().fill(Color.white.opacity(0.2 + Double(i % 4) * 0.08))
                        .frame(width: 1.4, height: 1.4)
                        .position(x: geo.size.width * x, y: geo.size.height * y)
                }
            }
        }
    }
}

/// The user's stars and planets, spread to fill the available rect.
/// Each category keeps its own star shape, so color is never the only signal.
struct MiniSky: View {
    var stars: [WidgetSnapshot.MiniStar]
    var glyphScale: CGFloat = 1
    /// Soft halos read well large; small slivers stay crisp without them.
    var glow = true

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(stars.enumerated()), id: \.offset) { _, star in
                    MiniSkyObject(star: star, sky: geo.size, glyphScale: glyphScale, glow: glow)
                        .position(Self.point(for: star, in: geo.size))
                }
            }
        }
    }

    /// Snapshot positions span roughly 0.09...0.91; stretch that range to the rect.
    static func point(for star: WidgetSnapshot.MiniStar, in size: CGSize) -> CGPoint {
        let nx = (star.x - 0.09) / 0.82, ny = (star.y - 0.09) / 0.82
        return CGPoint(x: size.width * (0.06 + 0.88 * nx), y: size.height * (0.08 + 0.84 * ny))
    }
}

private struct MiniSkyObject: View {
    var star: WidgetSnapshot.MiniStar
    var sky: CGSize
    var glyphScale: CGFloat
    var glow: Bool

    var body: some View {
        if star.isPlanet {
            let d = max(16, min(sky.width, sky.height) * 0.16)
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xFFE3A3), Color(hex: 0xF29BB8), Color(hex: 0x3A2C6E)],
                                     center: UnitPoint(x: 0.3, y: 0.3), startRadius: 0, endRadius: d * 0.75))
                .frame(width: d, height: d)
        } else {
            let category = FocusCategory(rawValue: star.categoryRaw)
            let size = CGFloat(4 + 3 * star.size) * glyphScale
            let color = category?.color ?? WidgetStyle.gold
            ZStack {
                if glow {
                    Circle().fill(color.opacity(0.4))
                        .frame(width: size * 2.6, height: size * 2.6).blur(radius: 3)
                }
                StarShape(points: category?.starPoints ?? 4)
                    .fill(glow ? Color.white : color)
                    .frame(width: size, height: size)
            }
        }
    }
}
