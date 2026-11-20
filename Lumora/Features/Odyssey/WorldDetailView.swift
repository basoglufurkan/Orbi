import SwiftUI

/// A world up close: what it is, the journey there, what you found, and how
/// it can grow — always with a preview of how the next stage will look.
struct WorldDetailView: View {
    let ordinal: Int
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var showPlot = false
    @State private var launching = false
    @State private var errorText: String?
    @State private var bloomStage: WorldStage?
    @State private var heroScale: CGFloat = 1
    @State private var visiting: WorldState?

    var body: some View {
        let snap = app.odyssey.snapshot
        if let world = snap.worlds.first(where: { $0.ordinal == ordinal }) {
            content(world: world, snap: snap)
                .telemetryScreen("world_detail")
        } else {
            VStack(spacing: LMSpace.s) {
                PellView(mood: .sleepy, showsLabel: false)
                Text("This world hasn't formed yet")
                    .font(LMFont.title).foregroundStyle(LMColor.textPrimary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CosmicBackgroundView(mood: .reward, light: 0.3, starOpacity: 0.6))
        }
    }

    private func content(world: WorldState, snap: OdysseySnapshot) -> some View {
        let bp = world.blueprint
        let uncharted = world.status == .uncharted
        return ZStack(alignment: .topLeading) {
            CosmicBackgroundView(mood: .reward, light: 0.5, starOpacity: 0.8)
            ScrollView {
                VStack(alignment: .leading, spacing: LMSpace.m) {
                    WorldView(world: bp, stage: world.stage, silhouette: !world.isCharted, scale: 0.34)
                        .frame(height: 280)
                        .scaleEffect(heroScale)
                        .padding(.top, 32)
                        .contentShape(Rectangle())
                        .onTapGesture { if world.isCharted { visit(world) } }
                        .accessibilityHidden(true)
                    titleBlock(world)
                    if !uncharted { statsRow(bp) }
                    if world.isCharted {
                        CosmicButton(title: "Visit the surface", systemImage: "sun.horizon", kind: .secondary, height: 52) { visit(world) }
                            .accessibilityIdentifier("world.visit")
                    }
                    switch world.status {
                    case .uncharted: plotSection(world: world, snap: snap)
                    case .enRoute: enRouteSection(snap: snap)
                    case .charted:
                        loreCard(bp)
                        findCard(bp)
                        terraformSection(world: world, snap: snap)
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
            if let stage = bloomStage {
                StageReachedBanner(stage: stage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showPlot) {
            PlotCourseSheet(world: world, snapshot: snap) {
                showPlot = false
                do {
                    try app.odyssey.plotCourse(to: world.ordinal)
                    app.haptics.sessionStart()
                    launching = true
                } catch {
                    errorText = error.localizedDescription
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $visiting) { w in
            SurfaceVisitView(world: w) { visiting = nil }
        }
        .fullScreenCover(isPresented: $launching) {
            LaunchCinematicView(world: world, loadout: snap.loadout) { launching = false }
        }
        .alert(String(localized: "Not yet"), isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    private func visit(_ world: WorldState) {
        app.haptics.selection()
        visiting = world
    }

    // MARK: Sections

    private func titleBlock(_ world: WorldState) -> some View {
        let bp = world.blueprint
        return VStack(alignment: .leading, spacing: LMSpace.xs) {
            HStack(spacing: 8) {
                EyebrowText(String(localized: "World \(bp.ordinal) · \(bp.archetype.displayName)"), color: LMColor.calm)
                RarityChip(rarity: bp.rarity)
            }
            Text(world.status == .uncharted ? String(localized: "Uncharted world") : bp.name)
                .font(LMFont.voice(.largeTitle)).foregroundStyle(LMColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(world.status == .uncharted
                 ? String(localized: "Something is out there. Its light reached you first.")
                 : WorldLexicon.tagline(bp.archetype))
                .font(LMFont.body).foregroundStyle(LMColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statsRow(_ bp: WorldBlueprint) -> some View {
        HStack(spacing: LMSpace.s) {
            StatisticsCardView(title: String(localized: "Gravity"), value: "\(bp.gravity.formatted(.number.precision(.fractionLength(1)))) g", fillsHeight: true)
            StatisticsCardView(title: String(localized: "Day"), value: "\(Int(bp.dayLengthHours)) h", fillsHeight: true)
            StatisticsCardView(title: String(localized: "Surface"), value: "\(bp.temperature)°", fillsHeight: true)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func plotSection(world: WorldState, snap: OdysseySnapshot) -> some View {
        let rules = app.odyssey.rules
        let minutes = rules.travelMinutes(for: world.blueprint)
        let cost = rules.expeditionCost(for: world.blueprint)
        return VStack(alignment: .leading, spacing: LMSpace.s) {
            Text(snap.expedition == nil
                 ? String(localized: "Your focus will power the journey. Each minute brings your ship closer.")
                 : String(localized: "Your ship is already travelling. This world will wait for its turn."))
                .font(LMFont.callout).foregroundStyle(LMColor.textSecondary)
            HStack(spacing: LMSpace.s) {
                StatisticsCardView(title: String(localized: "Journey"), value: String(localized: "\(minutes) min"),
                                   detail: String(localized: "of focus"), fillsHeight: true)
                StatisticsCardView(title: String(localized: "Fuel"), value: cost == 0 ? String(localized: "Free") : "\(cost) ✦",
                                   detail: cost == 0 ? String(localized: "first journey") : String(localized: "stardust"),
                                   highlight: LMColor.reward, fillsHeight: true)
            }
            .fixedSize(horizontal: false, vertical: true)
            CosmicButton(title: "Plot a course", systemImage: "location.north.line", kind: .reward) { showPlot = true }
                .disabled(snap.expedition != nil)
                .accessibilityIdentifier("world.plot")
        }
    }

    private func enRouteSection(snap: OdysseySnapshot) -> some View {
        VStack(alignment: .leading, spacing: LMSpace.s) {
            if let e = snap.expedition {
                JourneyBar(fraction: e.fraction, showsShip: true, loadout: snap.loadout)
                Text(String(localized: "\(e.remainingMinutes) minutes of focus to arrival"))
                    .font(LMFont.callout).foregroundStyle(LMColor.textSecondary)
                CosmicButton(title: "Focus now", systemImage: "sparkle") { app.beginFocus(taskID: nil) }
            }
        }
        .padding(LMSpace.l)
        .glassCard()
    }

    private func loreCard(_ bp: WorldBlueprint) -> some View {
        VStack(alignment: .leading, spacing: LMSpace.xs) {
            EyebrowText(String(localized: "Field notes"))
            Text(WorldLexicon.lore(bp.archetype, variant: bp.loreVariant))
                .font(LMFont.voice(.title3)).foregroundStyle(LMColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(LMSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func findCard(_ bp: WorldBlueprint) -> some View {
        let find = WorldLexicon.find(bp.findIndex)
        return HStack(alignment: .top, spacing: LMSpace.m) {
            Image(systemName: findSymbol(find.kind)).font(.title2).foregroundStyle(LMColor.reward)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                EyebrowText(String(localized: "Discovered · \(find.kindLabel)"), color: LMColor.reward)
                Text(find.title).font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
                Text(find.detail).font(LMFont.callout).foregroundStyle(LMColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(LMSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(border: LMColor.rewardFill.opacity(0.3))
    }

    private func terraformSection(world: WorldState, snap: OdysseySnapshot) -> some View {
        VStack(alignment: .leading, spacing: LMSpace.s) {
            OdysseySectionHeader(title: String(localized: "Terraform"), trailing: world.stage.title)
            StageTrack(stage: world.stage)
            if let next = world.stage.next {
                let cost = app.odyssey.rules.cultivationCost(to: next, rarity: world.blueprint.rarity)
                VStack(spacing: LMSpace.s) {
                    HStack(spacing: 0) {
                        stagePreview(world: world, stage: world.stage, label: String(localized: "Now"))
                        Image(systemName: "arrow.right").foregroundStyle(LMColor.reward).font(.title3.weight(.semibold))
                        stagePreview(world: world, stage: next, label: next.title)
                    }
                    Text(next.promise).font(LMFont.callout).foregroundStyle(LMColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { cultivate(world) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "leaf")
                            Text("Grow to \(next.title)")
                            Text("·")
                            Text("\(cost)")
                            // Inherits the button's ink; a gold glyph vanishes on the gold button.
                            StarShape(points: 4, innerRatio: 0.3).frame(width: 13, height: 13)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(CosmicButtonStyle(kind: .reward, height: 56))
                    .accessibilityIdentifier("world.cultivate")
                    if snap.balance < cost {
                        Text("\(cost - snap.balance) more stardust · about \(cost - snap.balance) minutes of focus")
                            .font(LMFont.footnote).foregroundStyle(LMColor.textTertiary)
                    }
                }
                .padding(LMSpace.m)
                .glassCard()
            } else {
                Text("\(world.blueprint.name) is a wonder now. It shines across every galaxy you have ignited.")
                    .font(LMFont.callout).foregroundStyle(LMColor.reward)
                    .padding(LMSpace.m)
                    .glassCard(border: LMColor.rewardFill.opacity(0.4))
            }
        }
    }

    private func stagePreview(world: WorldState, stage: WorldStage, label: String) -> some View {
        VStack(spacing: 4) {
            // Still: the hero above already turns, and three live worlds cost a lot.
            WorldView(world: world.blueprint, stage: stage, animate: false, scale: 0.3).frame(height: 130)
            Text(label).font(LMFont.footnote.weight(.semibold)).foregroundStyle(LMColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func cultivate(_ world: WorldState) {
        do {
            let stage = try app.odyssey.cultivate(world.ordinal)
            app.haptics.success()
            app.audio.play(.start)
            withAnimation(LMSpring.bloom) {
                bloomStage = stage
                heroScale = 1.08
            }
            Task {
                try? await Task.sleep(for: .seconds(0.5))
                withAnimation(LMSpring.settle) { heroScale = 1 }
                try? await Task.sleep(for: .seconds(2.2))
                withAnimation(LMSpring.settle) { bloomStage = nil }
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func findSymbol(_ kind: WorldFind.Kind) -> String {
        switch kind {
        case .lifeform: "leaf.circle"
        case .relic: "seal"
        case .phenomenon: "sparkles"
        }
    }
}

/// Six dots: how far the world has grown.
struct StageTrack: View {
    var stage: WorldStage

    var body: some View {
        HStack(spacing: 6) {
            ForEach(WorldStage.allCases, id: \.self) { s in
                Capsule()
                    .fill(s <= stage ? AnyShapeStyle(LinearGradient(colors: [Color(hex: Palette.starlightCyan), Color(hex: Palette.warmGold)], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(LMColor.textPrimary.opacity(0.1)))
                    .frame(height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Stage \(stage.rawValue + 1) of \(WorldStage.allCases.count), \(stage.title)"))
    }
}

struct StageReachedBanner: View {
    var stage: WorldStage

    var body: some View {
        HStack(spacing: LMSpace.s) {
            Image(systemName: "sparkles").foregroundStyle(LMColor.reward)
            Text("\(stage.title) reached").font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
        }
        .padding(.horizontal, LMSpace.l)
        .frame(minHeight: 48)
        .glassCard(radius: 24, border: LMColor.rewardFill.opacity(0.5))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Confirms the journey: how long, what it costs, how it works.
struct PlotCourseSheet: View {
    var world: WorldState
    var snapshot: OdysseySnapshot
    var onLaunch: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        let rules = app.odyssey.rules
        let minutes = rules.travelMinutes(for: world.blueprint)
        let cost = rules.expeditionCost(for: world.blueprint)
        VStack(spacing: LMSpace.m) {
            HStack(spacing: LMSpace.l) {
                RocketView(loadout: snapshot.loadout, heading: .pi / 2, thrust: 0.6).frame(width: 70, height: 70)
                Image(systemName: "ellipsis").foregroundStyle(LMColor.textTertiary)
                WorldView(world: world.blueprint, silhouette: true, animate: false, scale: 0.34).frame(width: 70, height: 70)
            }
            Text("Plot a course").font(LMFont.title).foregroundStyle(LMColor.textPrimary)
            Text("Your ship travels while you focus. \(minutes) minutes of focus — across one or more sessions — will bring it there.")
                .font(LMFont.body).foregroundStyle(LMColor.textSecondary).multilineTextAlignment(.center)
            HStack {
                Text("Fuel").foregroundStyle(LMColor.textSecondary)
                Spacer()
                Text(cost == 0 ? String(localized: "Free") : "\(cost)").foregroundStyle(LMColor.reward)
                if cost > 0 { StardustGlyph().frame(width: 12, height: 12) }
            }
            .font(LMFont.headline)
            .padding(.horizontal, LMSpace.m)
            .frame(minHeight: 48)
            .glassCard(radius: LMRadius.row)
            CosmicButton(title: "Launch", systemImage: "flame", kind: .reward) { onLaunch() }
                .disabled(snapshot.balance < cost)
                .accessibilityIdentifier("plot.launch")
            if snapshot.balance < cost {
                Text("You need \(cost - snapshot.balance) more stardust.").font(LMFont.footnote).foregroundStyle(LMColor.textTertiary)
            }
        }
        .padding(LMSpace.l)
        .presentationBackground(LMColor.bgRaised)
    }
}
