import SwiftUI

enum OdysseyRoute: Hashable {
    case galaxy(Int)
    case world(Int)
    case hangar
    case codex
}

/// The Odyssey hub: your rank and stardust, your ship's journey, the next
/// world forming, your horizon, and every galaxy you've ignited.
struct OdysseyView: View {
    @Environment(AppModel.self) private var app
    @State private var path = NavigationPath()
    @State private var showHorizonPicker = false
    @State private var landing: ExpeditionState?
    @State private var rankUp: NavigatorRank?
    @State private var confirmRecall = false

    var body: some View {
        let snap = app.odyssey.snapshot
        NavigationStack(path: $path) {
            ZStack {
                CosmicBackgroundView(mood: .home, light: 0.5, starOpacity: 0.7)
                ScrollView {
                    VStack(alignment: .leading, spacing: LMSpace.m) {
                        header(snap)
                        GalaxyHero(snapshot: snap)
                            .frame(height: 230)
                            .padding(.horizontal, -LMSpace.l)
                            .accessibilityHidden(true)
                        if !snap.introSeen { introCard }
                        if let arrival = snap.pendingArrival { arrivalBanner(arrival) }
                        if let reward = snap.unseenHorizon { horizonRewardBanner(reward) }
                        // On its day the rare event leads; otherwise it waits below your journey.
                        if let event = snap.nextEvent, event.day == app.today {
                            CosmicEventCard(event: event, witnessed: snap.nextEventWitnessed)
                        }
                        expeditionCard(snap)
                        if let event = snap.nextEvent, event.day != app.today {
                            CosmicEventCard(event: event, witnessed: false)
                        }
                        if let teaser = snap.nextEmergence { EmergenceTeaserCard(teaser: teaser) }
                        horizonCard(snap)
                        galaxies(snap)
                        HStack(spacing: LMSpace.s) {
                            linkCard(title: String(localized: "Hangar"), detail: snap.loadout.hull.title, route: .hangar) {
                                RocketView(loadout: snap.loadout, heading: 0.4, thrust: 0.5, animate: false)
                            }
                            linkCard(title: String(localized: "Codex"),
                                     detail: snap.chartedCount == 1 ? String(localized: "1 discovery") : String(localized: "\(snap.chartedCount) discoveries"), route: .codex) {
                                Image(systemName: "book.closed").font(.title2).foregroundStyle(LMColor.calm)
                            }
                        }
                        Color.clear.frame(height: 96)
                    }
                    .padding(.horizontal, LMSpace.l)
                    .readableColumn()
                }
                .scrollIndicators(.hidden)
                .statusBarScrim()
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: OdysseyRoute.self) { route in
                switch route {
                case let .galaxy(i): GalaxyDetailView(index: i)
                case let .world(o): WorldDetailView(ordinal: o)
                case .hangar: HangarView()
                case .codex: CodexView()
                }
            }
        }
        .sheet(isPresented: $showHorizonPicker) {
            HorizonPickerSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $landing) { expedition in
            ArrivalView(expedition: expedition) {
                app.odyssey.markArrivalSeen(expedition.id)
                landing = nil
            }
        }
        .fullScreenCover(item: $rankUp) { rank in
            RankUpView(rank: rank) {
                app.odyssey.markRankCelebrated()
                rankUp = nil
            }
        }
        .onAppear {
            app.odyssey.sync()
            if let ordinal = app.odysseyFocusWorld {
                app.odysseyFocusWorld = nil
                path.append(OdysseyRoute.world(ordinal))
            }
            let s = app.odyssey.snapshot
            if s.introSeen, s.rank.level > app.odyssey.profile().celebratedRankLevel { rankUp = s.rank }
        }
        .onChange(of: app.odysseyFocusWorld) { _, ordinal in
            // A world opened from elsewhere (the Universe sky, a summary) while this tab stays alive.
            guard let ordinal else { return }
            app.odysseyFocusWorld = nil
            path.append(OdysseyRoute.world(ordinal))
        }
        .confirmationDialog(String(localized: "Call your ship home?"), isPresented: $confirmRecall, titleVisibility: .visible) {
            Button(String(localized: "Recall ship"), role: .destructive) { app.odyssey.recallExpedition() }
            Button(String(localized: "Keep travelling"), role: .cancel) {}
        } message: {
            Text("Its fuel is refunded in full. The world will wait for you.")
        }
    }

    // MARK: Header

    private func header(_ snap: OdysseySnapshot) -> some View {
        VStack(alignment: .leading, spacing: LMSpace.xs) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    EyebrowText(String(localized: "Rank \(snap.rank.level) · \(snap.rank.title)"), color: LMColor.calm)
                    Text("Your Odyssey")
                        .font(LMFont.voice(.largeTitle))
                        .foregroundStyle(LMColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer()
                StardustPill(amount: snap.balance)
                    .accessibilityIdentifier("odyssey.stardust")
            }
            if let next = snap.nextRank {
                VStack(alignment: .leading, spacing: 4) {
                    JourneyBar(fraction: snap.rankFraction, tint: LMColor.focus)
                    Text("\(next.minXP - snap.xp) XP to \(next.title)")
                        .font(LMFont.footnote).foregroundStyle(LMColor.textTertiary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, LMSpace.m)
    }

    // MARK: Cards

    private var introCard: some View {
        VStack(alignment: .leading, spacing: LMSpace.s) {
            EyebrowText(String(localized: "A new chapter"), color: LMColor.reward)
            Text("Your light has been noticed.")
                .font(LMFont.voice(.title)).foregroundStyle(LMColor.textPrimary)
            Text("Every minute you focus is now stardust. Worlds will form at the edge of your sky, and your ship can travel to them, powered by your focus. Your first journey is free.")
                .font(LMFont.body).foregroundStyle(LMColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            CosmicButton(title: "Begin the Odyssey", systemImage: "sparkles", kind: .reward, height: 52) {
                app.odyssey.markIntroSeen()
            }
            .accessibilityIdentifier("odyssey.begin")
        }
        .padding(LMSpace.l)
        .glassCard(border: LMColor.rewardFill.opacity(0.35))
    }

    private func arrivalBanner(_ e: ExpeditionState) -> some View {
        Button { landing = e } label: {
            HStack(spacing: LMSpace.m) {
                WorldThumb(world: e.world, size: 58, veiled: true)
                VStack(alignment: .leading, spacing: 3) {
                    EyebrowText(String(localized: "Arrived"), color: LMColor.reward)
                    Text("Your ship reached \(e.world.blueprint.name)")
                        .font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
                    Text("Tap to land").font(LMFont.footnote).foregroundStyle(LMColor.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.down.forward.circle.fill").font(.title2).foregroundStyle(LMColor.reward)
            }
            .padding(LMSpace.m)
            .glassCard(tint: LMColor.rewardFill, border: LMColor.rewardFill.opacity(0.5))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityIdentifier("odyssey.land")
    }

    private func horizonRewardBanner(_ h: HorizonState) -> some View {
        HStack(spacing: LMSpace.m) {
            Image(systemName: "sparkles").font(.title2).foregroundStyle(LMColor.reward)
            VStack(alignment: .leading, spacing: 3) {
                EyebrowText(String(localized: "Horizon reached"), color: LMColor.reward)
                Text(h.kind.title).font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
            }
            Spacer(minLength: 0)
            Button {
                app.haptics.success()
                app.odyssey.markHorizonRewardSeen(h.id)
                showHorizonPicker = true
            } label: {
                HStack(spacing: 4) {
                    Text("+\(h.reward)")
                    StarShape(points: 4, innerRatio: 0.3).frame(width: 12, height: 12).accessibilityHidden(true)
                }
                .font(LMFont.headline)
                .foregroundStyle(LMColor.onAccent)
                .padding(.horizontal, 14).frame(minHeight: 40)
                .background(Capsule().fill(LMColor.rewardFill))
            }
            .accessibilityLabel(Text("Collect \(h.reward) stardust"))
        }
        .padding(LMSpace.m)
        .glassCard(border: LMColor.rewardFill.opacity(0.4))
    }

    @ViewBuilder
    private func expeditionCard(_ snap: OdysseySnapshot) -> some View {
        if let e = snap.expedition {
            VStack(alignment: .leading, spacing: LMSpace.s) {
                HStack(spacing: LMSpace.m) {
                    WorldThumb(world: e.world, size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        EyebrowText(String(localized: "En route"), color: LMColor.calm)
                        Text(e.world.blueprint.name).font(LMFont.title).foregroundStyle(LMColor.textPrimary)
                        Text(e.world.blueprint.archetype.displayName).font(LMFont.footnote).foregroundStyle(LMColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                JourneyBar(fraction: e.fraction, showsShip: true, loadout: snap.loadout)
                Text(e.remainingMinutes == 1 ? String(localized: "1 minute of focus to arrival") : String(localized: "\(e.remainingMinutes) minutes of focus to arrival"))
                    .font(LMFont.callout).foregroundStyle(LMColor.textSecondary)
                HStack(spacing: LMSpace.s) {
                    CosmicButton(title: "Focus now", systemImage: "sparkle", height: 48) { app.beginFocus(taskID: nil) }
                    Button(String(localized: "Recall")) { confirmRecall = true }
                        .font(LMFont.headline.weight(.medium))
                        .foregroundStyle(LMColor.textSecondary)
                        .frame(minWidth: 88, minHeight: 48)
                }
            }
            .padding(LMSpace.l)
            .glassCard()
            .accessibilityIdentifier("odyssey.expedition")
        } else if let waiting = snap.worlds.first(where: { $0.status == .uncharted }) {
            Button { path.append(OdysseyRoute.world(waiting.ordinal)) } label: {
                HStack(spacing: LMSpace.m) {
                    WorldThumb(world: waiting, size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        EyebrowText(String(localized: "A world awaits"), color: LMColor.calm)
                        Text(waiting.blueprint.name).font(LMFont.title).foregroundStyle(LMColor.textPrimary)
                        Text("Plot a course").font(LMFont.callout).foregroundStyle(LMColor.calm)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(LMColor.textTertiary)
                }
                .padding(LMSpace.l)
                .glassCard(border: LMColor.calm.opacity(0.35))
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityIdentifier("odyssey.awaits")
        } else {
            HStack(spacing: LMSpace.m) {
                RocketView(loadout: snap.loadout, heading: 0, thrust: 0.15).frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    EyebrowText(String(localized: "Docked"), color: LMColor.textTertiary)
                    Text("Your ship is ready. The next world is forming at the edge of your sky.")
                        .font(LMFont.callout).foregroundStyle(LMColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(LMSpace.l)
            .glassCard()
        }
    }

    @ViewBuilder
    private func horizonCard(_ snap: OdysseySnapshot) -> some View {
        if let h = snap.horizon {
            VStack(alignment: .leading, spacing: LMSpace.s) {
                HStack {
                    Image(systemName: h.kind.symbol).foregroundStyle(LMColor.reward)
                    EyebrowText(String(localized: "Your horizon"), color: LMColor.reward)
                    Spacer()
                    HStack(spacing: 3) {
                        Text("+\(h.reward)")
                        StardustGlyph().frame(width: 11, height: 11)
                    }
                    .font(LMFont.footnote.weight(.semibold)).foregroundStyle(LMColor.reward)
                }
                Text(h.kind.title).font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
                JourneyBar(fraction: h.fraction, tint: LMColor.rewardFill)
                HStack {
                    Text(h.label).font(LMFont.callout).foregroundStyle(LMColor.textSecondary)
                    Spacer()
                    if let ends = h.endsAt {
                        Text("Until \(ends.formatted(.dateTime.weekday(.wide)))").font(LMFont.footnote).foregroundStyle(LMColor.textTertiary)
                    }
                }
                chainLine(snap)
                Button(String(localized: "Change horizon")) { showHorizonPicker = true }
                    .font(LMFont.footnote.weight(.semibold)).foregroundStyle(LMColor.calm)
                    .frame(minHeight: 32)
            }
            .padding(LMSpace.l)
            .glassCard()
            .accessibilityElement(children: .combine)
        } else {
            Button { showHorizonPicker = true } label: {
                HStack(spacing: LMSpace.m) {
                    Image(systemName: "scope").font(.title2).foregroundStyle(LMColor.reward)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Set your next horizon").font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
                        Text("A goal you choose. Reach it for a burst of stardust.")
                            .font(LMFont.footnote).foregroundStyle(LMColor.textSecondary)
                        chainLine(snap)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(LMColor.reward)
                }
                .padding(LMSpace.l)
                .glassCard(border: LMColor.rewardFill.opacity(0.3))
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityIdentifier("odyssey.setHorizon")
        }
    }

    /// Horizons reached in a row, and the trail the next link would earn.
    @ViewBuilder
    private func chainLine(_ snap: OdysseySnapshot) -> some View {
        if let next = ShipTrail.allCases.first(where: { ($0.chainRequirement ?? 0) > snap.horizonChain }),
           let need = next.chainRequirement {
            Label(snap.horizonChain > 0
                  ? String(localized: "\(snap.horizonChain) in a row · reach \(need) for the \(next.title) trail")
                  : String(localized: "Reach \(need) in a row for the \(next.title) trail"),
                  systemImage: "link")
                .font(LMFont.footnote).foregroundStyle(LMColor.calm)
        }
    }

    private func galaxies(_ snap: OdysseySnapshot) -> some View {
        VStack(alignment: .leading, spacing: LMSpace.s) {
            OdysseySectionHeader(title: String(localized: "Your galaxies"),
                                 trailing: String(localized: "\(snap.galaxyCount) ignited"))
            ScrollView(.horizontal, showsIndicators: false) {
                // Two cards fill the column exactly, edge to edge with the cards
                // above and below; more scroll on in the same rhythm.
                HStack(alignment: .top, spacing: LMSpace.s) {
                    ForEach(0..<(snap.galaxyCount + 1), id: \.self) { i in
                        let locked = i >= snap.galaxyCount
                        Button { if !locked { path.append(OdysseyRoute.galaxy(i)) } } label: {
                            GalaxyCard(index: i, snapshot: snap, locked: locked)
                        }
                        .buttonStyle(PressScaleStyle())
                        .disabled(locked)
                        .containerRelativeFrame(.horizontal, count: 2, spacing: LMSpace.s)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func linkCard<Icon: View>(title: String, detail: String, route: OdysseyRoute,
                                      @ViewBuilder icon: () -> Icon) -> some View {
        Button { path.append(route) } label: {
            VStack(alignment: .leading, spacing: 6) {
                icon().frame(width: 56, height: 56)
                Text(title).font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
                Text(detail).font(LMFont.footnote).foregroundStyle(LMColor.textSecondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LMSpace.m)
            .glassCard()
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityIdentifier("odyssey.\(route)")
    }
}

/// The newest galaxy, alive, with your ship drifting in front of it.
struct GalaxyHero: View {
    var snapshot: OdysseySnapshot
    @Environment(\.motionLevel) private var motion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let live = motion.animatesContinuously && scenePhase == .active
        let index = max(0, snapshot.galaxyCount - 1)
        let galaxy = GalaxyCatalog.blueprint(index)
        let worlds = snapshot.worlds(inGalaxy: index)
        let brightness = Double(worlds.filter(\.isCharted).count) / Double(max(1, galaxy.capacity))
        TimelineView(.animation(minimumInterval: motion.frameInterval(20), paused: !live)) { tl in
            Canvas { ctx, size in
                let t = live ? tl.date.timeIntervalSinceReferenceDate : nil
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                GalaxyPainter.draw(&ctx, galaxy: galaxy, center: c, radius: min(size.width, size.height) * 0.62,
                                   brightness: 0.35 + 0.65 * brightness, time: t, locked: false)
                let bob = t.map { sin($0 * 0.8) * 4 } ?? 0
                let ship = CGPoint(x: size.width * 0.78, y: size.height * 0.62 + bob)
                RocketPainter.draw(&ctx, loadout: snapshot.loadout, center: ship, length: 46,
                                   heading: -0.5, thrust: snapshot.expedition == nil ? 0.25 : 0.85, time: t)
            }
        }
    }
}

/// A galaxy you've ignited (or the next one, locked).
struct GalaxyCard: View {
    var index: Int
    var snapshot: OdysseySnapshot
    var locked: Bool

    var body: some View {
        let galaxy = GalaxyCatalog.blueprint(index)
        let worlds = snapshot.worlds(inGalaxy: index)
        let charted = worlds.filter(\.isCharted).count
        VStack(alignment: .leading, spacing: 6) {
            // Still: a card's slow spin isn't visible at this size, and a row of
            // live galaxies made the page stutter while scrolling.
            Canvas { ctx, size in
                GalaxyPainter.draw(&ctx, galaxy: galaxy, center: CGPoint(x: size.width / 2, y: size.height / 2),
                                   radius: min(size.width, size.height) * 0.46,
                                   brightness: Double(charted) / Double(max(1, galaxy.capacity)),
                                   time: nil, locked: locked)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            Text(locked ? String(localized: "Unignited") : galaxy.name)
                .font(LMFont.headline).foregroundStyle(locked ? LMColor.textTertiary : LMColor.textPrimary)
                .lineLimit(1)
            // Two lines reserved either way, so every card stands the same height.
            Text(locked ? ignitesLabel : String(localized: "\(charted) of \(galaxy.capacity) charted"))
                .font(LMFont.footnote).foregroundStyle(LMColor.textTertiary)
                .lineLimit(2, reservesSpace: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LMSpace.m)
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    private var ignitesLabel: String {
        let needed = OdysseyRules.standard.galaxyCapacity(index - 1) - snapshot.worlds(inGalaxy: index - 1).count
        return needed == 1 ? String(localized: "Ignites after 1 more world") : String(localized: "Ignites after \(needed) more worlds")
    }
}

/// The next world taking shape: always something just ahead.
struct EmergenceTeaserCard: View {
    var teaser: EmergenceTeaser

    var body: some View {
        HStack(spacing: LMSpace.m) {
            ZStack {
                OrbitalProgressView(progress: teaser.fraction, lineWidth: 3, trackWidth: 2, headSize: 7)
                WorldView(world: teaser.blueprint, silhouette: true, animate: false, scale: 0.26)
            }
            .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 3) {
                EyebrowText(String(localized: "Forming"), color: LMColor.focus)
                Text("Next: \(teaser.blueprint.archetype.displayName)")
                    .font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
                Text(teaser.minutesRemaining == 1 ? String(localized: "1 more minute of focus") : String(localized: "\(teaser.minutesRemaining) more minutes of focus"))
                    .font(LMFont.callout).foregroundStyle(LMColor.textSecondary)
                if teaser.opensGalaxy {
                    Text("It will ignite \(GalaxyCatalog.name(teaser.galaxy)).")
                        .font(LMFont.footnote.weight(.semibold)).foregroundStyle(LMColor.reward)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(LMSpace.l)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("odyssey.forming")
    }
}

/// This week's rare event: what it is, when, and whether you saw it.
struct CosmicEventCard: View {
    var event: CosmicEvent
    var witnessed: Bool
    @Environment(AppModel.self) private var app

    var body: some View {
        let today = event.day == app.today
        VStack(alignment: .leading, spacing: LMSpace.s) {
            CosmicEventArt(kind: event.kind)
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            EyebrowText(today ? String(localized: "Rare event · Today")
                              : String(localized: "Next rare event · \(event.date.formatted(.dateTime.weekday(.wide)))"),
                        color: LMColor.reward)
            Text(event.kind.title).font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
            Text(event.kind.lore).font(LMFont.callout).foregroundStyle(LMColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if witnessed {
                Label(String(localized: "Witnessed · added to your Codex"), systemImage: "checkmark.seal.fill")
                    .font(LMFont.footnote.weight(.semibold)).foregroundStyle(LMColor.calm)
            } else {
                HStack(spacing: 4) {
                    Text(today ? String(localized: "Focus today to witness it") : String(localized: "Focus that day to witness it"))
                    Text("· +\(app.odyssey.rules.eventReward)")
                    StardustGlyph().frame(width: 11, height: 11)
                }
                .font(LMFont.footnote.weight(.semibold)).foregroundStyle(LMColor.reward)
            }
        }
        .padding(LMSpace.m)
        .glassCard(border: today && !witnessed ? LMColor.rewardFill.opacity(0.45) : nil)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("odyssey.event")
    }
}
