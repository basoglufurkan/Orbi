import Foundation

/// "Rhythm, not streak-shaming": consecutive focus days where one missed day
/// per rolling week is a free rest day. A second miss within a week pauses
/// the rhythm (the counter restarts); no object is ever removed.
struct RhythmStatus: Equatable, Sendable {
    /// Calendar days in the current rhythm (rest days included).
    var days: Int
    /// No focus yet today, but the rhythm is still alive.
    var pendingToday: Bool
    /// Yesterday (or earlier this week) used the free rest day.
    var restUsedRecently: Bool
    /// The user had a rhythm before and it has lapsed.
    var isPaused: Bool
    /// First day of the current rhythm.
    var startDay: DayKey?
}

enum RhythmCalculator {
    static let restWindowDays = 7

    /// Current rhythm as of `today`.
    static func status(focusDays: Set<DayKey>, today: DayKey, calendar: Calendar = .current) -> RhythmStatus {
        guard let first = focusDays.min(), first <= today else {
            return RhythmStatus(days: 0, pendingToday: true, restUsedRecently: false, isPaused: false, startDay: nil)
        }
        let walk = forwardWalk(focusDays: focusDays, from: first, through: today.adding(days: -1, calendar: calendar), calendar: calendar)
        let focusedToday = focusDays.contains(today)

        if focusedToday {
            let days = walk.current > 0 ? walk.current + walk.pendingRest + 1 : 1
            let start = today.adding(days: -(days - 1), calendar: calendar)
            return RhythmStatus(days: days, pendingToday: false, restUsedRecently: walk.restRecently(today: walk.dayIndex(today)),
                                isPaused: false, startDay: start)
        }
        // Today is not over: it is neither a focus day nor a miss yet.
        let days = walk.current > 0 ? walk.current + walk.pendingRest : 0
        let start = days > 0 ? today.adding(days: -days, calendar: calendar) : nil
        return RhythmStatus(days: days, pendingToday: true,
                            restUsedRecently: walk.restRecently(today: walk.dayIndex(today)),
                            isPaused: days == 0, startDay: start)
    }

    /// Longest rhythm ever achieved (counted through its last focus day).
    static func longest(focusDays: Set<DayKey>, calendar: Calendar = .current) -> Int {
        guard let first = focusDays.min(), let last = focusDays.max() else { return 0 }
        return forwardWalk(focusDays: focusDays, from: first, through: last, calendar: calendar).best
    }

    // MARK: - Walk

    struct Walk {
        var current = 0
        var pendingRest = 0
        var best = 0
        var lastRestIndex: Int?
        var origin: Date
        var calendar: Calendar

        func dayIndex(_ key: DayKey) -> Int {
            guard let d = key.startDate(calendar: calendar) else { return 0 }
            return calendar.dateComponents([.day], from: origin, to: d).day ?? 0
        }

        func restRecently(today: Int) -> Bool {
            guard current > 0, let r = lastRestIndex else { return false }
            return today - r < RhythmCalculator.restWindowDays
        }
    }

    static func forwardWalk(focusDays: Set<DayKey>, from first: DayKey, through last: DayKey, calendar: Calendar) -> Walk {
        let origin = first.startDate(calendar: calendar) ?? .distantPast
        var walk = Walk(origin: origin, calendar: calendar)
        guard first <= last else { return walk }
        var day = first
        var index = 0
        while day <= last, index < 36_500 {
            if focusDays.contains(day) {
                walk.current = walk.current > 0 ? walk.current + walk.pendingRest + 1 : 1
                walk.pendingRest = 0
                walk.best = max(walk.best, walk.current)
            } else if walk.current > 0, walk.pendingRest == 0,
                      walk.lastRestIndex.map({ index - $0 >= restWindowDays }) ?? true {
                walk.lastRestIndex = index
                walk.pendingRest = 1
            } else {
                walk.current = 0
                walk.pendingRest = 0
                walk.lastRestIndex = nil
            }
            day = day.adding(days: 1, calendar: calendar)
            index += 1
        }
        return walk
    }
}
