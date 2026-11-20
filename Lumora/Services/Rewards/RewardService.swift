import Foundation
import SwiftData
import os

enum RewardError: LocalizedError {
    case persistenceFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case let .persistenceFailed(error):
            String(localized: "Your session couldn't be saved: \(error.localizedDescription)")
        }
    }
}

/// Records finished focus segments and everything they earn, atomically and
/// exactly once per segment identifier.
@MainActor
final class RewardService: FocusResultRecording {
    private let context: ModelContext
    private let rules: RewardRules
    private let clock: DateProvider
    private let goalMinutes: () -> Int
    private let logger = Logger(subsystem: "com.mobapptech.lumora", category: "Rewards")
    /// Called after a reward is committed (widgets, analytics, …).
    var didCommit: ((SessionReward) -> Void)?

    init(context: ModelContext, rules: RewardRules = .standard, clock: DateProvider,
         goalMinutes: @escaping () -> Int) {
        self.context = context
        self.rules = rules
        self.clock = clock
        self.goalMinutes = goalMinutes
    }

    private var engine: ProgressionEngine { ProgressionEngine(rules: rules, calendar: clock.calendar) }

    func record(_ result: FocusResult) throws -> SessionReward {
        // Idempotency: the segment ID is the session ID.
        if let existing = fetchSession(id: result.segmentID), let reward = makeReward(for: existing) {
            logger.info("Duplicate completion ignored for \(result.segmentID)")
            return reward
        }

        let calendar = clock.calendar
        let outcome = rules.outcome(for: result)
        let day = DayKey(result.endedAt, calendar: calendar)
        let session = FocusSession(
            id: result.segmentID, startedAt: result.startedAt, endedAt: result.endedAt,
            plannedSeconds: result.plannedSeconds, focusedSeconds: result.focusedSeconds,
            pausedSeconds: result.pausedSeconds, pauseCount: result.pauseCount,
            category: result.configuration.category,
            intention: result.configuration.intention.trimmingCharacters(in: .whitespacesAndNewlines),
            outcome: outcome, dayKey: day, timeZoneID: calendar.timeZone.identifier)

        // The context is shared: settle anyone else's edits first, so a
        // rollback below can only undo this transaction, never theirs.
        if context.hasChanges { try? context.save() }
        do {
            let previous = try context.fetch(FetchDescriptor<FocusSession>(sortBy: [SortDescriptor(\.endedAt)]))
            context.insert(session)
            session.task = linkTask(for: result.configuration, now: result.endedAt)

            let history = (previous.map(SessionFacts.init) + [SessionFacts(session)]).sorted { $0.endedAt < $1.endedAt }
            var objects = try context.fetch(FetchDescriptor<CelestialObject>()).map(CelestialSnapshot.init)

            if outcome.earnsStar {
                let drafts = engine.rewards(for: SessionFacts(session), history: history, existing: objects)
                for draft in drafts {
                    context.insert(CelestialObject(draft: draft))
                    objects.append(CelestialSnapshot(draft: draft))
                    if draft.kind == .star { session.starNumber = draft.ordinal }
                }
            }

            let stats = ProgressStats.compute(sessions: history, goalMinutes: goalMinutes(), today: day, calendar: calendar)
            let unlocked = Set(try context.fetch(FetchDescriptor<AchievementUnlock>()).map(\.achievementID))
            for definition in AchievementEngine.newlyUnlocked(stats: stats, alreadyUnlocked: unlocked) {
                context.insert(AchievementUnlock(achievementID: definition.id, unlockedAt: result.endedAt,
                                                 sourceSessionID: session.id))
            }

            updateProgress(stats: stats, objects: objects)
            try context.save()
        } catch {
            context.rollback()
            logger.error("Reward transaction failed: \(error.localizedDescription)")
            throw RewardError.persistenceFailed(underlying: error)
        }

        guard let reward = makeReward(for: session) else {
            throw RewardError.persistenceFailed(underlying: CocoaError(.coderValueNotFound))
        }
        didCommit?(reward)
        return reward
    }

    /// The sky is kept per device and derived from history. When history came
    /// from another device (or this device's sky store is new), draw the whole
    /// sky again from day 1 — the same sessions always give the same sky.
    /// Returns true if it was redrawn.
    @discardableResult
    func rebuildUniverseIfNeeded(createdAt: Date, force: Bool = false) -> Bool {
        let sessions = (try? context.fetch(FetchDescriptor<FocusSession>(sortBy: [SortDescriptor(\.endedAt)]))) ?? []
        let objects = (try? context.fetch(FetchDescriptor<CelestialObject>())) ?? []
        let history = sessions.map(SessionFacts.init)
        let expected = Set(history.filter(\.qualifies).map(\.id))
        let drawn = Set(objects.filter { $0.kind == .star }.compactMap(\.sourceSessionID))
        guard force || expected != drawn else { return false }
        if context.hasChanges { try? context.save() }   // see record(_:)

        let calendar = clock.calendar
        let seedDraft = ProgressionEngine.seedStarDraft(createdAt: createdAt, calendar: calendar)
        let seed = objects.first { $0.kind == .seed } ?? CelestialObject(draft: seedDraft)
        if seed.modelContext == nil { context.insert(seed) }
        for object in objects where object !== seed { context.delete(object) }

        var snapshots = [CelestialSnapshot(seed)]
        let byID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for draft in engine.replay(history: history, seedStar: snapshots[0]) {
            context.insert(CelestialObject(draft: draft))
            snapshots.append(CelestialSnapshot(draft: draft))
            if draft.kind == .star, let id = draft.sourceSessionID { byID[id]?.starNumber = draft.ordinal }
        }
        let today = DayKey(clock.now, calendar: calendar)
        let stats = ProgressStats.compute(sessions: history, goalMinutes: goalMinutes(), today: today, calendar: calendar)
        updateProgress(stats: stats, objects: snapshots)
        do {
            try context.save()
        } catch {
            context.rollback()
            logger.error("Rebuilding the sky failed: \(error.localizedDescription)")
            return false
        }
        logger.info("Sky redrawn from \(expected.count) sessions")
        return true
    }

    func reward(for sessionID: UUID) -> SessionReward? {
        fetchSession(id: sessionID).flatMap(makeReward(for:))
    }

    // MARK: - Private

    private func fetchSession(id: UUID) -> FocusSession? {
        var descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func linkTask(for configuration: FocusConfiguration, now: Date) -> FocusTask? {
        let title = configuration.intention.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = configuration.taskID {
            var d = FetchDescriptor<FocusTask>(predicate: #Predicate { $0.id == id })
            d.fetchLimit = 1
            if let task = try? context.fetch(d).first {
                task.lastUsedAt = now
                return task
            }
        }
        guard !title.isEmpty else { return nil }
        let categoryRaw = configuration.category.rawValue
        var d = FetchDescriptor<FocusTask>(predicate: #Predicate { $0.title == title && $0.categoryRaw == categoryRaw })
        d.fetchLimit = 1
        if let task = try? context.fetch(d).first {
            task.lastUsedAt = now
            return task
        }
        let task = FocusTask(title: title, category: configuration.category, now: now)
        context.insert(task)
        return task
    }

    private func updateProgress(stats: ProgressStats, objects: [CelestialSnapshot]) {
        let progress: UniverseProgress
        if let existing = try? context.fetch(FetchDescriptor<UniverseProgress>()).first {
            progress = existing
        } else {
            progress = UniverseProgress(createdAt: clock.now)
            context.insert(progress)
        }
        let stars = objects.filter { $0.kind == .star }.count
        progress.starCount = stars
        progress.constellationCount = objects.filter { $0.kind == .constellation }.count
        progress.planetCount = objects.filter { $0.kind == .planet }.count
        progress.qualifyingSessionCount = stats.qualifyingSessions
        progress.totalFocusSeconds = stats.totalFocusSeconds
        progress.ambientLight = min(1, Double(stars) * rules.ambientLightPerStar)
        progress.updatedAt = clock.now
    }

    private func makeReward(for session: FocusSession) -> SessionReward? {
        let id: UUID? = session.id
        let objects = (try? context.fetch(FetchDescriptor<CelestialObject>(predicate: #Predicate { $0.sourceSessionID == id }))) ?? []
        let star = objects.first { $0.kind == .star }.map(CelestialSnapshot.init)
        let others = objects.filter { $0.kind != .star }.map(CelestialSnapshot.init).sorted { $0.kind.rawValue < $1.kind.rawValue }

        let sessionID = session.id
        let unlocks = (try? context.fetch(FetchDescriptor<AchievementUnlock>(predicate: #Predicate { $0.sourceSessionID == sessionID }))) ?? []
        let achievements = unlocks.compactMap(\.definition).sorted { $0.number < $1.number }

        let dayRaw = session.dayKeyRaw
        let starKind = CelestialKind.star.rawValue
        let todayStars = ((try? context.fetch(FetchDescriptor<CelestialObject>(
            predicate: #Predicate { $0.dayKeyRaw == dayRaw && $0.kindRaw == starKind }))) ?? [])
            .map(CelestialSnapshot.init).sorted { $0.ordinal < $1.ordinal }

        let daySessions = (try? context.fetch(FetchDescriptor<FocusSession>(predicate: #Predicate { $0.dayKeyRaw == dayRaw }))) ?? []
        let todaySeconds = daySessions.filter(\.qualifies).reduce(0) { $0 + $1.focusedSeconds }
        let ownSeconds = session.qualifies ? session.focusedSeconds : 0
        // Qualifying sessions up to and including this one ("Session 120").
        let tooShortRaw = SessionOutcome.tooShort.rawValue
        let endedAt = session.endedAt
        let countUpToHere = (try? context.fetchCount(FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.endedAt <= endedAt && $0.outcomeRaw != tooShortRaw }))) ?? 0

        return SessionReward(
            sessionID: session.id, outcome: session.outcome, category: session.category,
            intention: session.intention, focusedMinutes: session.focusedMinutes,
            plannedMinutes: session.plannedSeconds / 60, endedAt: session.endedAt,
            star: star, newObjects: others, newAchievements: achievements,
            todayMinutesBefore: (todaySeconds - ownSeconds) / 60, todayMinutes: todaySeconds / 60,
            goalMinutes: goalMinutes(), todayStars: todayStars,
            totalQualifyingSessions: countUpToHere, starsPerConstellation: rules.starsPerConstellation,
            task: session.task.flatMap(taskSnapshot(for:)))
    }

    /// Progress is derived from the task's linked sessions; only tasks from
    /// the task list are shown, not implicit intentions.
    private func taskSnapshot(for task: FocusTask) -> TaskSnapshot? {
        guard task.isPlanned else { return nil }
        return TaskSnapshot(id: task.id, title: task.title, category: task.category, progress: task.progress, isCompleted: task.isCompleted)
    }
}
