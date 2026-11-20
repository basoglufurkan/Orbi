import Foundation

/// One block of a day plan ("09:00–10:30 Write the report"), as plain values
/// the app, its widgets and tests share. In the app every block is a planned
/// `FocusTask` with a time; this is its read-only picture.
struct PlanBlock: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var categoryRaw: String
    var start: Date
    var minutes: Int
    var isCompleted: Bool

    var end: Date { start.addingTimeInterval(TimeInterval(max(0, minutes)) * 60) }
    var category: FocusCategory { FocusCategory(storedValue: categoryRaw) }

    /// Its time includes `date` (start inclusive, end exclusive).
    func contains(_ date: Date) -> Bool { start <= date && date < end }

    /// Start order; blocks starting together keep a stable order.
    static func chronological(_ a: PlanBlock, _ b: PlanBlock) -> Bool {
        if a.start != b.start { return a.start < b.start }
        if a.minutes != b.minutes { return a.minutes < b.minutes }
        return a.id.uuidString < b.id.uuidString
    }
}

/// Where a block stands at a moment.
enum PlanBlockStatus: String, Sendable {
    /// Its time hasn't come.
    case upcoming
    /// Its time is now.
    case active
    /// Marked done: a lit star on the orbit.
    case lit
    /// Its time passed without being marked done: a dim stop, never an alarm.
    case passed
}

/// A day plan read at one moment: which block is now, which is next, and
/// where the "you are here" comet sits on the route. Pure, so the app, the
/// widget timeline and tests agree.
struct DayTimeline: Sendable {
    /// In start order.
    let blocks: [PlanBlock]
    let now: Date

    /// How long before the first stop the comet starts approaching it, and
    /// how long after the last one it takes to drift home.
    static let approach: TimeInterval = 3600

    init(blocks: [PlanBlock], now: Date) {
        self.blocks = blocks.sorted(by: PlanBlock.chronological)
        self.now = now
    }

    func status(of block: PlanBlock) -> PlanBlockStatus {
        if block.isCompleted { return .lit }
        if now >= block.end { return .passed }
        if now >= block.start { return .active }
        return .upcoming
    }

    /// The unfinished block whose time is now; the latest-starting one when
    /// blocks overlap.
    var current: PlanBlock? { blocks.last { !$0.isCompleted && $0.contains(now) } }

    /// The next unfinished block that hasn't begun.
    var next: PlanBlock? { blocks.first { !$0.isCompleted && $0.start > now } }

    /// What the plan points at right now: the current block, else the next.
    var focus: PlanBlock? { current ?? next }

    var litCount: Int { blocks.filter(\.isCompleted).count }
    var plannedMinutes: Int { blocks.reduce(0) { $0 + max(0, $1.minutes) } }

    /// Every stop is lit or behind us.
    var isComplete: Bool { !blocks.isEmpty && blocks.allSatisfy { $0.isCompleted || now >= $0.end } }

    /// Seconds until the next block begins.
    var untilNext: TimeInterval? { next.map { $0.start.timeIntervalSince(now) } }

    /// Seconds left in the current block.
    var leftInCurrent: TimeInterval? { current.map { $0.end.timeIntervalSince(now) } }

    /// 0…1 through a block's time.
    func progress(of block: PlanBlock) -> Double {
        let length = block.end.timeIntervalSince(block.start)
        guard length > 0 else { return now >= block.start ? 1 : 0 }
        return min(1, max(0, now.timeIntervalSince(block.start) / length))
    }

    /// The comet's place on the route, measured in stops: `k` is at stop k,
    /// `k + f` is a fraction f of the way on to stop k + 1, `-1` is the start
    /// of the route (dawn) and `blocks.count` its end (night). It follows the
    /// clock: inside an unfinished block's time it waits at that stop, between
    /// blocks it travels in step with the free time. A block lit early counts
    /// as left behind from its start, so the comet moves on toward the next.
    var cursor: Double {
        let n = blocks.count
        guard n > 0 else { return 0 }
        if let k = blocks.lastIndex(where: { !$0.isCompleted && $0.contains(now) }) { return Double(k) }
        guard let k = blocks.lastIndex(where: { $0.start <= now }) else {
            let lead = blocks[0].start.timeIntervalSince(now)
            return -min(1, max(0, lead) / Self.approach)
        }
        // Everything up to k is behind us: ended, or lit.
        let reached = blocks[...k].map { $0.isCompleted ? min($0.start, $0.end) : $0.end }.max() ?? blocks[k].end
        let since = max(0, now.timeIntervalSince(reached))
        if k == n - 1 { return Double(k) + min(1, since / Self.approach) }
        let gap = blocks[k + 1].start.timeIntervalSince(reached)
        guard gap > 0 else { return Double(k) }
        return Double(k) + min(1, since / gap)
    }

    /// Moments after `now` where what the plan shows changes (a block begins
    /// or ends), soonest first. Widgets put a timeline entry at each.
    func boundaries(limit: Int = 40) -> [Date] {
        let dates = Set(blocks.flatMap { [$0.start, $0.end] }).filter { $0 > now }
        return Array(dates.sorted().prefix(limit))
    }

    /// The blocks that fall on `day` (by start), in order.
    static func blocks(_ blocks: [PlanBlock], on day: Date, calendar: Calendar) -> [PlanBlock] {
        blocks.filter { calendar.isDate($0.start, inSameDayAs: day) }.sorted(by: PlanBlock.chronological)
    }
}
