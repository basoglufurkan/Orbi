import Foundation

/// Aggregates derived purely from stored sessions. Achievements and insights
/// read these, so every unlock is backed by verifiable data.
struct ProgressStats: Equatable, Sendable {
    var qualifyingSessions = 0
    var completedSessions = 0
    var totalFocusSeconds = 0
    var longestSessionSeconds = 0
    var longestSession: SessionFacts?
    var longestCompletedSeconds = 0
    var maxQualifyingSessionsInDay = 0
    var goalDays = 0
    var bestDaySeconds = 0
    var bestDay: DayKey?
    var currentRhythm = RhythmStatus(days: 0, pendingToday: true, restUsedRecently: false, isPaused: false, startDay: nil)
    var longestRhythm = 0
    var todaySeconds = 0
    var todayQualifyingSessions = 0
    var focusDays: Set<DayKey> = []
    var secondsByDay: [DayKey: Int] = [:]

    var totalFocusHours: Double { Double(totalFocusSeconds) / 3600 }
    var todayMinutes: Int { todaySeconds / 60 }

    static func compute(sessions: [SessionFacts], goalMinutes: Int, today: DayKey,
                        calendar: Calendar = .current) -> ProgressStats {
        var stats = ProgressStats()
        var countByDay: [DayKey: Int] = [:]

        for s in sessions where s.qualifies {
            stats.qualifyingSessions += 1
            if s.outcome == .completed {
                stats.completedSessions += 1
                stats.longestCompletedSeconds = max(stats.longestCompletedSeconds, s.focusedSeconds)
            }
            stats.totalFocusSeconds += s.focusedSeconds
            if s.focusedSeconds > stats.longestSessionSeconds {
                stats.longestSessionSeconds = s.focusedSeconds
                stats.longestSession = s
            }
            stats.secondsByDay[s.dayKey, default: 0] += s.focusedSeconds
            countByDay[s.dayKey, default: 0] += 1
            stats.focusDays.insert(s.dayKey)
        }

        stats.maxQualifyingSessionsInDay = countByDay.values.max() ?? 0
        let goalSeconds = max(1, goalMinutes) * 60
        stats.goalDays = stats.secondsByDay.values.filter { $0 >= goalSeconds }.count
        if let best = stats.secondsByDay.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }) {
            stats.bestDay = best.key
            stats.bestDaySeconds = best.value
        }
        stats.todaySeconds = stats.secondsByDay[today] ?? 0
        stats.todayQualifyingSessions = countByDay[today] ?? 0
        stats.currentRhythm = RhythmCalculator.status(focusDays: stats.focusDays, today: today, calendar: calendar)
        stats.longestRhythm = max(RhythmCalculator.longest(focusDays: stats.focusDays, calendar: calendar),
                                  stats.currentRhythm.days)
        return stats
    }
}
