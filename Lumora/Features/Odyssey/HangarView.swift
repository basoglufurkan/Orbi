import SwiftUI

/// The hangar: your ship, its hull, paint and engine trail.
struct HangarView: View {
    enum Slot: Hashable { case hull, paint, trail }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var slot: Slot = .hull
    @State private var errorText: String?
    @State private var paywall: PlusFeature?

    var body: some View {
        let snap = app.odyssey.snapshot
        ZStack(alignment: .topLeading) {
            CosmicBackgroundView(mood: .home, light: 0.45, starOpacity: 0.9)
            ScrollView {
                VStack(alignment: .leading, spacing: LMSpace.m) {
                    HStack {
                        Spacer()
                        StardustPill(amount: snap.balance)
                    }
                    .padding(.top, LMSpace.xs)
                    RocketView(loadout: snap.loadout, heading: 0.18, thrust: 0.7)
                        .frame(height: 280)
                        .accessibilityHidden(true)
                    Text("Hangar").font(LMFont.voice(.largeTitle)).foregroundStyle(LMColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Every part is earned with stardust from your focus. Nothing here can be bought with money; Orbi+ finishes ask for stardust too.")
                        .font(LMFont.callout).foregroundStyle(LMColor.textSecondary)
                    CosmicSegmented(options: [(Slot.hull, String(localized: "Hull")), (Slot.paint, String(localized: "Paint")),
                                              (Slot.trail, String(localized: "Trail"))], selection: $slot)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: LMSpace.s), GridItem(.flexible(), spacing: LMSpace.s)],
                              spacing: LMSpace.s) {
                        ForEach(parts, id: \.key) { part in
                            PartCard(part: part, snapshot: snap) { select(part, snap: snap) }
                        }
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
        .plusPaywall($paywall, screen: "hangar")
        .alert(String(localized: "Not yet"), isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
        .telemetryScreen("hangar")
    }

    private var parts: [ShipPart] {
        switch slot {
        case .hull: ShipHull.allCases.map(ShipPart.hull)
        case .paint: ShipPaint.allCases.map(ShipPart.paint)
        case .trail: ShipTrail.allCases.map(ShipPart.trail)
        }
    }

    private func select(_ part: ShipPart, snap: OdysseySnapshot) {
        if part.isPlus, !app.plus.isActive {
            app.haptics.selection()
            paywall = .shipFinishes
            return
        }
        if snap.ownedParts.contains(part) {
            app.haptics.selection()
            withAnimation(LMSpring.bloom) { app.odyssey.equip(part) }
            Telemetry.log(.shipPartEquipped(part: part.key))
            return
        }
        do {
            try app.odyssey.buy(part)
            app.haptics.success()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct PartCard: View {
    var part: ShipPart
    var snapshot: OdysseySnapshot
    var action: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        let owned = snapshot.ownedParts.contains(part)
        let equipped = isEquipped
        let rank = app.odyssey.rules.requiredRank(for: part)
        let price = app.odyssey.rules.price(of: part)
        Button(action: action) {
            VStack(spacing: 6) {
                preview.frame(height: 96)
                Text(part.title).font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
                Group {
                    if part.isPlus, !app.plus.isActive {
                        PlusBadge()
                    } else if equipped {
                        Text("Equipped").foregroundStyle(LMColor.calm)
                    } else if owned {
                        Text("Equip").foregroundStyle(LMColor.textSecondary)
                    } else if case let .trail(t) = part, let need = t.chainRequirement {
                        Label(String(localized: "\(need) horizons in a row"), systemImage: "link").foregroundStyle(LMColor.textTertiary)
                    } else if snapshot.rank.level < rank {
                        Label(String(localized: "Rank \(rank)"), systemImage: "lock.fill").foregroundStyle(LMColor.textTertiary)
                    } else {
                        HStack(spacing: 4) {
                            Text("\(price)")
                            StardustGlyph().frame(width: 11, height: 11)
                        }
                        .foregroundStyle(LMColor.reward)
                    }
                }
                .font(LMFont.footnote.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(LMSpace.s)
            .glassCard(radius: 22, border: equipped ? LMColor.calm.opacity(0.6) : nil)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(equipped ? .isSelected : [])
    }

    private var isEquipped: Bool {
        switch part {
        case let .hull(h): snapshot.loadout.hull == h
        case let .paint(p): snapshot.loadout.paint == p
        case let .trail(t): snapshot.loadout.trail == t
        }
    }

    private var preview: some View {
        var loadout = snapshot.loadout
        var heading = 0.3, thrust = 0.3
        switch part {
        case let .hull(h): loadout.hull = h
        case let .paint(p): loadout.paint = p
        case let .trail(t):
            loadout.trail = t
            heading = .pi / 2
            thrust = 1
        }
        return RocketView(loadout: loadout, heading: heading, thrust: thrust, animate: false)
    }
}

/// Everything found on charted worlds.
struct CodexView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let charted = app.odyssey.snapshot.worlds.filter(\.isCharted)
        ZStack(alignment: .topLeading) {
            CosmicBackgroundView(mood: .home, light: 0.3, starOpacity: 0.6)
            ScrollView {
                VStack(alignment: .leading, spacing: LMSpace.m) {
                    Text("Codex").font(LMFont.voice(.largeTitle)).foregroundStyle(LMColor.textPrimary)
                        .padding(.top, 56)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(charted.count) of \(WorldLexicon.findCount) discoveries")
                        .font(LMFont.callout).foregroundStyle(LMColor.textSecondary)
                    if !app.odyssey.snapshot.witnessedEvents.isEmpty {
                        OdysseySectionHeader(title: String(localized: "Rare events"),
                                             trailing: "\(app.odyssey.snapshot.witnessedEvents.count)")
                        ForEach(app.odyssey.snapshot.witnessedEvents) { event in
                            HStack(alignment: .top, spacing: LMSpace.m) {
                                CosmicEventArt(kind: event.kind, animate: false)
                                    .frame(width: 54, height: 54)
                                    .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    EyebrowText(event.date.formatted(date: .abbreviated, time: .omitted), color: LMColor.reward)
                                    Text(event.kind.title).font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
                                    Text(event.kind.codexLine).font(LMFont.callout).foregroundStyle(LMColor.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(LMSpace.m)
                            .glassCard(radius: LMRadius.row)
                            .accessibilityElement(children: .combine)
                        }
                        OdysseySectionHeader(title: String(localized: "Worlds"), trailing: "\(charted.count)")
                    }
                    if charted.isEmpty {
                        VStack(spacing: LMSpace.s) {
                            PellView(mood: .curious, showsLabel: false)
                            Text("Land on your first world to begin the Codex.")
                                .font(LMFont.body).foregroundStyle(LMColor.textSecondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LMSpace.xxl)
                    }
                    ForEach(charted) { world in
                        let find = WorldLexicon.find(world.blueprint.findIndex)
                        NavigationLink(value: OdysseyRoute.world(world.ordinal)) {
                            HStack(alignment: .top, spacing: LMSpace.m) {
                                WorldThumb(world: world, size: 54)
                                VStack(alignment: .leading, spacing: 3) {
                                    EyebrowText("\(find.kindLabel) · \(world.blueprint.name)", color: LMColor.reward)
                                    Text(find.title).font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
                                    Text(find.detail).font(LMFont.callout).foregroundStyle(LMColor.textSecondary)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(LMColor.textTertiary)
                                    .padding(.top, 4)
                            }
                            .padding(LMSpace.m)
                            .glassCard(radius: LMRadius.row)
                            .accessibilityElement(children: .combine)
                        }
                        .buttonStyle(PressScaleStyle())
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
}

/// Choose a horizon: a goal you set for yourself, rewarded with stardust.
struct HorizonPickerSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var kind: HorizonKind = .sessions
    @State private var target = 5
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LMSpace.m) {
                Text("Set your horizon").font(LMFont.voice(.title)).foregroundStyle(LMColor.textPrimary)
                    .padding(.top, LMSpace.l)
                Text("Choose something a little further than today. Reaching it brings a burst of stardust; missing a weekly one simply rests — no penalty.")
                    .font(LMFont.callout).foregroundStyle(LMColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(HorizonKind.allCases) { k in
                    VStack(alignment: .leading, spacing: LMSpace.s) {
                        Button {
                            app.haptics.selection()
                            withAnimation(LMSpring.snap) {
                                kind = k
                                if !k.presets.contains(target) { target = k.presets[1] }
                            }
                        } label: {
                            HStack {
                                Image(systemName: k.symbol).frame(width: 28).foregroundStyle(kind == k ? LMColor.reward : LMColor.textTertiary)
                                Text(k.title).font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
                                Spacer()
                                if kind == k { Image(systemName: "checkmark.circle.fill").foregroundStyle(LMColor.reward) }
                            }
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        if kind == k {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: LMSpace.xs) {
                                    ForEach(k.presets, id: \.self) { value in
                                        SelectChip(title: k == .weeklyHours ? "\(value)h" : "\(value)", isSelected: value == target,
                                                   tint: LMColor.rewardFill) {
                                            app.haptics.selection()
                                            target = value
                                        }
                                    }
                                }
                            }
                            .scrollClipDisabled()
                        }
                    }
                    .padding(LMSpace.m)
                    .glassCard(radius: LMRadius.row, border: kind == k ? LMColor.rewardFill.opacity(0.45) : nil)
                }
                HStack {
                    Text("Reward").foregroundStyle(LMColor.textSecondary)
                    Spacer()
                    Text("+\(kind.rewardStardust(target: target))").foregroundStyle(LMColor.reward)
                    StardustGlyph().frame(width: 13, height: 13)
                }
                .font(LMFont.headline)
                CosmicButton(title: "Start this horizon", systemImage: "scope", kind: .reward) {
                    app.odyssey.startHorizon(kind: kind, target: target)
                    app.haptics.sessionStart()
                    dismiss()
                }
                .accessibilityIdentifier("horizon.start")
            }
            .padding(.horizontal, LMSpace.l)
            .padding(.bottom, LMSpace.l)
        }
        .presentationBackground(LMColor.bgRaised)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let snap = app.odyssey.snapshot
            let last = snap.horizon ?? snap.unseenHorizon
            let s = app.odyssey.suggestion(after: last?.kind, target: last?.target)
            kind = s.kind
            target = s.target
        }
    }
}

/// A new navigator rank.
struct RankUpView: View {
    var rank: NavigatorRank
    var onContinue: () -> Void
    @Environment(AppModel.self) private var app
    @State private var shown = false

    var body: some View {
        ZStack {
            CosmicBackgroundView(mood: .reward, light: 0.8)
            VStack(spacing: LMSpace.m) {
                // Scrolls at large text sizes so Onward is always reachable.
                FittingScrollView(alignment: .center) {
                    VStack(spacing: LMSpace.m) {
                        RankInsignia(level: rank.level).frame(width: 220, height: 220)
                            .scaleEffect(shown ? 1 : 0.6).opacity(shown ? 1 : 0)
                        EyebrowText(String(localized: "New rank · \(rank.level)"), color: LMColor.reward)
                        Text(rank.title).font(LMFont.voice(.largeTitle)).foregroundStyle(LMColor.textPrimary)
                            .multilineTextAlignment(.center)
                        if let next = rank.next {
                            Text("Next: \(next.title) at \(next.minXP.formatted()) XP")
                                .font(LMFont.callout).foregroundStyle(LMColor.textSecondary)
                                .multilineTextAlignment(.center)
                        } else {
                            Text("The highest rank. Every sky is yours to keep.").font(LMFont.callout).foregroundStyle(LMColor.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                CosmicButton(title: "Onward", systemImage: "sparkles", kind: .reward) { onContinue() }
                    .accessibilityIdentifier("rankup.continue")
            }
            .padding(LMSpace.l)
        }
        .onAppear {
            app.haptics.playCelebration(milestone: false, reduced: true)
            app.audio.play(.start)
            withAnimation(LMSpring.bloom.delay(0.15)) { shown = true }
            AccessibilityNotification.Announcement(String(localized: "New rank: \(rank.title)")).post()
        }
    }
}

/// Rank insignia: one ring per level, a star crown, slowly turning.
struct RankInsignia: View {
    var level: Int
    @Environment(\.motionLevel) private var motion

    var body: some View {
        TimelineView(.animation(minimumInterval: motion.frameInterval(30), paused: !motion.animatesContinuously)) { tl in
            Canvas { ctx, size in
                Self.draw(&ctx, in: size, level: level,
                          time: motion.animatesContinuously ? tl.date.timeIntervalSinceReferenceDate : 0)
            }
        }
        .accessibilityHidden(true)
    }

    /// One ring per rank around a gold star; rings turn slowly with `time`.
    nonisolated static func draw(_ ctx: inout GraphicsContext, in size: CGSize, level: Int, time t: Double) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let R = min(size.width, size.height) / 2
        ctx.blendMode = .plusLighter
        CelestialPainter.glow(&ctx, at: c, radius: R, color: Color(hex: Palette.warmGold), intensity: 0.4)
        for i in 0..<max(1, level) {
            let r = R * (0.32 + 0.085 * CGFloat(i))
            var arc = Path()
            let spin = t * (i.isMultiple(of: 2) ? 0.2 : -0.14)
            arc.addArc(center: c, radius: r, startAngle: .radians(spin), endAngle: .radians(spin + .pi * 1.6), clockwise: false)
            ctx.stroke(arc, with: .color(Color(hex: i.isMultiple(of: 2) ? Palette.warmGold : Palette.starlightCyan).opacity(0.75)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        CelestialPainter.star(&ctx, at: c, radius: R * 0.24, points: 4, color: Color(hex: Palette.warmGold), brightness: 1.3, flare: true)
    }
}
