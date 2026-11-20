import Foundation

/// Turns a newly recorded session into the celestial objects it earns.
///
/// Pure and deterministic: output depends only on the session, the session
/// history and the objects that already exist. `RewardService` persists the
/// drafts; `replay(history:)` regenerates a whole universe from history and
/// must produce the same result (verified by tests).
struct ProgressionEngine: Sendable {
    var rules: RewardRules = .standard
    var calendar: Calendar = .current

    /// Rewards for `session`. `history` must contain every stored session
    /// (including `session`), ordered by `endedAt`.
    func rewards(for session: SessionFacts, history: [SessionFacts], existing: [CelestialSnapshot]) -> [CelestialDraft] {
        guard session.qualifies else { return [] }
        var objects = existing
        var drafts: [CelestialDraft] = []
        let existingKeys = Set(existing.map(\.rewardKey))

        func add(_ draft: CelestialDraft) {
            guard !existingKeys.contains(draft.rewardKey),
                  !drafts.contains(where: { $0.rewardKey == draft.rewardKey }) else { return }
            drafts.append(draft)
            objects.append(CelestialSnapshot(draft: draft))
        }

        let qualifying = history.filter(\.qualifies)
        guard let sessionIndex = qualifying.firstIndex(where: { $0.id == session.id }) else { return [] }
        let prior = Array(qualifying[..<sessionIndex])
        let countAfter = sessionIndex + 1
        let seed = StableHash.fnv1a(session.id.uuidString)

        // 1 · The star.
        let stars = objects.filter { $0.kind == .star }
        let ordinal = (stars.map(\.ordinal).max() ?? 0) + 1
        let region = UniverseRegion.newestOpen(forQualifyingSessions: prior.count)
        let sameDay = stars.filter { $0.dayKey == session.dayKey }.sorted { $0.ordinal < $1.ordinal }
        let candidate: WorldPoint
        if let last = sameDay.last {
            candidate = UniverseLayout.chainStep(from: last.position, indexInDay: sameDay.count, seed: seed)
        } else {
            let dayRegion = region
            let daysInRegion = Set(stars.filter { $0.region == dayRegion }.map(\.dayKey)).count
            let gateway = dayRegion == .homeCluster ? nil
                : UniverseLayout.gateway(to: dayRegion, beyond: stars.filter { $0.region != dayRegion }.map(\.position))
            let anchor = UniverseLayout.dayAnchor(region: dayRegion, dayIndex: daysInRegion,
                                                  seed: StableHash.fnv1a(session.dayKey.rawValue), gateway: gateway)
            candidate = UniverseLayout.jitter(anchor, seed: seed, amount: 14)
        }
        let starRegion = sameDay.last?.region ?? region
        let position = UniverseLayout.placeFree(candidate, clearance: UniverseLayout.starClearance, occupied: objects)
        add(CelestialDraft(kind: .star, rewardKey: "star:\(session.id.uuidString)", seed: seed,
                           bornAt: session.endedAt, position: position,
                           scale: rules.starScale(focusedSeconds: session.focusedSeconds, outcome: session.outcome),
                           hue: session.category.rawValue,
                           name: session.intention.isEmpty ? session.category.displayName : session.intention,
                           region: starRegion, ordinal: ordinal, dayKey: session.dayKey,
                           focusedMinutes: session.focusedMinutes, sourceSessionID: session.id))

        // 2 · Constellation: every N same-day stars connect.
        let dayStars = objects.filter { $0.kind == .star && $0.dayKey == session.dayKey }.sorted { $0.ordinal < $1.ordinal }
        let perConstellation = max(2, rules.starsPerConstellation)
        if dayStars.count % perConstellation == 0 {
            let group = Array(dayStars.suffix(perConstellation))
            let index = dayStars.count / perConstellation
            let cx = group.map(\.position.x).reduce(0, +) / Double(group.count)
            let cy = group.map(\.position.y).reduce(0, +) / Double(group.count)
            let count = objects.filter { $0.kind == .constellation }.count
            add(CelestialDraft(kind: .constellation, rewardKey: "constellation:\(session.dayKey.rawValue):\(index)",
                               seed: seed ^ 0xC0_11, bornAt: session.endedAt, position: WorldPoint(x: cx, y: cy),
                               scale: 1, hue: session.category.rawValue,
                               name: Self.constellationName(day: session.dayKey, intentions: [session.intention], calendar: calendar),
                               region: starRegion, ordinal: count + 1, dayKey: session.dayKey,
                               focusedMinutes: 0, sourceSessionID: session.id,
                               linkedOrdinals: group.map(\.ordinal)))
        }

        // 3 · Planets at session milestones.
        if let planetIndex = rules.planetMilestones.firstIndex(of: countAfter) {
            let anchor = UniverseLayout.planetAnchor(index: planetIndex)
            let pos = UniverseLayout.placeFree(anchor, clearance: 70, occupied: objects.filter { $0.kind != .star })
            add(CelestialDraft(kind: .planet, rewardKey: "planet:\(countAfter)", seed: seed ^ 0x9_1A_E7,
                               bornAt: session.endedAt, position: pos, scale: 1,
                               hue: Self.planetPalette(index: planetIndex),
                               name: rules.planetName(index: planetIndex), region: region,
                               ordinal: planetIndex + 1, dayKey: session.dayKey, focusedMinutes: 0,
                               sourceSessionID: session.id,
                               sourceAchievementID: "world.\(planetIndex + 1)"))
        }

        // 4 · Moons orbit the newest planet.
        if let moonIndex = rules.moonMilestones.firstIndex(of: countAfter),
           let planet = objects.filter({ $0.kind == .planet }).max(by: { $0.ordinal < $1.ordinal }) {
            var rng = SeededRandom(seed: seed ^ 0x300)
            let candidate = planet.position.offset(angle: rng.range(0, 2 * .pi), distance: 105)
            let pos = UniverseLayout.placeFree(candidate, clearance: 30, occupied: objects)
            add(CelestialDraft(kind: .moon, rewardKey: "moon:\(countAfter)", seed: seed ^ 0x300,
                               bornAt: session.endedAt, position: pos, scale: 1, hue: "moon",
                               name: moonIndex < rules.moonNames.count ? rules.moonNames[moonIndex] : "Moon \(moonIndex + 1)",
                               region: planet.region, ordinal: moonIndex + 1, dayKey: session.dayKey,
                               focusedMinutes: 0, sourceSessionID: session.id,
                               linkedOrdinals: [planet.ordinal]))
        }

        // 5 · Nebula for each full week of rhythm.
        let focusDays = Set(qualifying[...sessionIndex].map(\.dayKey))
        let rhythm = RhythmCalculator.status(focusDays: focusDays, today: session.dayKey, calendar: calendar)
        if rhythm.days >= rules.nebulaRhythmDays, let start = rhythm.startDay {
            // Keyed by rhythm start + completed weeks, so rest days that skip
            // past an exact multiple of 7 still award, and repeats dedupe.
            let count = objects.filter { $0.kind == .nebula }.count
            let regionForNebula: UniverseRegion = count == 0 ? .roseVeil : region
            var rng = SeededRandom(seed: seed ^ 0x4E_B0)
            let pos = regionForNebula.center.offset(angle: rng.range(0, 2 * .pi), distance: rng.range(0, 160))
            add(CelestialDraft(kind: .nebula, rewardKey: "nebula:\(start.rawValue):\(rhythm.days / rules.nebulaRhythmDays)",
                               seed: seed ^ 0x4E_B0, bornAt: session.endedAt, position: pos,
                               scale: 1 + 0.15 * Double(min(count, 4)),
                               hue: count == 0 ? "roseVeil" : regionForNebula.rawValue,
                               name: count < rules.nebulaNames.count ? rules.nebulaNames[count] : "Nebula \(count + 1)",
                               region: regionForNebula, ordinal: count + 1, dayKey: session.dayKey,
                               focusedMinutes: 0, sourceSessionID: session.id,
                               sourceAchievementID: count == 0 ? "rhythm.7" : nil))
        }

        // 6 · Comets mark focus-hour milestones.
        let hoursBefore = prior.reduce(0) { $0 + $1.focusedSeconds } / 3600
        let hoursAfter = (prior.reduce(0) { $0 + $1.focusedSeconds } + session.focusedSeconds) / 3600
        for milestone in rules.cometHourMilestones where hoursBefore < milestone && hoursAfter >= milestone {
            var rng = SeededRandom(seed: seed ^ UInt64(milestone))
            let candidate = position.offset(angle: rng.range(0, 2 * .pi), distance: rng.range(140, 260))
            let pos = UniverseLayout.placeFree(candidate, clearance: 40, occupied: objects)
            add(CelestialDraft(kind: .comet, rewardKey: "comet:hours:\(milestone)", seed: seed ^ UInt64(milestone),
                               bornAt: session.endedAt, position: pos, scale: 1, hue: "gold",
                               name: String(localized: "\(milestone)-hour comet"), region: starRegion,
                               ordinal: milestone, dayKey: session.dayKey, focusedMinutes: 0,
                               sourceSessionID: session.id))
        }
        return drafts
    }

    /// Regenerates every object from history alone (plus the seed star).
    func replay(history: [SessionFacts], seedStar: CelestialSnapshot) -> [CelestialDraft] {
        var existing = [seedStar]
        var all: [CelestialDraft] = []
        let ordered = history.sorted { $0.endedAt < $1.endedAt }
        for (i, s) in ordered.enumerated() where s.qualifies {
            let drafts = rewards(for: s, history: Array(ordered[...i]), existing: existing)
            all += drafts
            existing += drafts.map { CelestialSnapshot(draft: $0) }
        }
        return all
    }

    static func seedStarDraft(createdAt: Date, calendar: Calendar = .current) -> CelestialDraft {
        CelestialDraft(kind: .seed, rewardKey: "seed", seed: 0x5EED, bornAt: createdAt,
                       position: UniverseLayout.seedStarPosition, scale: 1, hue: "seed",
                       name: String(localized: "First Light"), region: .homeCluster, ordinal: 0,
                       dayKey: DayKey(createdAt, calendar: calendar), focusedMinutes: 0)
    }

    static func planetPalette(index: Int) -> String {
        ["rose", "aqua", "amber", "violet", "jade"][index % 5]
    }

    static func constellationName(day: DayKey, intentions: [String], calendar: Calendar) -> String {
        let date = day.startDate(calendar: calendar) ?? .now
        let dayName = date.formatted(.dateTime.month(.wide).day())
        if let intention = intentions.last(where: { !$0.isEmpty }) {
            return "\(dayName) — \(intention)"
        }
        return dayName
    }
}
