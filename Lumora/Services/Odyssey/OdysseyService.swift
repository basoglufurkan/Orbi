import Foundation
import Observation
import SwiftData
import os

// MARK: - Read models

struct WorldState: Identifiable, Equatable, Sendable {
    var id: Int { ordinal }
    var ordinal: Int
    var blueprint: WorldBlueprint
    var galaxy: Int
    var slot: Int
    var status: WorldStatus
    var stage: WorldStage
    var emergedAt: Date
    var visitedAt: Date?

    var isCharted: Bool { status == .charted }
}

struct ExpeditionState: Identifiable, Equatable, Sendable {
    var id: UUID
    var world: WorldState
    var startedAt: Date
    var requiredMinutes: Int
    var progressMinutes: Int
    var cost: Int
    var status: ExpeditionStatus
    var arrivedAt: Date?
    var arrivalSeen: Bool

    var remainingMinutes: Int { max(0, requiredMinutes - progressMinutes) }
    var fraction: Double { requiredMinutes > 0 ? min(1, Double(progressMinutes) / Double(requiredMinutes)) : 1 }
}

struct HorizonState: Identifiable, Equatable, Sendable {
    var id: UUID
    var kind: HorizonKind
    var target: Int
    var progressUnits: Int
    var targetUnits: Int
    var endsAt: Date?
    var reward: Int
    var status: HorizonStatus
    var rewardSeen: Bool

    var fraction: Double { targetUnits > 0 ? min(1, Double(progressUnits) / Double(targetUnits)) : 1 }
    var label: String { kind.progressLabel(progress: progressUnits, target: target) }
}

/// The next world that will emerge, shown as a teaser: always something just ahead.
struct EmergenceTeaser: Equatable, Sendable {
    var blueprint: WorldBlueprint
    var minutesRemaining: Int
    var fraction: Double
    var galaxy: Int
    /// This world will ignite a new galaxy.
    var opensGalaxy: Bool
}

struct OdysseySnapshot: Equatable, Sendable {
    var totalMinutes = 0
    var stardustEarned = 0
    var stardustCredited = 0
    var stardustSpent = 0
    var xp = 0
    var rank = NavigatorRank.all[0]
    var worlds: [WorldState] = []
    var galaxyCount = 1
    var expedition: ExpeditionState?
    /// The most recent arrival whose landing hasn't been shown yet.
    var pendingArrival: ExpeditionState?
    var horizon: HorizonState?
    /// An achieved horizon whose reward hasn't been celebrated yet.
    var unseenHorizon: HorizonState?
    var horizonsAchieved = 0
    var nextEmergence: EmergenceTeaser?
    var loadout = ShipLoadout()
    var ownedParts: Set<ShipPart> = ShipPart.starter
    var introSeen = false
    /// This week's rare event if it is still ahead (or today), else next week's.
    var nextEvent: CosmicEvent?
    /// Today's event has already been witnessed.
    var nextEventWitnessed = false
    /// Every rare event seen so far, newest first.
    var witnessedEvents: [CosmicEvent] = []
    /// Horizons reached in a row right now, and the longest run ever.
    var horizonChain = 0
    var bestHorizonChain = 0

    var balance: Int { stardustEarned + stardustCredited - stardustSpent }
    var chartedCount: Int { worlds.filter(\.isCharted).count }
    var stagesTotal: Int { worlds.reduce(0) { $0 + $1.stage.rawValue } }
    var nextRank: NavigatorRank? { rank.next }
    var rankFraction: Double {
        guard let next = nextRank else { return 1 }
        return Double(xp - rank.minXP) / Double(max(1, next.minXP - rank.minXP))
    }
    func worlds(inGalaxy g: Int) -> [WorldState] { worlds.filter { $0.galaxy == g } }
}

/// What one focus session did in the Odyssey, for the celebration summary.
struct OdysseySessionSummary: Equatable, Sendable {
    var stardust = 0
    var emerged: [WorldState] = []
    var arrival: ExpeditionState?
    var horizon: HorizonState?
    var rankUp: NavigatorRank?
    var galaxyIgnited: GalaxyBlueprint?
    var expeditionProgress: ExpeditionState?
    /// The rare event this session witnessed.
    var event: CosmicEvent?
    /// A chain trail this session's horizon unlocked.
    var chainTrail: ShipTrail?

    var isEmpty: Bool {
        stardust == 0 && emerged.isEmpty && arrival == nil && horizon == nil && rankUp == nil && event == nil
    }
}

enum OdysseyError: LocalizedError, Equatable {
    case insufficientStardust(needed: Int)
    case expeditionUnderway
    case worldUnavailable
    case fullyTerraformed
    case rankTooLow(required: Int)
    case chainRequired(Int)
    case plusRequired

    var errorDescription: String? {
        switch self {
        case let .insufficientStardust(needed): String(localized: "You need \(needed) more stardust. Every focused minute adds some.")
        case .expeditionUnderway: String(localized: "Your ship is already travelling. Recall it first, or let it arrive.")
        case .worldUnavailable: String(localized: "That world can't be reached right now.")
        case .fullyTerraformed: String(localized: "This world is already a wonder.")
        case let .rankTooLow(required): String(localized: "This part unlocks at rank \(required).")
        case let .chainRequired(chain): String(localized: "Reach \(chain) horizons in a row to earn this trail.")
        case .plusRequired: String(localized: "This finish comes with Orbi+.")
        }
    }
}

// MARK: - Service

/// The Odyssey game layer on top of focus history.
///
/// Invariants:
/// - Stardust earned is derived from stored sessions; spending is an
///   idempotent ledger keyed by purpose. The balance can always be recomputed.
/// - Worlds emerge on a deterministic schedule of total focus minutes and are
///   created once per ordinal. `sync` is idempotent and safe to call anytime.
/// - Expedition progress is the sum of focus minutes after departure;
///   arrival is recorded once, attributed to the session that completed it.
@MainActor
@Observable
final class OdysseyService {
    /// Bumped on every change so views recompute.
    private(set) var revision = 0

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let clock: DateProvider
    @ObservationIgnored let rules: OdysseyRules
    @ObservationIgnored private var cache: OdysseySnapshot?
    @ObservationIgnored private let logger = Logger(subsystem: "com.mobapptech.lumora", category: "Odyssey")

    init(context: ModelContext, clock: DateProvider, rules: OdysseyRules = .standard) {
        self.context = context
        self.clock = clock
        self.rules = rules
    }

    var snapshot: OdysseySnapshot {
        _ = revision
        if let cache { return cache }
        let s = computeSnapshot()
        cache = s
        return s
    }

    /// Called after any change (e.g. to refresh widgets).
    @ObservationIgnored var didChange: (() -> Void)?

    private func invalidate() {
        cache = nil
        revision &+= 1
        didChange?()
    }

    // MARK: Sync

    /// Brings worlds, the expedition and the horizon up to date with recorded
    /// focus. `sessionID` attributes new events to the session that caused them.
    func sync(after sessionID: UUID? = nil) {
        let facts = qualifyingFacts()
        let now = clock.now
        var changed = false

        // 0 · Two devices may each have set a course before syncing. One ship,
        // one journey: keep the earliest and call the others home, refunded
        // (the refund's ledger key makes this safe to repeat).
        let enRouteRaw = ExpeditionStatus.enRoute.rawValue
        let enRoute = (try? context.fetch(FetchDescriptor<Expedition>(
            predicate: #Predicate { $0.statusRaw == enRouteRaw }, sortBy: [SortDescriptor(\.startedAt)]))) ?? []
        if let kept = enRoute.first {
            for extra in enRoute.dropFirst() {
                extra.status = .recalled
                if extra.worldOrdinal != kept.worldOrdinal { world(ordinal: extra.worldOrdinal)?.status = .uncharted }
                if extra.stardustCost > 0 {
                    credit(key: "refund:\(extra.id.uuidString)", amount: extra.stardustCost, kind: .refund, note: "", date: now)
                }
                changed = true
            }
        }

        // 1 · Worlds emerge on the minute schedule.
        let total = facts.reduce(0) { $0 + $1.focusedMinutes }
        let shouldExist = rules.worldsEmerged(totalMinutes: total)
        let existing = Set(fetchWorlds().map(\.ordinal))
        if shouldExist > 0 {
            for ordinal in 1...shouldExist where !existing.contains(ordinal) {
                let crossing = crossingSession(facts, minutes: rules.emergenceThreshold(ordinal: ordinal))
                let place = rules.placement(ofWorld: ordinal)
                let world = OdysseyWorld(blueprint: WorldGenerator.blueprint(ordinal: ordinal), galaxyIndex: place.galaxy,
                                         emergedAt: crossing?.endedAt ?? now,
                                         sessionID: crossing?.id ?? sessionID)
                context.insert(world)
                changed = true
            }
        }

        // 2 · The ship arrives once enough focus has powered the journey.
        if let expedition = activeExpedition() {
            let after = facts.filter { $0.endedAt > expedition.startedAt }
            let progress = after.reduce(0) { $0 + $1.focusedMinutes }
            if progress >= expedition.requiredMinutes {
                let crossing = crossingSession(after, minutes: expedition.requiredMinutes)
                expedition.status = .arrived
                expedition.arrivedAt = crossing?.endedAt ?? now
                expedition.arrivalSessionID = crossing?.id ?? sessionID
                if let world = world(ordinal: expedition.worldOrdinal) {
                    world.status = .charted
                    world.visitedAt = expedition.arrivedAt
                }
                changed = true
            }
        }

        // 3 · The horizon is achieved (and rewarded once) or rests.
        if let goal = activeHorizon() {
            let progress = horizonProgress(goal, facts: facts)
            if progress >= goal.kind.targetUnits(goal.target) {
                goal.status = .achieved
                goal.achievedAt = now
                goal.achievedSessionID = sessionID
                credit(key: "horizon:\(goal.id.uuidString)", amount: goal.rewardStardust, kind: .horizonReward,
                       note: goal.kind.title, date: now)
                changed = true
            } else if let ends = goal.endsAt, now > ends {
                goal.status = .rested
                changed = true
            }
        }

        // 4 · The week's rare event is witnessed by the first session on its day.
        if witnessEvents(facts) { changed = true }

        if changed { save() }
        invalidate()
    }

    /// Credits each rare event seen since the Odyssey began. Idempotent.
    @discardableResult
    private func witnessEvents(_ facts: [SessionFacts]) -> Bool {
        let since = profile().createdAt
        var weeks: [DayKey: CosmicEvent] = [:]
        var changed = false
        for fact in facts where fact.endedAt >= since {
            let event = CosmicCalendar.event(inWeekOf: fact.endedAt, calendar: clock.calendar)
            guard fact.dayKey == event.day, weeks[event.day] == nil else { continue }
            weeks[event.day] = event
            if credit(key: Self.eventKey(event.day), amount: rules.eventReward, kind: .cosmicEvent,
                      note: event.kind.rawValue, date: fact.endedAt) {
                changed = true
            }
        }
        return changed
    }

    private static func eventKey(_ day: DayKey) -> String { "event:\(day.rawValue)" }

    /// What `sessionID` contributed, reconstructed from stored data.
    func summary(for sessionID: UUID) -> OdysseySessionSummary {
        let snap = snapshot
        var summary = OdysseySessionSummary()
        if let facts = qualifyingFacts().first(where: { $0.id == sessionID }) {
            summary.stardust = rules.stardust(for: facts)
        }
        let emergedOrdinals = Set(fetchWorlds().filter { $0.emergedSessionID == sessionID }.map(\.ordinal))
        summary.emerged = snap.worlds.filter { emergedOrdinals.contains($0.ordinal) }
        if let ignite = summary.emerged.first(where: { $0.slot == 0 && $0.galaxy > 0 }) {
            summary.galaxyIgnited = GalaxyCatalog.blueprint(ignite.galaxy)
        }
        let id: UUID? = sessionID
        if let arrived = (try? context.fetch(FetchDescriptor<Expedition>(predicate: #Predicate { $0.arrivalSessionID == id })))?.first {
            summary.arrival = expeditionState(arrived, snapshot: snap)
        } else if let active = snap.expedition {
            summary.expeditionProgress = active
        }
        if let goal = (try? context.fetch(FetchDescriptor<HorizonGoal>(predicate: #Predicate { $0.achievedSessionID == id })))?.first {
            summary.horizon = horizonState(goal, facts: qualifyingFacts())
        }
        if snap.rank.level > profile().celebratedRankLevel { summary.rankUp = snap.rank }
        if let facts = qualifyingFacts().first(where: { $0.id == sessionID }), facts.endedAt >= profile().createdAt {
            let event = CosmicCalendar.event(inWeekOf: facts.endedAt, calendar: clock.calendar)
            let firstThatDay = qualifyingFacts().first { $0.dayKey == event.day && $0.endedAt >= profile().createdAt }
            if facts.dayKey == event.day, firstThatDay?.id == sessionID { summary.event = event }
        }
        if summary.horizon != nil, let trail = ShipTrail.allCases.first(where: { $0.chainRequirement == snap.horizonChain }) {
            summary.chainTrail = trail
        }
        return summary
    }

    // MARK: Expeditions

    func plotCourse(to ordinal: Int) throws {
        guard activeExpedition() == nil else { throw OdysseyError.expeditionUnderway }
        guard let world = world(ordinal: ordinal), world.status == .uncharted else { throw OdysseyError.worldUnavailable }
        let blueprint = WorldGenerator.blueprint(ordinal: ordinal)
        let cost = rules.expeditionCost(for: blueprint)
        let balance = snapshot.balance
        guard balance >= cost else { throw OdysseyError.insufficientStardust(needed: cost - balance) }
        let now = clock.now
        let expedition = Expedition(worldOrdinal: ordinal, startedAt: now,
                                    requiredMinutes: rules.travelMinutes(for: blueprint), stardustCost: cost)
        context.insert(expedition)
        world.status = .enRoute
        if cost > 0 {
            credit(key: "expedition:\(expedition.id.uuidString)", amount: -cost, kind: .expedition, note: world.name, date: now)
        }
        save()
        invalidate()
        Telemetry.log(.coursePlotted(ordinal: ordinal, cost: cost))
    }

    /// Calls the ship home. Fuel is refunded in full; nothing is ever lost.
    func recallExpedition() {
        guard let expedition = activeExpedition() else { return }
        Telemetry.log(.expeditionRecalled)
        expedition.status = .recalled
        world(ordinal: expedition.worldOrdinal)?.status = .uncharted
        if expedition.stardustCost > 0 {
            credit(key: "refund:\(expedition.id.uuidString)", amount: expedition.stardustCost, kind: .refund,
                   note: "", date: clock.now)
        }
        save()
        invalidate()
    }

    func markArrivalSeen(_ id: UUID) {
        let target = id
        guard let e = (try? context.fetch(FetchDescriptor<Expedition>(predicate: #Predicate { $0.id == target })))?.first else { return }
        e.arrivalSeen = true
        save()
        invalidate()
    }

    // MARK: Terraforming

    @discardableResult
    func cultivate(_ ordinal: Int) throws -> WorldStage {
        guard let world = world(ordinal: ordinal), world.status == .charted else { throw OdysseyError.worldUnavailable }
        guard let next = world.worldStage.next else { throw OdysseyError.fullyTerraformed }
        let blueprint = WorldGenerator.blueprint(ordinal: ordinal)
        let cost = rules.cultivationCost(to: next, rarity: blueprint.rarity)
        let balance = snapshot.balance
        guard balance >= cost else { throw OdysseyError.insufficientStardust(needed: cost - balance) }
        let now = clock.now
        credit(key: "cultivate:\(ordinal):\(next.rawValue)", amount: -cost, kind: .cultivation, note: world.name, date: now)
        world.stage = next.rawValue
        world.lastCultivatedAt = now
        save()
        sync()
        return next
    }

    // MARK: Hangar

    func buy(_ part: ShipPart) throws {
        let snap = snapshot
        guard !snap.ownedParts.contains(part) else { return }
        if case let .trail(t) = part, let chain = t.chainRequirement { throw OdysseyError.chainRequired(chain) }
        if part.isPlus, !PlusAccess.isActive { throw OdysseyError.plusRequired }
        guard snap.rank.level >= rules.requiredRank(for: part) else {
            throw OdysseyError.rankTooLow(required: rules.requiredRank(for: part))
        }
        let price = rules.price(of: part)
        guard snap.balance >= price else { throw OdysseyError.insufficientStardust(needed: price - snap.balance) }
        credit(key: "part:\(part.key)", amount: -price, kind: .shipPart, note: part.title, date: clock.now)
        let p = profile()
        p.ownedPartKeys.append(part.key)
        equip(part, saving: false)
        save()
        invalidate()
        Telemetry.log(.shipPartBought(part: part.key, price: price, plus: part.isPlus))
    }

    /// Orbi+ started or ended: the loadout redraws with or without its finishes.
    func refreshPlus() { invalidate() }

    func equip(_ part: ShipPart, saving: Bool = true) {
        let p = profile()
        switch part {
        case let .hull(h): p.hullRaw = h.rawValue
        case let .paint(c): p.paintRaw = c.rawValue
        case let .trail(t): p.trailRaw = t.rawValue
        }
        if saving {
            save()
            invalidate()
        }
    }

    // MARK: Horizons

    func startHorizon(kind: HorizonKind, target: Int) {
        Telemetry.log(.horizonStarted(kind: kind.rawValue, target: target))
        if let current = activeHorizon() { current.status = .rested }
        let now = clock.now
        let ends = kind.isWeekly ? clock.calendar.date(byAdding: .day, value: 7, to: now) : nil
        context.insert(HorizonGoal(kind: kind, target: target, startedAt: now, endsAt: ends))
        save()
        sync()
    }

    func retireHorizon() {
        activeHorizon()?.status = .rested
        save()
        invalidate()
    }

    func markHorizonRewardSeen(_ id: UUID) {
        let target = id
        guard let g = (try? context.fetch(FetchDescriptor<HorizonGoal>(predicate: #Predicate { $0.id == target })))?.first else { return }
        g.rewardSeen = true
        save()
        invalidate()
    }

    /// A gentle next step after `kind`/`target`: a little further, never a leap.
    func suggestion(after kind: HorizonKind?, target: Int?) -> (kind: HorizonKind, target: Int) {
        guard let kind, let target else { return (.sessions, 5) }
        let presets = kind.presets
        if let next = presets.first(where: { $0 > target }) { return (kind, next) }
        return (kind, target)
    }

    // MARK: Profile & milestones

    func profile() -> OdysseyProfile {
        if let p = try? context.fetch(FetchDescriptor<OdysseyProfile>()).first { return p }
        let p = OdysseyProfile(createdAt: clock.now)
        context.insert(p)
        save()
        return p
    }

    func markIntroSeen() {
        profile().introSeen = true
        save()
        invalidate()
    }

    func markRankCelebrated() {
        profile().celebratedRankLevel = max(profile().celebratedRankLevel, snapshot.rank.level)
        save()
        invalidate()
    }

    // MARK: - Snapshot

    private func computeSnapshot() -> OdysseySnapshot {
        var s = OdysseySnapshot()
        let facts = qualifyingFacts()
        s.totalMinutes = facts.reduce(0) { $0 + $1.focusedMinutes }
        s.stardustEarned = facts.reduce(0) { $0 + rules.stardust(for: $1) }
        for entry in (try? context.fetch(FetchDescriptor<OdysseyLedgerEntry>())) ?? [] {
            if entry.amount >= 0 { s.stardustCredited += entry.amount } else { s.stardustSpent -= entry.amount }
        }

        s.worlds = fetchWorlds().sorted { $0.ordinal < $1.ordinal }.map(worldState)
        s.galaxyCount = rules.galaxiesIgnited(worlds: s.worlds.count)

        let expeditions = (try? context.fetch(FetchDescriptor<Expedition>(sortBy: [SortDescriptor(\.startedAt)]))) ?? []
        if let active = expeditions.last(where: { $0.status == .enRoute }) {
            s.expedition = expeditionState(active, worlds: s.worlds, facts: facts)
        }
        if let arrived = expeditions.last(where: { $0.status == .arrived && !$0.arrivalSeen }) {
            s.pendingArrival = expeditionState(arrived, worlds: s.worlds, facts: facts)
        }

        let goals = (try? context.fetch(FetchDescriptor<HorizonGoal>(sortBy: [SortDescriptor(\.startedAt)]))) ?? []
        s.horizonsAchieved = goals.filter { $0.status == .achieved }.count
        // A chain is horizons reached in a row; one that rests unfinished breaks it.
        for g in goals {
            switch g.status {
            case .achieved:
                s.horizonChain += 1
                s.bestHorizonChain = max(s.bestHorizonChain, s.horizonChain)
            case .rested: s.horizonChain = 0
            case .active: break
            }
        }
        if let active = goals.last(where: { $0.status == .active }) { s.horizon = horizonState(active, facts: facts) }
        if let unseen = goals.last(where: { $0.status == .achieved && !$0.rewardSeen }) {
            s.unseenHorizon = horizonState(unseen, facts: facts)
        }

        s.xp = rules.experience(focusMinutes: s.totalMinutes, chartedWorlds: s.chartedCount, stages: s.stagesTotal,
                                galaxies: s.galaxyCount, horizons: s.horizonsAchieved)
        s.rank = NavigatorRank.rank(forXP: s.xp)

        let nextOrdinal = s.worlds.count + 1
        let threshold = rules.emergenceThreshold(ordinal: nextOrdinal)
        let previous = nextOrdinal > 1 ? rules.emergenceThreshold(ordinal: nextOrdinal - 1) : 0
        let place = rules.placement(ofWorld: nextOrdinal)
        s.nextEmergence = EmergenceTeaser(
            blueprint: WorldGenerator.blueprint(ordinal: nextOrdinal),
            minutesRemaining: max(0, threshold - s.totalMinutes),
            fraction: Double(s.totalMinutes - previous) / Double(max(1, threshold - previous)),
            galaxy: place.galaxy, opensGalaxy: place.slot == 0 && place.galaxy > 0)

        let p = profile()
        // A Orbi+ finish rests while Orbi+ isn't active; it's still owned.
        s.loadout = PlusAccess.isActive ? p.loadout : p.loadout.withoutPlus
        s.ownedParts = p.ownedParts
        // Chain trails stay yours once earned, even if a later chain breaks.
        for t in ShipTrail.allCases {
            if let need = t.chainRequirement, s.bestHorizonChain >= need { s.ownedParts.insert(.trail(t)) }
        }
        s.introSeen = p.introSeen

        let event = CosmicCalendar.upcoming(from: clock.now, calendar: clock.calendar)
        s.nextEvent = event
        let eventKind = LedgerKind.cosmicEvent.rawValue
        let seen = (try? context.fetch(FetchDescriptor<OdysseyLedgerEntry>(
            predicate: #Predicate { $0.kindRaw == eventKind }, sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        s.nextEventWitnessed = seen.contains { $0.key == Self.eventKey(event.day) }
        s.witnessedEvents = seen.compactMap { entry in
            guard let kind = CosmicEventKind(rawValue: entry.note) else { return nil }
            let day = DayKey(rawValue: String(entry.key.dropFirst("event:".count)))
            return CosmicEvent(kind: kind, day: day, date: entry.date)
        }
        return s
    }

    private func worldState(_ w: OdysseyWorld) -> WorldState {
        var blueprint = WorldGenerator.blueprint(ordinal: w.ordinal)
        // Stored identity wins, so names never change under the user.
        if let stored = WorldArchetype(rawValue: w.archetypeRaw) { blueprint.archetype = stored }
        if !w.name.isEmpty { blueprint.name = w.name }
        let place = rules.placement(ofWorld: w.ordinal)
        return WorldState(ordinal: w.ordinal, blueprint: blueprint, galaxy: w.galaxyIndex, slot: place.slot,
                          status: w.status, stage: w.worldStage, emergedAt: w.emergedAt, visitedAt: w.visitedAt)
    }

    private func expeditionState(_ e: Expedition, snapshot: OdysseySnapshot) -> ExpeditionState? {
        expeditionState(e, worlds: snapshot.worlds, facts: qualifyingFacts())
    }

    private func expeditionState(_ e: Expedition, worlds: [WorldState], facts: [SessionFacts]) -> ExpeditionState? {
        guard let world = worlds.first(where: { $0.ordinal == e.worldOrdinal }) else { return nil }
        let progress = facts.filter { $0.endedAt > e.startedAt }.reduce(0) { $0 + $1.focusedMinutes }
        return ExpeditionState(id: e.id, world: world, startedAt: e.startedAt, requiredMinutes: e.requiredMinutes,
                               progressMinutes: min(progress, e.requiredMinutes), cost: e.stardustCost,
                               status: e.status, arrivedAt: e.arrivedAt, arrivalSeen: e.arrivalSeen)
    }

    private func horizonState(_ g: HorizonGoal, facts: [SessionFacts]) -> HorizonState {
        HorizonState(id: g.id, kind: g.kind, target: g.target, progressUnits: horizonProgress(g, facts: facts),
                     targetUnits: g.kind.targetUnits(g.target), endsAt: g.endsAt, reward: g.rewardStardust,
                     status: g.status, rewardSeen: g.rewardSeen)
    }

    private func horizonProgress(_ g: HorizonGoal, facts: [SessionFacts]) -> Int {
        let start = g.startedAt, end = g.endsAt ?? .distantFuture
        let since = facts.filter { $0.endedAt >= start && $0.endedAt <= end }
        switch g.kind {
        case .weeklyHours:
            return since.reduce(0) { $0 + $1.focusedMinutes }
        case .sessions:
            return since.count
        case .chartWorlds:
            let arrivedRaw = ExpeditionStatus.arrived.rawValue
            return (try? context.fetchCount(FetchDescriptor<Expedition>(
                predicate: #Predicate { $0.statusRaw == arrivedRaw && $0.startedAt >= start }))) ?? 0
        case .cultivate:
            let kindRaw = LedgerKind.cultivation.rawValue
            return (try? context.fetchCount(FetchDescriptor<OdysseyLedgerEntry>(
                predicate: #Predicate { $0.kindRaw == kindRaw && $0.date >= start }))) ?? 0
        case .rhythm:
            let days = Set(facts.map(\.dayKey))
            return RhythmCalculator.status(focusDays: days, today: DayKey(clock.now, calendar: clock.calendar),
                                           calendar: clock.calendar).days
        }
    }

    // MARK: - Storage helpers

    private func qualifyingFacts() -> [SessionFacts] {
        ((try? context.fetch(FetchDescriptor<FocusSession>(sortBy: [SortDescriptor(\.endedAt)]))) ?? [])
            .map(SessionFacts.init).filter(\.qualifies)
    }

    /// The session at which cumulative focus first reached `minutes`.
    private func crossingSession(_ facts: [SessionFacts], minutes: Int) -> SessionFacts? {
        var total = 0
        for f in facts {
            total += f.focusedMinutes
            if total >= minutes { return f }
        }
        return nil
    }

    private func fetchWorlds() -> [OdysseyWorld] {
        (try? context.fetch(FetchDescriptor<OdysseyWorld>())) ?? []
    }

    private func world(ordinal: Int) -> OdysseyWorld? {
        let o = ordinal
        var d = FetchDescriptor<OdysseyWorld>(predicate: #Predicate { $0.ordinal == o })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    private func activeExpedition() -> Expedition? {
        let raw = ExpeditionStatus.enRoute.rawValue
        var d = FetchDescriptor<Expedition>(predicate: #Predicate { $0.statusRaw == raw })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    private func activeHorizon() -> HorizonGoal? {
        let raw = HorizonStatus.active.rawValue
        var d = FetchDescriptor<HorizonGoal>(predicate: #Predicate { $0.statusRaw == raw })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// Idempotent ledger write: an existing key is never charged twice.
    /// Returns whether a new entry was written.
    @discardableResult
    private func credit(key: String, amount: Int, kind: LedgerKind, note: String, date: Date) -> Bool {
        let k = key
        var d = FetchDescriptor<OdysseyLedgerEntry>(predicate: #Predicate { $0.key == k })
        d.fetchLimit = 1
        guard ((try? context.fetchCount(d)) ?? 0) == 0 else { return false }
        context.insert(OdysseyLedgerEntry(key: key, date: date, amount: amount, kind: kind, note: note))
        return true
    }

    private func save() {
        do {
            if context.hasChanges { try context.save() }
        } catch {
            logger.error("Odyssey save failed: \(error.localizedDescription)")
        }
    }
}
