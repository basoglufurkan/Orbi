#if DEBUG
import SwiftUI

/// Debug-only art board (launch with `-lumora-gallery`): every world class
/// at every stage, every galaxy shape, every ship. Used to review the
/// procedural art in the simulator. Pass `-lumora-gallery-section worlds`,
/// `stages`, `galaxies`, `ships`, `events` or `pell` to show one section.
struct OdysseyGalleryView: View {
    var section: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if section == nil || section == "worlds" { worlds }
                if section == nil || section == "stages" { stages }
                if section == nil || section == "galaxies" { galaxies }
                if section == nil || section == "ships" { ships }
                if section == nil || section == "events" { events }
                if section == nil || section == "pell" { pell }
            }
            .padding(12)
        }
        .background(Color(hex: Palette.deepSpace).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
    }

    /// One world of each class (first ordinal of that class), stage 0 and stage 5.
    private var worlds: some View {
        let samples = WorldArchetype.allCases.map { a in
            (1...200).lazy.map(WorldGenerator.blueprint(ordinal:)).first { $0.archetype == a }!
        }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
            ForEach(samples, id: \.ordinal) { w in
                VStack(spacing: 2) {
                    HStack(spacing: 0) {
                        WorldView(world: w, stage: .discovered).frame(height: 110)
                        WorldView(world: w, stage: .wonder).frame(height: 110)
                    }
                    label("\(w.archetype.rawValue) · \(w.name)")
                }
            }
        }
    }

    /// Every stage for a few classes.
    private var stages: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach([1, 2, 3, 4], id: \.self) { ordinal in
                let w = WorldGenerator.blueprint(ordinal: ordinal)
                label(w.archetype.rawValue)
                HStack(spacing: 0) {
                    ForEach(WorldStage.allCases, id: \.self) { s in
                        VStack(spacing: 0) {
                            WorldView(world: w, stage: s).frame(height: 76)
                            label(s.title)
                        }
                    }
                }
            }
            label("silhouette")
            WorldView(world: WorldGenerator.blueprint(ordinal: 5), silhouette: true).frame(height: 90)
        }
    }

    private var galaxies: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
            ForEach(0..<8, id: \.self) { i in
                let g = GalaxyCatalog.blueprint(i)
                VStack(spacing: 2) {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                        Canvas { ctx, size in
                            GalaxyPainter.draw(&ctx, galaxy: g, center: CGPoint(x: size.width / 2, y: size.height / 2),
                                               radius: min(size.width, size.height) * 0.42, brightness: i == 0 ? 1 : 0.4,
                                               time: tl.date.timeIntervalSinceReferenceDate, locked: i >= 6)
                        }
                    }
                    .frame(height: 170)
                    label("\(g.name) · \(g.shape.rawValue)\(i >= 6 ? " · locked" : "")")
                }
            }
        }
    }

    private var events: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
            ForEach(CosmicEventKind.allCases, id: \.self) { kind in
                VStack(spacing: 2) {
                    CosmicEventArt(kind: kind)
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    label(kind.rawValue)
                }
            }
        }
    }

    private var pell: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
            ForEach(PellExpression.allCases, id: \.self) { e in
                VStack(spacing: 2) {
                    PellFace(expression: e).frame(height: 120)
                    label(e.rawValue)
                }
            }
        }
    }

    private var ships: some View {
        let combos = ShipHull.allCases.flatMap { hull in
            zip(ShipPaint.allCases.prefix(4), ShipTrail.allCases).map { ShipLoadout(hull: hull, paint: $0, trail: $1) }
        }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
            ForEach(combos.indices, id: \.self) { i in
                let loadout = combos[i]
                VStack(spacing: 0) {
                    RocketView(loadout: loadout, heading: 0, thrust: 0.8)
                        .frame(height: 120)
                    label("\(loadout.hull.rawValue)/\(loadout.paint.rawValue)")
                }
            }
            RocketView(loadout: ShipLoadout(hull: .swift, paint: .abyss, trail: .comet), heading: .pi / 3, thrust: 1)
                .frame(height: 120)
        }
    }
}
#endif
