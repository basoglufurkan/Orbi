import SwiftData
import SwiftUI

/// Active habits, in their order, for any view that shows them.
struct HabitsReader<Content: View>: View {
    @Query(filter: #Predicate<Habit> { !$0.isArchived }, sort: \Habit.sortOrder) private var habits: [Habit]
    @ViewBuilder var content: ([Habit]) -> Content

    var body: some View { content(habits) }
}

/// Words for habits.
enum HabitFormat {
    /// "Every day", "Weekdays", "Mon, Wed, Fri", "3 times a week".
    static func cadence(_ cadence: HabitCadence, calendar: Calendar) -> String {
        switch cadence {
        case .daily:
            return String(localized: "Every day")
        case let .weekdays(days):
            if days == [2, 3, 4, 5, 6] { return String(localized: "Weekdays") }
            if days == [1, 7] { return String(localized: "Weekends") }
            let symbols = calendar.shortWeekdaySymbols
            return HabitCalendar(calendar).orderedWeekdays.filter(days.contains).map { symbols[$0 - 1] }
                .formatted(.list(type: .and, width: .narrow))
        case let .timesPerWeek(n):
            return n == 1 ? String(localized: "Once a week") : String(localized: "\(n) times a week")
        }
    }

    /// "12-day streak", "3-week streak".
    static func streak(_ stats: HabitStats) -> String {
        stats.countsWeeks ? String(localized: "\(stats.current)-week streak") : String(localized: "\(stats.current)-day streak")
    }

    /// "12d" / "3w", for tight spaces.
    static func shortStreak(_ value: Int, weeks: Bool) -> String {
        weeks ? String(localized: "\(value)w") : String(localized: "\(value)d")
    }

    /// The line under a habit's name: what's left today, or how it stands.
    static func status(_ habit: Habit, stats: HabitStats, focusedToday: Int?, calendar: Calendar) -> String {
        if stats.keptToday {
            return stats.current > 1 ? String(localized: "Kept · \(streak(stats))") : String(localized: "Kept today")
        }
        if let focused = focusedToday, habit.isFocusLinked {
            return String(localized: "\(focused) of \(habit.focusMinutes) min focused")
        }
        if case let .timesPerWeek(target) = habit.cadence {
            return String(localized: "\(stats.keptThisWeek) of \(target) this week")
        }
        if !stats.dueToday { return String(localized: "Rest day · \(cadence(habit.cadence, calendar: calendar))") }
        if stats.atRisk { return String(localized: "Keep your \(streak(stats)) alive") }
        return cadence(habit.cadence, calendar: calendar)
    }

    static func time(hour: Int, minute: Int, calendar: Calendar) -> String {
        let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour().minute())
    }
}

// MARK: Star

/// A habit's star: its symbol inside a halo as bright as its run. Open, it
/// waits as a dashed ring in the habit's colour; kept, it burns gold. A
/// keep bursts into sparks (a soft crossfade with Reduce Motion).
struct HabitStarView: View {
    var symbol: String
    var hue: FocusCategory
    /// The run in days (weeks count seven).
    var streakDays: Int
    var kept: Bool
    var size: CGFloat = 52
    /// Bumped on each keep: plays the burst.
    var burst: Int = 0

    @Environment(\.motionLevel) private var motion
    @State private var breathing = false

    var body: some View {
        let glow = HabitLuminosity.brightness(days: streakDays)
        let tint = kept ? LMColor.rewardFill : hue.color
        let animated = motion.animatesContinuously
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [tint.opacity((kept ? 0.55 : 0.32) * glow), .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.75))
                .frame(width: size * 1.5, height: size * 1.5)
                .scaleEffect(animated && breathing ? 1.08 : 0.94)
            if kept {
                StarShape(points: max(4, hue.starPoints), innerRatio: 0.62)
                    .fill(LinearGradient(colors: [LMColor.rewardFill, LMColor.rewardFill.opacity(0.75)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: size, height: size)
                    .shadow(color: LMColor.rewardFill.opacity(0.6 * glow), radius: size * 0.22)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            } else {
                Circle()
                    .strokeBorder(hue.color.opacity(0.35 + 0.5 * glow), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                    .frame(width: size * 0.86, height: size * 0.86)
                    .rotationEffect(.degrees(animated && breathing ? 45 : 0))
            }
            Image(systemName: symbol)
                .font(.system(size: size * (kept ? 0.3 : 0.34), weight: .semibold))
                .foregroundStyle(kept ? LMColor.onAccent : LMColor.textPrimary.opacity(0.45 + 0.55 * glow))
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: size, height: size)
        .overlay { HabitBurstView(trigger: burst, tint: LMColor.rewardFill, size: size) }
        .animation(animated ? LMSpring.bloom : .easeInOut(duration: 0.2), value: kept)
        .onAppear {
            guard animated else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathing = true }
        }
        .accessibilityHidden(true)
    }
}

/// Sparks and a ring flying out of a star that was just kept.
struct HabitBurstView: View {
    var trigger: Int
    var tint: Color
    var size: CGFloat
    @Environment(\.motionLevel) private var motion

    var body: some View {
        if motion.animatesContinuously {
            Color.clear
                .keyframeAnimator(initialValue: 1.0, trigger: trigger) { content, progress in
                    content.overlay {
                        Canvas { [trigger, tint, size] g, canvas in
                            Self.draw(&g, canvas: canvas, progress: progress, trigger: trigger, tint: tint, size: size)
                        }
                        .frame(width: size * 3, height: size * 3)
                        .allowsHitTesting(false)
                    }
                } keyframes: { _ in
                    MoveKeyframe(0.0)
                    LinearKeyframe(1.0, duration: 0.9)
                }
                .allowsHitTesting(false)
        }
    }

    private nonisolated static func draw(_ g: inout GraphicsContext, canvas: CGSize, progress: Double,
                                         trigger: Int, tint: Color, size: CGFloat) {
        guard progress < 1 else { return }
        let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let eased = LMCurve.easeOutCubic.value(progress)
        let fade = 1 - progress
        // The ring.
        let r = size * (0.45 + 0.9 * eased)
        g.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: .color(tint.opacity(0.7 * fade)), lineWidth: 2 * fade + 0.5)
        // The sparks.
        let count = 10
        for i in 0..<count {
            let angle = Double(i) / Double(count) * 2 * .pi + Double(trigger) * 0.6
            let reach = size * (0.5 + (i.isMultiple(of: 2) ? 1.0 : 0.75) * eased)
            let p = CGPoint(x: c.x + CGFloat(cos(angle)) * reach, y: c.y + CGFloat(sin(angle)) * reach)
            let s = max(0.5, 4.5 * fade)
            g.fill(StarShape.path(center: p, radius: s, points: 4), with: .color(tint.opacity(fade)))
        }
    }
}

// MARK: Week strip

/// Seven days for a habit: kept stars, open today, dim misses. The last
/// seven days ending today, or this calendar week for a weekly target.
struct HabitWeekStrip: View {
    var habit: Habit
    var today: DayKey
    var calendar: Calendar
    var compact = false

    var body: some View {
        let cal = HabitCalendar(calendar)
        let kept = habit.keptDays
        let schedule = habit.schedule
        HStack(spacing: compact ? 4 : 6) {
            ForEach(days(cal), id: \.self) { day in
                let state = HabitStats.state(of: day, kept: kept, schedule: schedule, today: today, calendar: calendar)
                VStack(spacing: 3) {
                    if !compact {
                        Text(initial(of: day, cal: cal))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(day == today ? LMColor.textPrimary : LMColor.textTertiary)
                    }
                    HabitDayDot(state: state, hue: habit.hue, isToday: day == today)
                        .frame(width: compact ? 12 : 16, height: compact ? 12 : 16)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken(kept: kept, cal: cal)))
    }

    private func days(_ cal: HabitCalendar) -> [DayKey] {
        if habit.cadence.countsWeeks { return cal.week(of: today) }
        return (0..<7).reversed().map { today.adding(days: -$0, calendar: calendar) }
    }

    private func initial(of day: DayKey, cal: HabitCalendar) -> String {
        calendar.veryShortWeekdaySymbols[cal.weekday(of: day) - 1]
    }

    private func spoken(kept: Set<DayKey>, cal: HabitCalendar) -> String {
        let count = days(cal).filter { kept.contains($0) }.count
        return habit.cadence.countsWeeks ? String(localized: "Kept \(count) days this week")
                                         : String(localized: "Kept \(count) of the last 7 days")
    }
}

/// One day as a tiny celestial body.
struct HabitDayDot: View {
    var state: HabitDayState
    var hue: FocusCategory
    var isToday: Bool

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                switch state {
                case .kept:
                    StarShape(points: 4, innerRatio: 0.42).fill(LMColor.rewardFill)
                        .shadow(color: LMColor.rewardFill.opacity(0.7), radius: 3)
                case .open:
                    Circle().strokeBorder(hue.color, style: StrokeStyle(lineWidth: 1.4, dash: [2, 2]))
                case .missed:
                    Circle().fill(LMColor.textTertiary.opacity(0.35)).padding(s * 0.3)
                case .rest:
                    Circle().fill(LMColor.textTertiary.opacity(0.18)).padding(s * 0.4)
                case .future:
                    Circle().strokeBorder(LMColor.hairline, lineWidth: 1).padding(s * 0.18)
                }
            }
            .frame(width: s, height: s)
        }
        .overlay {
            if isToday { Circle().stroke(LMColor.textPrimary.opacity(0.35), lineWidth: 1).padding(-3) }
        }
    }
}

// MARK: Heat map

/// Weeks of a habit as a field of stars, one column a week, today at the
/// bottom right. Brighter where a run was longer. Tapping a past day keeps
/// it (or clears it), so a forgotten day can still be logged.
struct HabitHeatmap: View {
    var habit: Habit
    var today: DayKey
    var calendar: Calendar
    var weeks = 18
    var onToggle: ((DayKey) -> Void)?

    var body: some View {
        let cal = HabitCalendar(calendar)
        let kept = habit.keptDays
        let schedule = habit.schedule
        let lastWeek = cal.weekStart(of: today)
        let columns = (0..<weeks).map { lastWeek.adding(days: -7 * (weeks - 1 - $0), calendar: calendar) }
        let runs = Self.runLengths(kept: kept, calendar: calendar)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 3) {
                VStack(spacing: 3) {
                    ForEach(cal.orderedWeekdays, id: \.self) { weekday in
                        Text(calendar.veryShortWeekdaySymbols[weekday - 1])
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(LMColor.textTertiary)
                            .frame(height: 14)
                    }
                }
                .frame(width: 12)
                .accessibilityHidden(true)
                ForEach(columns, id: \.self) { start in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { offset in
                            let day = start.adding(days: offset, calendar: calendar)
                            cell(day, state: HabitStats.state(of: day, kept: kept, schedule: schedule, today: today, calendar: calendar),
                                 run: runs[day] ?? 0)
                        }
                    }
                }
            }
            HStack {
                Text(monthLabel(columns.first))
                Spacer()
                Text(String(localized: "Today"))
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(LMColor.textTertiary)
            .padding(.leading, 15)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func cell(_ day: DayKey, state: HabitDayState, run: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        let glow = HabitLuminosity.brightness(days: run)
        let body = ZStack {
            switch state {
            case .kept:
                shape.fill(LMColor.rewardFill.opacity(0.25 + 0.75 * glow))
                StarShape(points: 4, innerRatio: 0.4).fill(Color.white.opacity(0.35 * glow)).padding(3)
            case .open:
                shape.strokeBorder(habit.hue.color, style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
            case .missed:
                shape.fill(LMColor.textPrimary.opacity(0.08))
            case .rest:
                shape.fill(LMColor.textPrimary.opacity(0.03))
            case .future:
                Color.clear
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 14)
        if let onToggle, state != .future, day <= today {
            Button { onToggle(day) } label: { body.contentShape(shape) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(spokenDay(day, state: state)))
                .accessibilityHint(Text(state == .kept ? "Clears this day" : "Marks this day kept"))
        } else {
            body.accessibilityHidden(true)
        }
    }

    private func spokenDay(_ day: DayKey, state: HabitDayState) -> String {
        let date = day.startDate(calendar: calendar)?.formatted(.dateTime.weekday(.wide).day().month(.wide)) ?? day.rawValue
        return state == .kept ? String(localized: "\(date), kept") : String(localized: "\(date), not kept")
    }

    private func monthLabel(_ day: DayKey?) -> String {
        guard let date = day?.startDate(calendar: calendar) else { return "" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// For each kept day, how many kept days in a row end there (for glow).
    static func runLengths(kept: Set<DayKey>, calendar: Calendar) -> [DayKey: Int] {
        var result: [DayKey: Int] = [:]
        for day in kept.sorted() {
            result[day] = (result[day.adding(days: -1, calendar: calendar)] ?? 0) + 1
        }
        return result
    }
}

// MARK: Constellation

/// A habit's last fourteen due days drawn as its own constellation: kept
/// days are stars joined by light, misses stay dim, today waits as a pulse.
/// Seeded by the habit, so its shape is its own and never changes.
struct HabitConstellationView: View {
    var habit: Habit
    var today: DayKey
    var calendar: Calendar
    var appeared: Date

    @Environment(\.motionLevel) private var motion

    var body: some View {
        let points = days()
        let kept = habit.keptDays
        let schedule = habit.schedule
        let states = points.map { HabitStats.state(of: $0, kept: kept, schedule: schedule, today: today, calendar: calendar) }
        Group {
            if motion.animatesContinuously {
                TimelineView(.animation(minimumInterval: motion.frameInterval(30))) { context in
                    canvas(states: states, date: context.date)
                }
            } else {
                canvas(states: states, date: .distantFuture)
            }
        }
        .accessibilityHidden(true)
    }

    private func canvas(states: [HabitDayState], date: Date) -> some View {
        Canvas { g, size in
            draw(&g, size: size, states: states, date: date)
        }
    }

    /// The fourteen most recent days the habit asked for (today included).
    private func days() -> [DayKey] {
        let schedule = habit.schedule
        let cal = HabitCalendar(calendar)
        var result: [DayKey] = []
        var day = today
        var guardDays = 0
        while result.count < 14, guardDays < 120 {
            if schedule.cadence.countsWeeks || schedule.isDue(on: day, calendar: cal) || habit.keptDays.contains(day) {
                result.append(day)
            }
            day = day.adding(days: -1, calendar: calendar)
            guardDays += 1
        }
        return result.reversed()
    }

    private func layout(count: Int, size: CGSize) -> [CGPoint] {
        var rng = SeededRandom(seed: StableHash.fnv1a(habit.id.uuidString))
        let pad: CGFloat = 26, top: CGFloat = 40
        let w = size.width - pad * 2, h = size.height - pad - top
        // A wandering path left to right, so the line reads as time.
        return (0..<count).map { i in
            let x = pad + w * (CGFloat(i) + CGFloat(rng.range(0.15, 0.85))) / CGFloat(max(1, count))
            let y = top + h * CGFloat(0.5 + 0.42 * sin(Double(i) * 0.9 + rng.range(0, 6.28)) * rng.range(0.4, 1))
            return CGPoint(x: x, y: y)
        }
    }

    private func draw(_ g: inout GraphicsContext, size: CGSize, states: [HabitDayState], date: Date) {
        let pts = layout(count: states.count, size: size)
        guard !pts.isEmpty else { return }
        let t = date == .distantFuture ? 0 : date.timeIntervalSinceReferenceDate
        let reveal = date == .distantFuture ? 1 : LMCurve.easeOutCubic.value(date.timeIntervalSince(appeared) / 1.4)
        let shown = Double(pts.count) * reveal
        let gold = Color(hex: Palette.warmGold), hue = habit.hue.color

        // Light between consecutive kept stars.
        for i in 1..<max(1, pts.count) where Double(i) < shown {
            let a = states[i - 1], b = states[i]
            var p = Path()
            p.move(to: pts[i - 1])
            p.addLine(to: pts[i])
            if a == .kept, b == .kept {
                g.stroke(p, with: .color(gold.opacity(0.18)), lineWidth: 6)
                g.stroke(p, with: .linearGradient(Gradient(colors: [gold.opacity(0.9), hue.opacity(0.9)]),
                                                  startPoint: pts[i - 1], endPoint: pts[i]), lineWidth: 1.4)
            } else {
                g.stroke(p, with: .color(hue.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
            }
        }
        // The stars.
        for (i, (p, state)) in zip(pts, states).enumerated() where Double(i) < shown {
            let appear = min(1, max(0, shown - Double(i)))
            let twinkle = 0.85 + 0.15 * sin(t * 2.1 + Double(i) * 1.7)
            switch state {
            case .kept:
                let r = 7 * appear * twinkle
                g.fill(Path(ellipseIn: CGRect(x: p.x - r * 2.6, y: p.y - r * 2.6, width: r * 5.2, height: r * 5.2)),
                       with: .radialGradient(Gradient(colors: [gold.opacity(0.45), .clear]), center: p, startRadius: 0, endRadius: r * 2.6))
                g.fill(StarShape.path(center: p, radius: r, points: max(4, habit.hue.starPoints)), with: .color(gold))
            case .open:
                let pulse = 0.5 + 0.5 * sin(t * 3)
                let r = 6 + 3 * pulse
                g.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(hue.opacity(0.5 + 0.4 * pulse)), lineWidth: 1.5)
                g.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)), with: .color(hue))
            case .missed, .rest, .future:
                g.fill(Path(ellipseIn: CGRect(x: p.x - 2.2, y: p.y - 2.2, width: 4.4, height: 4.4)),
                       with: .color(hue.opacity(0.35 * appear)))
            }
        }
    }
}

// MARK: Today's sky

/// Today's habits circling a core of light. Each kept one sends a beam to
/// the core, which grows brighter with every habit kept; open ones drift on
/// the ring, waiting. It turns slowly (still with Reduce Motion).
struct HabitsSkyView: View {
    var habits: [Habit]
    var keptIDs: Set<UUID>
    var streaks: [UUID: Int]

    @Environment(\.motionLevel) private var motion

    var body: some View {
        Group {
            if motion.animatesContinuously {
                TimelineView(.animation(minimumInterval: motion.frameInterval(30))) { context in
                    canvas(t: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                canvas(t: 0)
            }
        }
        .accessibilityHidden(true)
    }

    private func canvas(t: Double) -> some View {
        Canvas { g, size in
            draw(&g, size: size, t: t)
        } symbols: {
            ForEach(habits) { habit in
                Image(systemName: habit.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(keptIDs.contains(habit.id) ? LMColor.onAccent : LMColor.textPrimary)
                    .tag(habit.id)
            }
        }
    }

    private func draw(_ g: inout GraphicsContext, size: CGSize, t: Double) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let n = habits.count
        let kept = habits.filter { keptIDs.contains($0.id) }.count
        let fraction = n > 0 ? Double(kept) / Double(n) : 0
        let gold = Color(hex: Palette.warmGold), violet = Color(hex: Palette.cosmicViolet)
        let rx = size.width * 0.38, ry = size.height * 0.36
        let spin = t * 0.05

        // The ring.
        g.stroke(Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2)),
                 with: .color(violet.opacity(0.22)), style: StrokeStyle(lineWidth: 1, dash: [2, 6], dashPhase: t * 4))

        // The core: brighter for every habit kept.
        let coreR = 16 + 16 * fraction
        let pulse = 1 + 0.06 * sin(t * 1.6)
        g.fill(Path(ellipseIn: CGRect(x: c.x - coreR * 3, y: c.y - coreR * 3, width: coreR * 6, height: coreR * 6)),
               with: .radialGradient(Gradient(colors: [gold.opacity(0.18 + 0.4 * fraction), violet.opacity(0.08), .clear]),
                                     center: c, startRadius: 0, endRadius: coreR * 3 * pulse))
        g.fill(StarShape.path(center: c, radius: coreR * 0.55 * pulse, points: 8, innerRatio: 0.35),
               with: .color(fraction >= 1 ? gold : Color.white.opacity(0.55 + 0.45 * fraction)))

        for (i, habit) in habits.enumerated() {
            let angle = Double(i) / Double(max(1, n)) * 2 * .pi - .pi / 2 + spin
            let p = CGPoint(x: c.x + CGFloat(cos(angle)) * rx, y: c.y + CGFloat(sin(angle)) * ry)
            let isKept = keptIDs.contains(habit.id)
            let glow = HabitLuminosity.brightness(days: streaks[habit.id] ?? 0)
            let hue = habit.hue.color
            var beam = Path()
            beam.move(to: p)
            beam.addLine(to: c)
            if isKept {
                g.stroke(beam, with: .linearGradient(Gradient(colors: [gold.opacity(0.8), gold.opacity(0.05)]), startPoint: p, endPoint: c),
                         lineWidth: 1.6)
                // A mote of light travelling inward.
                let k = (t * 0.6 + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
                let m = CGPoint(x: p.x + (c.x - p.x) * k, y: p.y + (c.y - p.y) * k)
                g.fill(Path(ellipseIn: CGRect(x: m.x - 2, y: m.y - 2, width: 4, height: 4)), with: .color(gold.opacity(1 - k)))
            } else {
                g.stroke(beam, with: .color(hue.opacity(0.12)), style: StrokeStyle(lineWidth: 1, dash: [1, 6]))
            }
            let r: CGFloat = 17
            g.fill(Path(ellipseIn: CGRect(x: p.x - r * 1.9, y: p.y - r * 1.9, width: r * 3.8, height: r * 3.8)),
                   with: .radialGradient(Gradient(colors: [(isKept ? gold : hue).opacity(0.4 * glow), .clear]),
                                         center: p, startRadius: 0, endRadius: r * 1.9))
            if isKept {
                g.fill(StarShape.path(center: p, radius: r, points: max(4, habit.hue.starPoints), innerRatio: 0.62), with: .color(gold))
            } else {
                g.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.8, y: p.y - r * 0.8, width: r * 1.6, height: r * 1.6)),
                       with: .color(LMColor.bgRaised.opacity(0.9)))
                g.stroke(Path(ellipseIn: CGRect(x: p.x - r * 0.8, y: p.y - r * 0.8, width: r * 1.6, height: r * 1.6)),
                         with: .color(hue.opacity(0.4 + 0.5 * glow)), style: StrokeStyle(lineWidth: 1.3, dash: [3, 3]))
            }
            if let symbol = g.resolveSymbol(id: habit.id) {
                g.draw(symbol, at: p)
            }
        }
    }
}
