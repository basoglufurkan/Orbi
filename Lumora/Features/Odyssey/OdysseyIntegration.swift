import SwiftUI

/// Home: one compact line about the Odyssey — the journey, a world waiting,
/// or the next world forming. Tap to open the Odyssey.
struct OdysseyStatusRow: View {
    @Environment(AppModel.self) private var app

    static func hasContent(_ app: AppModel) -> Bool {
        let s = app.odyssey.snapshot
        return s.introSeen || !s.worlds.isEmpty
    }

    var body: some View {
        let s = app.odyssey.snapshot
        Button {
            app.haptics.selection()
            app.selectedTab = .odyssey
        } label: {
            HStack(spacing: LMSpace.s) {
                RocketGlyph()
                    .stroke(LMColor.calm, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text(line(s)).font(LMFont.footnote.weight(.semibold)).foregroundStyle(LMColor.textPrimary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    if let e = s.expedition {
                        JourneyBar(fraction: e.fraction, tint: LMColor.calm).frame(height: 4)
                    }
                }
                Spacer(minLength: 0)
                StardustPill(amount: s.balance, compact: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minHeight: 46)
            .glassCard(radius: 23)
        }
        .buttonStyle(PressScaleStyle())
        .padding(.bottom, LMSpace.s)
        .accessibilityIdentifier("home.odyssey")
    }

    private func line(_ s: OdysseySnapshot) -> String {
        if let a = s.pendingArrival { return String(localized: "Your ship reached \(a.world.blueprint.name) · land") }
        if let e = s.nextEvent, e.day == app.today, !s.nextEventWitnessed {
            return String(localized: "Today: \(e.kind.title) · focus to witness it")
        }
        if let e = s.expedition { return String(localized: "En route to \(e.world.blueprint.name) · \(e.remainingMinutes) min") }
        if let w = s.worlds.first(where: { $0.status == .uncharted }) {
            return String(localized: "A new world awaits: \(w.blueprint.name)")
        }
        if let t = s.nextEmergence { return String(localized: "Next world forming · \(t.minutesRemaining) min") }
        return String(localized: "Your Odyssey")
    }
}

/// Focus setup: what this session will do in the Odyssey.
struct SetupOdysseyLine: View {
    var minutes: Int
    @Environment(AppModel.self) private var app

    var body: some View {
        let s = app.odyssey.snapshot
        HStack(spacing: 6) {
            StardustGlyph().frame(width: 12, height: 12)
            Text(text(s, minutes: minutes))
                .font(LMFont.footnote.weight(.semibold))
                .foregroundStyle(LMColor.reward)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    private func text(_ s: OdysseySnapshot, minutes: Int) -> String {
        let dust = minutes + app.odyssey.rules.completionBonus
        if let e = s.expedition {
            return e.remainingMinutes <= minutes
                ? String(localized: "+\(dust) stardust · this session lands you on \(e.world.blueprint.name)")
                : String(localized: "+\(dust) stardust · powers your ship to \(e.world.blueprint.name)")
        }
        if let t = s.nextEmergence, t.minutesRemaining <= minutes {
            return String(localized: "+\(dust) stardust · a new world will form")
        }
        return String(localized: "+\(dust) stardust")
    }
}

/// Active focus: a quiet reminder of the journey this session powers.
struct ExpeditionChip: View {
    var segment: TimerSegment
    var now: Date
    @Environment(AppModel.self) private var app

    var body: some View {
        if let e = app.odyssey.snapshot.expedition {
            let live = max(0, e.remainingMinutes - Int(segment.elapsed(at: now) / 60))
            HStack(spacing: 6) {
                RocketGlyph()
                    .stroke(LMColor.calm, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 14, height: 14)
                Text(live == 0 ? String(localized: "\(e.world.blueprint.name) · arriving") : String(localized: "\(e.world.blueprint.name) · \(live) min to arrival"))
                    .font(LMFont.footnote.weight(.medium))
                    .foregroundStyle(LMColor.textSecondary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 28)
            .background(Capsule().fill(LMColor.textPrimary.opacity(0.06)))
            .accessibilityElement(children: .combine)
        }
    }
}

/// Completion summary: what this session did in the Odyssey.
struct OdysseySummaryCard: View {
    var sessionID: UUID
    @Environment(AppModel.self) private var app
    @State private var landing: ExpeditionState?

    var body: some View {
        let summary = app.odyssey.summary(for: sessionID)
        if !summary.isEmpty || summary.expeditionProgress != nil {
            VStack(alignment: .leading, spacing: LMSpace.s) {
                HStack(spacing: 6) {
                    StardustGlyph().frame(width: 14, height: 14)
                    Text("+\(summary.stardust) stardust").font(LMFont.headline).foregroundStyle(LMColor.reward)
                    Spacer()
                    if let rank = summary.rankUp {
                        Text("Rank up · \(rank.title)").font(LMFont.footnote.weight(.semibold)).foregroundStyle(LMColor.calm)
                    }
                }
                if let a = summary.arrival {
                    if app.odyssey.snapshot.pendingArrival?.id == a.id {
                        Button { landing = a } label: {
                            row(world: a.world, veiled: true, eyebrow: String(localized: "Arrived"),
                                title: String(localized: "Your ship reached \(a.world.blueprint.name)"),
                                action: String(localized: "Land"))
                        }
                        .buttonStyle(PressScaleStyle())
                        .accessibilityIdentifier("summary.land")
                    } else {
                        Button { open(a.world.ordinal) } label: {
                            row(world: a.world, eyebrow: String(localized: "Arrived"),
                                title: String(localized: "You landed on \(a.world.blueprint.name)"),
                                action: String(localized: "See it"))
                        }
                        .buttonStyle(PressScaleStyle())
                    }
                } else if let e = summary.expeditionProgress {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(e.world.blueprint.name) · \(e.remainingMinutes) min to arrival")
                            .font(LMFont.footnote).foregroundStyle(LMColor.textSecondary)
                        JourneyBar(fraction: e.fraction, showsShip: true, loadout: app.odyssey.snapshot.loadout)
                    }
                }
                ForEach(summary.emerged) { w in
                    Button { open(w.ordinal) } label: {
                        row(world: w, eyebrow: String(localized: "A new world formed"),
                            title: w.blueprint.archetype.displayName, action: String(localized: "See it"))
                    }
                    .buttonStyle(PressScaleStyle())
                }
                if let g = summary.galaxyIgnited {
                    Label(String(localized: "\(g.name) ignited — a new galaxy opens"), systemImage: "sparkles")
                        .font(LMFont.footnote.weight(.semibold)).foregroundStyle(LMColor.reward)
                }
                if let h = summary.horizon {
                    Label(String(localized: "Horizon reached · +\(h.reward) stardust"), systemImage: "scope")
                        .font(LMFont.footnote.weight(.semibold)).foregroundStyle(LMColor.reward)
                }
                if let trail = summary.chainTrail {
                    Label(String(localized: "\(trail.chainRequirement ?? 0) horizons in a row · \(trail.title) trail earned"), systemImage: "link")
                        .font(LMFont.footnote.weight(.semibold)).foregroundStyle(LMColor.calm)
                }
                if let event = summary.event {
                    HStack(spacing: LMSpace.s) {
                        CosmicEventArt(kind: event.kind, animate: false)
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            EyebrowText(String(localized: "Rare event witnessed"), color: LMColor.calm)
                            Text(event.kind.title).font(LMFont.callout.weight(.semibold)).foregroundStyle(LMColor.textPrimary)
                        }
                        Spacer(minLength: 0)
                        Text("+\(app.odyssey.rules.eventReward)").font(LMFont.footnote.weight(.semibold)).foregroundStyle(LMColor.reward)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(LMSpace.m)
            .glassCard(radius: 22, border: LMColor.rewardFill.opacity(0.25))
            .fullScreenCover(item: $landing) { e in
                ArrivalView(expedition: e, onExplore: { app.timer.acknowledge() }) {
                    app.odyssey.markArrivalSeen(e.id)
                    landing = nil
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("summary.odyssey")
        }
    }

    private func row(world: WorldState, veiled: Bool? = nil, eyebrow: String, title: String, action: String) -> some View {
        HStack(spacing: LMSpace.s) {
            WorldThumb(world: world, size: 44, veiled: veiled)
            VStack(alignment: .leading, spacing: 2) {
                EyebrowText(eyebrow, color: LMColor.calm)
                Text(title).font(LMFont.callout.weight(.semibold)).foregroundStyle(LMColor.textPrimary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Text(action).font(LMFont.footnote.weight(.semibold)).foregroundStyle(LMColor.reward)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(LMColor.textTertiary)
        }
    }

    private func open(_ ordinal: Int) {
        app.timer.acknowledge()
        app.odysseyFocusWorld = ordinal
        app.selectedTab = .odyssey
    }
}
