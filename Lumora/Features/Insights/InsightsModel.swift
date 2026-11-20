import Foundation

/// Pure aggregation for the Insights screen, computed from session facts.
struct InsightsModel: Equatable {
    enum Period: Hashable { case week, month }

    struct DayBar: Identifiable, Equatable {
        var id: DayKey { day }
        var day: DayKey
        var date: Date
        var minutes: Int
        var isToday: Bool
        var isRest: Bool
    }

    struct CategoryShare: Identifiable, Equatable {
        var id: FocusCategory { category }
        var category: FocusCategory
        var minutes: Int
        var fraction: Double
    }

    struct WeekTotal: Identifiable, Equatable {
        var id: Date { start }
        var start: Date
        var minutes: Int
    }

    var period: Period
    var bars: [DayBar] = []
    var totalMinutes = 0
    var categories: [CategoryShare] = []
    var steadiestPart: String?
    var restDayNames: [String] = []
    var weekTotals: [WeekTotal] = []
    var monthGrid: [DayBar] = []
    var monthName = ""
    var maxMonthMinutes = 0
    /// Whole periods back from the current one.
    var offset = 0
    var rangeStart = Date.distantPast
    var rangeEnd = Date.distantPast
    /// Focus exists before the shown period, so stepping back shows something.
    var hasEarlier = false

    /// `offset` steps back in whole periods: 1 is last week or last month.
    static func make(facts: [SessionFacts], period: Period, today: DayKey, calendar: Calendar, now: Date,
                     offset: Int = 0) -> InsightsModel {
        var model = InsightsModel(period: period)
        let back = max(0, offset)
        // The last day of the shown week, and a moment inside the shown month.
        let anchor = today.adding(days: -7 * back, calendar: calendar)
        let monthAnchor = calendar.date(byAdding: .month, value: -back, to: now) ?? now
        let qualifying = facts.filter(\.qualifies)
        var byDay: [DayKey: Int] = [:]
        for s in qualifying { byDay[s.dayKey, default: 0] += s.focusedSeconds }
        let focusDays = Set(byDay.keys)

        // Bars: seven days, or every day of the month.
        let days: [DayKey]
        switch period {
        case .week:
            days = (0..<7).reversed().map { anchor.adding(days: -$0, calendar: calendar) }
        case .month:
            let start = calendar.dateInterval(of: .month, for: monthAnchor)?.start ?? monthAnchor
            let count = calendar.range(of: .day, in: .month, for: monthAnchor)?.count ?? 30
            days = (0..<count).map { DayKey(calendar.date(byAdding: .day, value: $0, to: start) ?? start, calendar: calendar) }
        }
        let firstFocus = focusDays.min()
        model.bars = days.map { d in
            let minutes = (byDay[d] ?? 0) / 60
            let past = d < today
            let rest = minutes == 0 && past && (firstFocus.map { d > $0 } ?? false)
            return DayBar(day: d, date: d.startDate(calendar: calendar) ?? now, minutes: minutes, isToday: d == today, isRest: rest)
        }
        let range = Set(days)
        let inRange = qualifying.filter { range.contains($0.dayKey) }
        model.totalMinutes = inRange.reduce(0) { $0 + $1.focusedSeconds } / 60

        // Categories.
        var byCategory: [FocusCategory: Int] = [:]
        for s in inRange { byCategory[s.category, default: 0] += s.focusedSeconds / 60 }
        let total = max(1, byCategory.values.reduce(0, +))
        model.categories = byCategory.map { CategoryShare(category: $0.key, minutes: $0.value, fraction: Double($0.value) / Double(total)) }
            .filter { $0.minutes > 0 }
            .sorted { $0.minutes > $1.minutes }

        // Steadiest part of the day.
        var buckets = [0, 0, 0, 0]
        for s in inRange {
            let hour = calendar.component(.hour, from: s.startedAt)
            let b = hour < 12 ? 0 : hour < 17 ? 1 : hour < 22 ? 2 : 3
            buckets[b] += s.focusedSeconds
        }
        if let best = buckets.indices.max(by: { buckets[$0] < buckets[$1] }), buckets[best] > 0 {
            model.steadiestPart = [String(localized: "before noon"), String(localized: "in the afternoon"),
                                   String(localized: "in the evening"), String(localized: "late at night")][best]
        }
        model.restDayNames = model.bars.filter(\.isRest).suffix(2).map { $0.date.formatted(.dateTime.weekday(.wide)) }

        // Weekly totals (four weeks to the end of the shown period) for the month view.
        let monthEnd: DayKey = {
            guard back > 0, let last = days.last else { return today }
            return last
        }()
        model.weekTotals = (0..<4).reversed().map { w in
            let end = (period == .month ? monthEnd : anchor).adding(days: -7 * w, calendar: calendar)
            let keys = Set((0..<7).map { end.adding(days: -$0, calendar: calendar) })
            let minutes = qualifying.filter { keys.contains($0.dayKey) }.reduce(0) { $0 + $1.focusedSeconds } / 60
            return WeekTotal(start: end.adding(days: -6, calendar: calendar).startDate(calendar: calendar) ?? now, minutes: minutes)
        }

        // Month sky grid.
        let monthStart = calendar.dateInterval(of: .month, for: monthAnchor)?.start ?? monthAnchor
        let monthDays = calendar.range(of: .day, in: .month, for: monthAnchor)?.count ?? 30
        model.monthGrid = (0..<monthDays).map { i in
            let date = calendar.date(byAdding: .day, value: i, to: monthStart) ?? monthStart
            let key = DayKey(date, calendar: calendar)
            return DayBar(day: key, date: date, minutes: (byDay[key] ?? 0) / 60, isToday: key == today, isRest: false)
        }
        model.maxMonthMinutes = model.monthGrid.map(\.minutes).max() ?? 0
        model.monthName = monthStart.formatted(.dateTime.month(.wide))
        model.offset = back
        model.rangeStart = days.first?.startDate(calendar: calendar) ?? now
        model.rangeEnd = days.last?.startDate(calendar: calendar) ?? now
        model.hasEarlier = facts.contains { $0.qualifies && $0.dayKey < (days.first ?? today) }
        return model
    }

    /// Every session as CSV, oldest first: one row each, for spreadsheets.
    static func csv(facts: [SessionFacts]) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        func field(_ text: String) -> String {
            guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return text }
            return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var lines = ["day,started,ended,focused_minutes,planned_minutes,pauses,category,outcome,earned_star,intention"]
        for f in facts.sorted(by: { $0.startedAt < $1.startedAt }) {
            lines.append([f.dayKey.rawValue, iso.string(from: f.startedAt), iso.string(from: f.endedAt),
                          String(f.focusedSeconds / 60), String(f.plannedSeconds / 60), String(f.pauseCount),
                          f.category.rawValue, f.outcome.rawValue, f.qualifies ? "yes" : "no", field(f.intention)]
                .joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
