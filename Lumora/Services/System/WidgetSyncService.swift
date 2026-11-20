import Foundation
import SwiftData
import WidgetKit

/// Publishes the minimal `WidgetSnapshot` to the App Group and asks WidgetKit
/// to reload. Called after rewards, on launch and on day changes.
@MainActor
final class WidgetSyncService {
    private let context: ModelContext
    private let clock: DateProvider
    private let rules: RewardRules

    init(context: ModelContext, clock: DateProvider, rules: RewardRules = .standard) {
        self.context = context
        self.clock = clock
        self.rules = rules
    }

    /// Supplies the Odyssey journey for the widget (set by the app model).
    var odysseyInfo: (() -> (world: String?, fraction: Double?, stardust: Int))?
    /// Supplies today's and tomorrow's plan blocks (set by the app model).
    var planBlocks: (() -> [PlanBlock])?
    /// Supplies the habits (set by the app model).
    var habits: (() -> [HabitWidgetItem])?

    func publish(goalMinutes: Int) {
        let snapshot = makeSnapshot(goalMinutes: goalMinutes)
        guard snapshot != WidgetSnapshot.load() else { return }
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func makeSnapshot(goalMinutes: Int) -> WidgetSnapshot {
        let calendar = clock.calendar
        let now = clock.now
        let today = DayKey(now, calendar: calendar)
        let sessions = ((try? context.fetch(FetchDescriptor<FocusSession>())) ?? []).map(SessionFacts.init)
        let stats = ProgressStats.compute(sessions: sessions, goalMinutes: goalMinutes, today: today, calendar: calendar)
        let objects = ((try? context.fetch(FetchDescriptor<CelestialObject>(sortBy: [SortDescriptor(\.bornAt, order: .reverse)]))) ?? [])

        let drawable = objects.filter { [.star, .seed, .planet].contains($0.kind) }.prefix(60)
        var mini: [WidgetSnapshot.MiniStar] = []
        if let minX = drawable.map(\.x).min(), let maxX = drawable.map(\.x).max(),
           let minY = drawable.map(\.y).min(), let maxY = drawable.map(\.y).max() {
            let span = max(maxX - minX, maxY - minY, 300)
            let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
            mini = drawable.map { o in
                WidgetSnapshot.MiniStar(x: 0.5 + (o.x - cx) / span * 0.82, y: 0.5 + (o.y - cy) / span * 0.82,
                                        categoryRaw: o.hueRaw, size: o.kind == .planet ? 2.4 : o.scale,
                                        isPlanet: o.kind == .planet)
            }
        }
        let next = rules.nextPlanet(after: stats.qualifyingSessions)
        var snapshot = WidgetSnapshot(
            generatedAt: now, dayKey: today.rawValue, todayMinutes: stats.todayMinutes,
            goalMinutes: goalMinutes, rhythmDays: stats.currentRhythm.days,
            totalStars: objects.filter { $0.kind == .star }.count,
            planets: objects.filter { $0.kind == .planet }.count,
            constellations: objects.filter { $0.kind == .constellation }.count,
            stars: mini, nextWorldName: next?.name,
            sessionsToNextWorld: next.map { $0.sessions - stats.qualifyingSessions })
        if let info = odysseyInfo?() {
            snapshot.expeditionWorld = info.world
            snapshot.expeditionFraction = info.fraction
            snapshot.stardust = info.stardust
        }
        snapshot.plan = planBlocks?()
        snapshot.habits = habits?()
        return snapshot
    }
}
