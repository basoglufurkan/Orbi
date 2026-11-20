import Foundation

/// A block's reminder choices, stored on its task.
struct PlanReminderSettings: Codable, Equatable, Sendable {
    /// Minutes before the block begins; 0 means no early reminder.
    var beforeMinutes: Int
    /// A notification when it begins.
    var atStart: Bool
    /// An alarm when it begins (AlarmKit).
    var alarm: Bool

    static let standard = PlanReminderSettings(beforeMinutes: 10, atStart: true, alarm: false)
    static let leadOptions = [0, 5, 10, 15, 30, 60]

    var isSilent: Bool { beforeMinutes == 0 && !atStart && !alarm }

    /// What a new block starts with: the last choice made in the editor.
    static var lastUsed: PlanReminderSettings {
        get {
            guard let data = UserDefaults.standard.data(forKey: storageKey),
                  let value = try? JSONDecoder().decode(PlanReminderSettings.self, from: data) else { return .standard }
            return value
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: storageKey) }
    }

    private static let storageKey = "lumora.plan.lastReminders"
}

/// The time of a planned task: a block on its day.
struct BlockSchedule: Equatable, Sendable {
    var start: Date
    var minutes: Int = DayPlanner.defaultMinutes
    var reminders: PlanReminderSettings = .standard

    static let minuteRange = 5...(16 * 60)
}

/// Pure rules for editing a day plan: where a new block goes, what it
/// overlaps, how reordering and "running late" move times, and how long a
/// focus started from a block lasts.
struct DayPlanner {
    var calendar: Calendar
    var now: Date

    static let defaultMinutes = 60
    static let durationPresets = [15, 30, 45, 60, 90, 120, 180]
    static let lateOptions = [5, 15, 30]
    /// A later day's first suggestion.
    static let morningHour = 9

    /// Rounds up to the next multiple of `minutes` past the hour (seconds dropped).
    func roundedUp(_ date: Date, to minutes: Int = 15) -> Date {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard let hourStart = calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: c.hour)) else {
            return date
        }
        let minute = c.minute ?? 0, second = c.second ?? 0
        let exact = second == 0 && minute % minutes == 0
        let slots = exact ? minute / minutes : minute / minutes + 1
        return hourStart.addingTimeInterval(TimeInterval(slots * minutes * 60))
    }

    /// The first free stretch of `minutes` on `day`: from the next quarter
    /// hour today, from 09:00 on a later day, and never on top of a block.
    func suggestedStart(on day: Date, minutes: Int, among blocks: [PlanBlock]) -> Date {
        let morning = calendar.date(bySettingHour: Self.morningHour, minute: 0, second: 0, of: day)
            ?? calendar.startOfDay(for: day)
        var candidate = calendar.isDate(day, inSameDayAs: now) ? roundedUp(now) : morning
        let length = TimeInterval(max(1, minutes) * 60)
        for block in DayTimeline.blocks(blocks, on: day, calendar: calendar) where block.end > candidate {
            if candidate.addingTimeInterval(length) <= block.start { return candidate }
            candidate = max(candidate, block.end)
        }
        return candidate
    }

    /// Blocks that share any time with `[start, start + minutes)`, except `id`.
    func overlaps(start: Date, minutes: Int, excluding id: UUID?, in blocks: [PlanBlock]) -> [PlanBlock] {
        let end = start.addingTimeInterval(TimeInterval(max(0, minutes) * 60))
        return blocks
            .filter { $0.id != id && $0.start < end && start < $0.end }
            .sorted(by: PlanBlock.chronological)
    }

    /// New starts after moving rows of one day (List `onMove` semantics,
    /// rows in start order). The day's first start and the gaps between
    /// neighbouring blocks stay where they were; the blocks are laid out
    /// again in the new order, so each keeps its length and none overlap.
    static func repack(_ day: [PlanBlock], moving source: IndexSet, to destination: Int) -> [UUID: Date] {
        let sorted = day.sorted(by: PlanBlock.chronological)
        guard let first = sorted.first else { return [:] }
        let gaps = zip(sorted, sorted.dropFirst()).map { max(0, $1.start.timeIntervalSince($0.end)) }

        let moving = source.sorted().filter { $0 < sorted.count }.map { sorted[$0] }
        var order = sorted.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        order.insert(contentsOf: moving, at: max(0, min(insertAt, order.count)))

        var result: [UUID: Date] = [:]
        var start = first.start
        for (i, block) in order.enumerated() {
            result[block.id] = start
            start.addTimeInterval(TimeInterval(max(0, block.minutes) * 60) + (i < gaps.count ? gaps[i] : 0))
        }
        return result
    }

    /// "Running late": every block that hasn't begun yet (and isn't lit)
    /// moves `minutes` later; what's under way or behind stays.
    func shifted(_ blocks: [PlanBlock], by minutes: Int) -> [UUID: Date] {
        blocks.filter { !$0.isCompleted && $0.start >= now }
            .reduce(into: [:]) { $0[$1.id] = $1.start.addingTimeInterval(TimeInterval(minutes * 60)) }
    }

    /// A focus started from a block: the usual session length, never longer
    /// than what's left of the block, within the setup screen's range.
    func focusMinutes(for block: PlanBlock, usual: Int) -> Int {
        clampFocus(min(usual, available(in: block)))
    }

    /// The whole block (what's left of it, once under way) as one session.
    func wholeBlockMinutes(for block: PlanBlock) -> Int {
        clampFocus(available(in: block))
    }

    /// Sessions of `focusMinutes` (with short breaks between) that fit in a
    /// block of `minutes`: a 90-minute block holds three 25-minute sessions.
    static func estimatedSessions(minutes: Int, focusMinutes: Int, breakMinutes: Int = 5) -> Int {
        let fit = Double(minutes + breakMinutes) / Double(max(1, focusMinutes + breakMinutes))
        return min(TaskDraft.estimateRange.upperBound, max(1, Int(fit.rounded(.down))))
    }

    private func available(in block: PlanBlock) -> Int {
        block.contains(now) ? Int(block.end.timeIntervalSince(now) / 60) : block.minutes
    }

    private func clampFocus(_ minutes: Int) -> Int {
        let range = FocusConfiguration.customRangeMinutes
        return min(range.upperBound, max(range.lowerBound, minutes))
    }
}

/// One reminder the plan wants delivered.
struct PlanAlert: Equatable, Sendable {
    enum Kind: String, Sendable { case before, start }

    var block: PlanBlock
    var kind: Kind
    var fireDate: Date
    var minutesBefore: Int

    var id: String { PlanReminderPlanner.identifier(block: block.id, kind: kind) }
}

/// An alarm the plan wants to ring.
struct PlanAlarmRequest: Equatable, Sendable {
    var block: PlanBlock
    var fireDate: Date { block.start }
}

/// Turns the plan and each block's choices into reminders and alarms.
enum PlanReminderPlanner {
    /// iOS keeps 64 pending notifications per app; the plan uses at most
    /// this many, soonest first, and tops them up whenever Lumora opens.
    static let notificationLimit = 30
    static let alarmLimit = 12
    static let prefix = "lumora.plan."

    static func identifier(block: UUID, kind: PlanAlert.Kind) -> String {
        prefix + block.uuidString + "." + kind.rawValue
    }

    /// The block a plan notification belongs to.
    static func blockID(fromIdentifier id: String) -> UUID? {
        guard id.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(id.dropFirst(prefix.count).prefix(36)))
    }

    /// Notifications still ahead of `now` for unlit blocks. When the block
    /// rings an alarm (and alarms work here) the start notification would
    /// only repeat it, so it's left out.
    static func alerts(for items: [(block: PlanBlock, reminders: PlanReminderSettings)], now: Date,
                       alarmsActive: Bool, limit: Int = notificationLimit) -> [PlanAlert] {
        var result: [PlanAlert] = []
        for (block, reminders) in items where !block.isCompleted {
            if reminders.beforeMinutes > 0 {
                let fire = block.start.addingTimeInterval(-TimeInterval(reminders.beforeMinutes * 60))
                if fire > now {
                    result.append(PlanAlert(block: block, kind: .before, fireDate: fire, minutesBefore: reminders.beforeMinutes))
                }
            }
            if reminders.atStart, !(reminders.alarm && alarmsActive), block.start > now {
                result.append(PlanAlert(block: block, kind: .start, fireDate: block.start, minutesBefore: 0))
            }
        }
        result.sort { a, b in
            if a.fireDate != b.fireDate { return a.fireDate < b.fireDate }
            return a.id < b.id
        }
        return Array(result.prefix(limit))
    }

    /// Alarms for unlit blocks that ask for one and haven't begun.
    static func alarms(for items: [(block: PlanBlock, reminders: PlanReminderSettings)], now: Date,
                       limit: Int = alarmLimit) -> [PlanAlarmRequest] {
        let wanted = items.filter { $0.reminders.alarm && !$0.block.isCompleted && $0.block.start > now }
            .map(\.block).sorted(by: PlanBlock.chronological)
        return Array(wanted.prefix(limit)).map(PlanAlarmRequest.init(block:))
    }
}
