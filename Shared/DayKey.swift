import Foundation

/// A calendar-day identifier ("yyyy-MM-dd") resolved in a specific time zone.
///
/// Sessions store the day key computed at completion time, so history never
/// shifts when the user travels or changes time zones later.
///
/// Keys are always Gregorian, whatever calendar the user's locale uses
/// (Islamic, Buddhist, Japanese, …): only the passed calendar's *time zone*
/// matters. Otherwise keys from different calendars would not compare or sort.
struct DayKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }

    init(_ date: Date, calendar: Calendar = .current) {
        let c = Self.gregorian(matching: calendar).dateComponents([.year, .month, .day], from: date)
        rawValue = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    var description: String { rawValue }

    static func < (lhs: DayKey, rhs: DayKey) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The start of this day in the given calendar's time zone (nil for malformed keys).
    func startDate(calendar: Calendar = .current) -> Date? {
        let parts = rawValue.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Self.gregorian(matching: calendar).date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// The key `days` calendar days away (negative for the past).
    func adding(days: Int, calendar: Calendar = .current) -> DayKey {
        let gregorian = Self.gregorian(matching: calendar)
        guard let start = startDate(calendar: calendar),
              let shifted = gregorian.date(byAdding: .day, value: days, to: start) else { return self }
        return DayKey(shifted, calendar: calendar)
    }

    /// A Gregorian calendar in the same time zone as `calendar`.
    static func gregorian(matching calendar: Calendar) -> Calendar {
        guard calendar.identifier != .gregorian else { return calendar }
        var g = Calendar(identifier: .gregorian)
        g.timeZone = calendar.timeZone
        return g
    }
}
