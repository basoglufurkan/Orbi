import Foundation

/// "Your year in light": the year's focus told as a handful of facts, for
/// the year-in-review story. Pure, so it can be tested and computed anytime.
struct YearReview: Equatable, Sendable {
    struct Day: Equatable, Sendable {
        var date: Date
        var minutes: Int
    }

    struct Session: Equatable, Sendable {
        var date: Date
        var minutes: Int
        var category: FocusCategory
    }

    struct Share: Equatable, Sendable {
        var category: FocusCategory
        var fraction: Double
    }

    var year: Int
    var totalMinutes = 0
    var sessions = 0
    var activeDays = 0
    var brightestDay: Day?
    var longestSession: Session?
    var topCategory: Share?
    /// Most focus days in a row.
    var longestRun = 0
    var worldsCharted = 0
    var firstWorldName: String?
    var rareEvents = 0
    var rank: NavigatorRank = NavigatorRank.all[0]
    var horizons = 0

    var hasContent: Bool { sessions > 0 }
    var hours: Double { Double(totalMinutes) / 60 }

    static func make(year: Int, facts: [SessionFacts], calendar: Calendar, worlds: [WorldState] = [],
                     events: [CosmicEvent] = [], rank: NavigatorRank = NavigatorRank.all[0], horizons: Int = 0) -> YearReview {
        var review = YearReview(year: year, rank: rank, horizons: horizons)
        let inYear = facts.filter { $0.qualifies && calendar.component(.year, from: $0.endedAt) == year }
        guard !inYear.isEmpty else { return review }

        review.sessions = inYear.count
        review.totalMinutes = inYear.reduce(0) { $0 + $1.focusedMinutes }

        let byDay = Dictionary(grouping: inYear, by: \.dayKey)
        review.activeDays = byDay.count
        if let best = byDay.max(by: { a, b in
            let ma = a.value.reduce(0) { $0 + $1.focusedMinutes }, mb = b.value.reduce(0) { $0 + $1.focusedMinutes }
            return ma != mb ? ma < mb : a.key > b.key   // ties go to the earlier day
        }) {
            review.brightestDay = Day(date: best.value[0].endedAt, minutes: best.value.reduce(0) { $0 + $1.focusedMinutes })
        }
        if let longest = inYear.max(by: { $0.focusedMinutes != $1.focusedMinutes ? $0.focusedMinutes < $1.focusedMinutes : $0.endedAt > $1.endedAt }) {
            review.longestSession = Session(date: longest.endedAt, minutes: longest.focusedMinutes, category: longest.category)
        }
        let perCategory = Dictionary(grouping: inYear, by: \.category).mapValues { $0.reduce(0) { $0 + $1.focusedMinutes } }
        if let top = perCategory.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key.rawValue > $1.key.rawValue }),
           review.totalMinutes > 0 {
            review.topCategory = Share(category: top.key, fraction: Double(top.value) / Double(review.totalMinutes))
        }

        // Longest run of consecutive focus days.
        let days = byDay.values.map { calendar.startOfDay(for: $0[0].endedAt) }.sorted()
        var run = 0, best = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.dateComponents([.day], from: previous, to: day).day == 1 { run += 1 } else { run = 1 }
            best = max(best, run)
            previous = day
        }
        review.longestRun = best

        let charted = worlds.filter { w in w.visitedAt.map { calendar.component(.year, from: $0) == year } ?? false }
            .sorted { ($0.visitedAt ?? .distantFuture) < ($1.visitedAt ?? .distantFuture) }
        review.worldsCharted = charted.count
        review.firstWorldName = charted.first?.blueprint.name
        review.rareEvents = events.filter { calendar.component(.year, from: $0.date) == year }.count
        return review
    }
}
