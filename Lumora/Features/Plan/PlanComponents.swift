import SwiftData
import SwiftUI

/// Planned tasks that have a time, for any view showing the day plan.
struct DayPlanReader<Content: View>: View {
    @Query(filter: #Predicate<FocusTask> { $0.isPlanned && !$0.isArchived && $0.scheduledStart != nil })
    private var scheduled: [FocusTask]
    @ViewBuilder var content: ([FocusTask]) -> Content

    var body: some View {
        content(scheduled.sorted { a, b in
            guard let pa = a.planBlock, let pb = b.planBlock else { return false }
            return PlanBlock.chronological(pa, pb)
        })
    }
}

/// Words and numbers for the day plan.
enum PlanFormat {
    /// A time of day in the person's own clock: "14:00", or "2:00 PM" where
    /// clocks have 12 hours. A plan needs AM and PM to be unambiguous.
    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    /// "09:00–10:30".
    static func range(_ block: PlanBlock) -> String {
        "\(time(block.start))–\(time(block.end))"
    }

    /// Spoken "9:00 to 10:30".
    static func spokenRange(_ block: PlanBlock) -> String {
        String(localized: "\(PlanFormat.time(block.start)) to \(PlanFormat.time(block.end))")
    }

    /// A countdown: "24:13", or "1:12:05" past an hour.
    static func countdown(_ seconds: TimeInterval) -> String {
        LMFormat.clock(max(0, seconds))
    }

    /// Whole minutes, rounded up, as "1h 12m".
    static func span(_ seconds: TimeInterval) -> String {
        LMFormat.minutes(Int((max(0, seconds) / 60).rounded(.up)))
    }

    /// "24m left", "in 1h 12m", "lit", "passed".
    static func status(_ block: PlanBlock, in timeline: DayTimeline) -> String {
        switch timeline.status(of: block) {
        case .active: String(localized: "\(span(block.end.timeIntervalSince(timeline.now))) left")
        case .upcoming: String(localized: "in \(span(block.start.timeIntervalSince(timeline.now)))")
        case .lit: String(localized: "lit")
        case .passed: String(localized: "passed")
        }
    }

    /// "Today", "Tomorrow", "Wed 12".
    static func day(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "Tomorrow")
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day())
    }

    static func color(for status: PlanBlockStatus, category: FocusCategory) -> Color {
        switch status {
        case .upcoming: category.color
        case .active: LMColor.calm
        case .lit: LMColor.reward
        case .passed: LMColor.textTertiary
        }
    }

    /// What VoiceOver reads for a block.
    static func spoken(_ block: PlanBlock, in timeline: DayTimeline) -> String {
        let state: String = switch timeline.status(of: block) {
        case .active: String(localized: "now, \(LMFormat.spokenMinutes(Int((block.end.timeIntervalSince(timeline.now) / 60).rounded(.up)))) left")
        case .upcoming: String(localized: "begins in \(LMFormat.spokenMinutes(Int((block.start.timeIntervalSince(timeline.now) / 60).rounded(.up))))")
        case .lit: String(localized: "done, its star is lit")
        case .passed: String(localized: "its time has passed")
        }
        return [spokenRange(block), block.title, block.category.displayName, state].joined(separator: ", ")
    }
}

/// A block's mark: a hollow orb before it begins, a bright orb while it
/// runs, the category's star once lit, a dim ring once its time passed.
struct PlanStopGlyph: View {
    var status: PlanBlockStatus
    var category: FocusCategory
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            switch status {
            case .upcoming:
                Circle().fill(category.color.opacity(0.14))
                Circle().strokeBorder(category.color, lineWidth: 1.5)
            case .active:
                Circle().fill(LMColor.calm.opacity(0.25)).scaleEffect(1.5)
                Circle().fill(LMColor.calm)
                Circle().fill(Color.white).frame(width: size * 0.36, height: size * 0.36)
            case .lit:
                StarShape(points: max(4, category.starPoints))
                    .fill(LMColor.reward)
                    .scaleEffect(1.25)
                    .shadow(color: LMColor.reward.opacity(0.7), radius: 5)
            case .passed:
                Circle().strokeBorder(LMColor.textTertiary.opacity(0.6), style: StrokeStyle(lineWidth: 1.25, dash: [2.5, 2.5]))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension View {
    /// The planner's field surface (matches the task editor's).
    func planField(focused: Bool) -> some View {
        background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(LMColor.textPrimary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(focused ? LMColor.focus : LMColor.hairline, lineWidth: focused ? 1.5 : 1))
    }
}
