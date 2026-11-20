import SwiftUI

/// One galaxy as a system map: its worlds on luminous orbits around the
/// core, with the slots still waiting to form.
struct GalaxyDetailView: View {
    let index: Int
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.motionLevel) private var motion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let snap = app.odyssey.snapshot
        let galaxy = GalaxyCatalog.blueprint(index)
        let worlds = snap.worlds(inGalaxy: index)
        let charted = worlds.filter(\.isCharted).count
        ZStack(alignment: .topLeading) {
            CosmicBackgroundView(mood: .home, light: 0.4, starOpacity: 0.6)
            ScrollView {
                VStack(alignment: .leading, spacing: LMSpace.m) {
                    systemMap(galaxy: galaxy, worlds: worlds, charted: charted)
                        .aspectRatio(1, contentMode: .fit)
                        .padding(.horizontal, -LMSpace.m)
                        .padding(.top, 56)
                    VStack(alignment: .leading, spacing: LMSpace.xs) {
                        EyebrowText(String(localized: "Galaxy \(index + 1)"), color: LMColor.calm)
                        Text(galaxy.name).font(LMFont.voice(.largeTitle)).foregroundStyle(LMColor.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text(galaxy.lore).font(LMFont.body).foregroundStyle(LMColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(charted) of \(galaxy.capacity) worlds charted · it glows brighter with each one")
                            .font(LMFont.footnote).foregroundStyle(LMColor.textTertiary)
                    }
                    ForEach(worlds) { world in
                        NavigationLink(value: OdysseyRoute.world(world.ordinal)) { WorldRow(world: world) }
                            .buttonStyle(PressScaleStyle())
                    }
                    let empty = galaxy.capacity - worlds.count
                    if empty > 0 {
                        Text(empty == 1 ? String(localized: "1 world is still forming here.") : String(localized: "\(empty) worlds are still forming here."))
                            .font(LMFont.callout).foregroundStyle(LMColor.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, LMSpace.s)
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, LMSpace.l)
                .readableColumn()
            }
            .scrollIndicators(.hidden)
            .statusBarScrim()
            RoundControlButton(systemImage: "chevron.backward", label: "Back", size: 44) { dismiss() }
                .padding(.leading, LMSpace.m)
                .padding(.top, LMSpace.xs)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Orbit radius and angle for a world slot, deterministic per galaxy.
    static func slotPosition(slot: Int, capacity: Int, seed: UInt64, in size: CGSize) -> CGPoint {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let R = min(size.width, size.height) / 2
        let r = R * (0.24 + 0.66 * CGFloat(slot + 1) / CGFloat(capacity))
        var rng = SeededRandom(seed: seed ^ UInt64(slot &* 7919))
        let angle = Double(slot) * 2.399963 + rng.range(-0.3, 0.3)
        return CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r * 0.62)
    }

    private func systemMap(galaxy: GalaxyBlueprint, worlds: [WorldState], charted: Int) -> some View {
        GeometryReader { geo in
            let size = geo.size
            let live = motion.animatesContinuously && scenePhase == .active
            ZStack {
                TimelineView(.animation(minimumInterval: motion.frameInterval(20), paused: !live)) { tl in
                    Canvas { ctx, s in
                        let c = CGPoint(x: s.width / 2, y: s.height / 2)
                        GalaxyPainter.draw(&ctx, galaxy: galaxy, center: c, radius: min(s.width, s.height) * 0.5,
                                           brightness: 0.25 + 0.75 * Double(charted) / Double(max(1, galaxy.capacity)),
                                           time: live ? tl.date.timeIntervalSinceReferenceDate : nil, locked: false)
                        // Orbits.
                        for slot in 0..<galaxy.capacity {
                            let p = Self.slotPosition(slot: slot, capacity: galaxy.capacity, seed: galaxy.seed, in: s)
                            let rx = hypot(p.x - c.x, (p.y - c.y) / 0.62)
                            let filled = slot < worlds.count
                            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - rx * 0.62, width: rx * 2, height: rx * 1.24)),
                                       with: .color(.white.opacity(filled ? 0.12 : 0.05)),
                                       style: StrokeStyle(lineWidth: 1, dash: filled ? [] : [2, 6]))
                            if !filled {
                                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)),
                                           with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                            }
                        }
                    }
                }
                ForEach(worlds) { world in
                    let p = Self.slotPosition(slot: world.slot, capacity: galaxy.capacity, seed: galaxy.seed, in: size)
                    NavigationLink(value: OdysseyRoute.world(world.ordinal)) {
                        WorldView(world: world.blueprint, stage: world.stage, silhouette: !world.isCharted,
                                  animate: false, scale: 0.3)
                            .frame(width: 62, height: 62)
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressScaleStyle())
                    .position(p)
                    .accessibilityLabel(Text("\(world.blueprint.name), \(world.blueprint.archetype.displayName)"))
                }
            }
        }
    }
}

/// A row for a world in lists.
struct WorldRow: View {
    var world: WorldState

    var body: some View {
        HStack(spacing: LMSpace.m) {
            WorldThumb(world: world, size: 58)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(world.status == .uncharted ? String(localized: "Uncharted") : world.blueprint.name)
                        .font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
                    RarityChip(rarity: world.blueprint.rarity)
                }
                Text(subtitle).font(LMFont.footnote).foregroundStyle(LMColor.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(LMColor.textTertiary)
        }
        .padding(LMSpace.s)
        .glassCard(radius: LMRadius.row)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        switch world.status {
        case .uncharted: String(localized: "\(world.blueprint.archetype.displayName) · plot a course")
        case .enRoute: String(localized: "\(world.blueprint.archetype.displayName) · your ship is on the way")
        case .charted: String(localized: "\(world.blueprint.archetype.displayName) · \(world.stage.title)")
        }
    }
}
