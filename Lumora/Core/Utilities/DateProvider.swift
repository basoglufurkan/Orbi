import Foundation

/// Injectable source of "now" and the user's calendar, so timer and calendar
/// logic can be tested deterministically (midnight, time-zone changes, …).
protocol DateProvider: Sendable {
    var now: Date { get }
    var calendar: Calendar { get }
}

struct SystemDateProvider: DateProvider {
    var now: Date { Date() }
    var calendar: Calendar { Calendar.autoupdatingCurrent }
}

/// The system clock shifted by a fixed amount: a debug clock that starts at
/// a chosen time and runs on in real time.
struct OffsetDateProvider: DateProvider {
    var offset: TimeInterval
    var now: Date { Date().addingTimeInterval(offset) }
    var calendar: Calendar { Calendar.autoupdatingCurrent }

    /// Today at `minutes` after midnight, from now on.
    init(minutesAfterMidnight minutes: Int, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) {
        let target = calendar.startOfDay(for: now).addingTimeInterval(TimeInterval(minutes * 60))
        offset = target.timeIntervalSince(now)
    }
}

/// Mutable clock for tests and previews.
final class ManualDateProvider: DateProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    private var _calendar: Calendar

    init(now: Date, timeZone: TimeZone = .current) {
        _now = now
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        _calendar = cal
    }

    var now: Date { lock.withLock { _now } }
    var calendar: Calendar { lock.withLock { _calendar } }

    func advance(by seconds: TimeInterval) { lock.withLock { _now += seconds } }
    func set(_ date: Date) { lock.withLock { _now = date } }
    func setTimeZone(_ tz: TimeZone) { lock.withLock { _calendar.timeZone = tz } }
}
