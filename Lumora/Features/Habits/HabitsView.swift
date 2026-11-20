import SwiftData
import SwiftUI

/// Habits: today's habits circling a core of light, each one a star you
/// keep with a tap. A habit's star brightens with its run; focus-linked
/// habits are kept by focusing, and start a session in one tap.
struct HabitsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Habit.sortOrder) private var allHabits: [Habit]

    @State private var editor: HabitEditorTarget?
    @State private var bursts: [UUID: Int] = [:]
    @State private var showResting = false
    @State private var path: [UUID] = []
    @State private var appeared = false

    var body: some View {
        let today = app.today
        let calendar = app.clock.calendar
        let active = allHabits.filter { !$0.isArchived }
        let resting = allHabits.filter(\.isArchived)
        let stats = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0.stats(today: today, calendar: calendar)) })
        let todays = active.filter { stats[$0.id]?.dueToday == true || stats[$0.id]?.keptToday == true }
        let others = active.filter { !todays.contains($0) }
        NavigationStack(path: $path) {
            ZStack {
                LMColor.bgBase.ignoresSafeArea()
                CosmicBackgroundView(mood: .home, light: 0.35, showsStars: true, starOpacity: 0.5)
                    .ignoresSafeArea()
                if active.isEmpty && resting.isEmpty {
                    FittingScrollView(alignment: .center) { emptyState }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: LMSpace.m) {
                            if !todays.isEmpty {
                                hero(todays: todays, stats: stats)
                            }
                            if !todays.isEmpty {
                                section(String(localized: "Today"), color: LMColor.calm, habits: todays, stats: stats)
                            }
                            if !others.isEmpty {
                                section(String(localized: "Resting today"), color: LMColor.textTertiary, habits: others, stats: stats)
                            }
                            if active.isEmpty {
                                Text("Every habit is resting. Bring one back, or begin a new one.")
                                    .font(LMFont.callout.weight(.regular))
                                    .foregroundStyle(LMColor.textSecondary)
                            }
                            CosmicButton(title: "New habit", systemImage: "plus", kind: .secondary, height: 52) {
                                editor = .new(nil)
                            }
                            .accessibilityIdentifier("habits.newBottom")
                            if !resting.isEmpty { restingSection(resting) }
                            Color.clear.frame(height: LMSpace.l)
                        }
                        .padding(.horizontal, LMSpace.l)
                        .padding(.top, LMSpace.xs)
                        .readableColumn()
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle(String(localized: "Habits"))
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: UUID.self) { id in
                if let habit = allHabits.first(where: { $0.id == id }) {
                    HabitDetailView(habit: habit) { editor = .edit(habit) }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                        .accessibilityIdentifier("habits.done")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { editor = .new(nil) } label: { Image(systemName: "plus") }
                        .accessibilityLabel(Text("New habit"))
                        .accessibilityIdentifier("habits.add")
                }
            }
        }
        .tint(LMColor.focus)
        .sheet(item: $editor) { target in
            HabitEditorView(target: target)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
        .onAppear {
            guard !appeared else { return }
            appeared = true
            Telemetry.log(.habitsOpened(habits: active.count, keptToday: todays.filter { stats[$0.id]?.keptToday == true }.count,
                                        source: app.habitsSource))
            app.habitsSource = "link"
        }
        .onChange(of: app.timer.state.phase.isFocusActive) { _, active in
            // A session started elsewhere (Siri, the watch): make way for the focus screen.
            if active { app.isShowingHabits = false }
        }
        .telemetryScreen("habits")
    }

    // MARK: Hero

    private func hero(todays: [Habit], stats: [UUID: HabitStats]) -> some View {
        let kept = todays.filter { stats[$0.id]?.keptToday == true }
        let all = kept.count == todays.count
        return VStack(spacing: LMSpace.xs) {
            HabitsSkyView(habits: todays, keptIDs: Set(kept.map(\.id)),
                          streaks: stats.mapValues(\.currentDays))
                .frame(height: 210)
            Text(all ? String(localized: "Every habit kept. Your sky is ablaze.")
                     : String(localized: "\(kept.count) of \(todays.count) kept today"))
                .font(LMFont.voice(.title2))
                .foregroundStyle(all ? LMColor.reward : LMColor.textPrimary)
                .multilineTextAlignment(.center)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity)
            if let best = todays.compactMap({ h in stats[h.id].map { (h, $0) } }).max(by: { $0.1.currentDays < $1.1.currentDays }),
               best.1.current > 1 {
                Text("Brightest: \(best.0.title) · \(HabitFormat.streak(best.1))")
                    .font(LMFont.footnote)
                    .foregroundStyle(LMColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, LMSpace.s)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("habits.hero")
    }

    // MARK: Sections

    private func section(_ title: String, color: Color, habits: [Habit], stats: [UUID: HabitStats]) -> some View {
        VStack(alignment: .leading, spacing: LMSpace.xs) {
            EyebrowText(title, color: color)
                .accessibilityAddTraits(.isHeader)
            ForEach(habits) { habit in
                if let s = stats[habit.id] {
                    HabitRow(habit: habit, stats: s, burst: bursts[habit.id] ?? 0,
                             onToggle: { toggle(habit) },
                             onOpen: { path.append(habit.id) },
                             onFocus: { app.requestHabitFocus(habit.id) })
                }
            }
        }
    }

    private func restingSection(_ habits: [Habit]) -> some View {
        VStack(alignment: .leading, spacing: LMSpace.xs) {
            Button {
                withAnimation(LMSpring.settle) { showResting.toggle() }
            } label: {
                HStack {
                    EyebrowText(String(localized: "Archived"))
                    Text("\(habits.count)").font(LMFont.eyebrow.monospacedDigit()).foregroundStyle(LMColor.textTertiary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(LMColor.textTertiary)
                        .rotationEffect(.degrees(showResting ? 0 : -90))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Archived, \(habits.count)"))
            if showResting {
                ForEach(habits) { habit in
                    HStack(spacing: LMSpace.s) {
                        Image(systemName: habit.symbol).foregroundStyle(habit.hue.color).frame(width: 28)
                        Text(habit.title).font(LMFont.headline).foregroundStyle(LMColor.textSecondary).lineLimit(1)
                        Spacer()
                        Button(String(localized: "Restore")) { app.habits.setArchived(habit, false) }
                            .font(LMFont.callout)
                            .frame(minHeight: 44)
                    }
                    .padding(.horizontal, LMSpace.m)
                    .glassCard(radius: LMRadius.row)
                }
            }
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: LMSpace.l) {
            VStack(spacing: LMSpace.s) {
                HabitStarView(symbol: "sparkle", hue: .work, streakDays: 30, kept: false, size: 72)
                    .padding(.bottom, LMSpace.s)
                Text("Small things, every day,\nbecome who you are.")
                    .font(LMFont.voice(.title))
                    .foregroundStyle(LMColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Each habit is a star. Keep it and it brightens; keep it for 66 days and it becomes a nova.")
                    .font(LMFont.body)
                    .foregroundStyle(LMColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: LMSpace.xs) {
                EyebrowText(String(localized: "Start from one of these"))
                FlowChips(templates: HabitTemplate.all) { editor = .new($0) }
            }
            CosmicButton(title: "Create your own", systemImage: "plus") { editor = .new(nil) }
                .accessibilityIdentifier("habits.create")
        }
        .padding(LMSpace.l)
        .readableColumn(560)
    }

    // MARK: Actions

    private func toggle(_ habit: Habit) {
        let kept = app.habits.toggleToday(habit)
        if kept {
            app.haptics.success()
            bursts[habit.id, default: 0] += 1
        } else {
            app.haptics.lightTap()
        }
    }
}

/// What the habit editor opens for.
enum HabitEditorTarget: Identifiable {
    case new(HabitTemplate?)
    case edit(Habit)

    var id: String {
        switch self {
        case let .new(template): "new." + (template?.id ?? "blank")
        case let .edit(habit): habit.id.uuidString
        }
    }
}

/// One habit: its star (tap to keep), name, how it stands, and this week.
struct HabitRow: View {
    var habit: Habit
    var stats: HabitStats
    var burst: Int
    var onToggle: () -> Void
    var onOpen: () -> Void
    var onFocus: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let focused = habit.isFocusLinked ? app.habits.focusedMinutesToday(for: habit) : nil
        HStack(spacing: LMSpace.s) {
            Button(action: onToggle) {
                HabitStarView(symbol: habit.symbol, hue: habit.hue, streakDays: stats.currentDays,
                              kept: stats.keptToday, size: 50, burst: burst)
                    .frame(width: 56, height: 56)
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(Text(habit.title))
            .accessibilityValue(Text(stats.keptToday ? "Kept today" : "Not kept yet"))
            .accessibilityHint(Text(stats.keptToday ? "Opens today again" : "Marks it kept for today"))
            .accessibilityAddTraits(stats.keptToday ? .isSelected : [])
            .accessibilityIdentifier("habit.toggle")

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(habit.title)
                            .font(LMFont.headline)
                            .foregroundStyle(LMColor.textPrimary)
                            .lineLimit(2)
                        if stats.current > 0, !typeSize.isAccessibilitySize {
                            Text(HabitFormat.shortStreak(stats.current, weeks: stats.countsWeeks))
                                .font(LMFont.footnote.weight(.semibold).monospacedDigit())
                                .foregroundStyle(LMColor.reward)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(LMColor.reward.opacity(0.12)))
                                .accessibilityHidden(true)
                        }
                    }
                    Text(HabitFormat.status(habit, stats: stats, focusedToday: focused, calendar: app.clock.calendar))
                        .font(LMFont.footnote)
                        .foregroundStyle(stats.atRisk ? LMColor.warm : LMColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let focused, habit.isFocusLinked, !stats.keptToday {
                        ProgressView(value: Double(min(focused, habit.focusMinutes)), total: Double(max(1, habit.focusMinutes)))
                            .tint(habit.hue.color)
                            .padding(.vertical, 2)
                    }
                    if !typeSize.isAccessibilitySize {
                        HabitWeekStrip(habit: habit, today: app.today, calendar: app.clock.calendar, compact: true)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens the habit"))
            .accessibilityIdentifier("habit.open")

            if habit.isFocusLinked, !stats.keptToday {
                Button(action: onFocus) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LMColor.starlightLabel)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(LMColor.starlightFill))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(Text("Focus on \(habit.title)"))
                .accessibilityIdentifier("habit.focus")
            }
        }
        .padding(.horizontal, LMSpace.s)
        .padding(.vertical, LMSpace.s)
        .glassCard(radius: LMRadius.row, tint: stats.keptToday ? LMColor.reward : nil)
        .animation(LMSpring.settle, value: stats.keptToday)
    }
}

/// Template chips that wrap onto as many lines as they need.
struct FlowChips: View {
    var templates: [HabitTemplate]
    var onPick: (HabitTemplate) -> Void

    var body: some View {
        WrapLayout(spacing: LMSpace.xs) {
            ForEach(templates) { template in
                Button { onPick(template) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: template.symbol).font(.footnote.weight(.semibold)).foregroundStyle(template.hue.color)
                        Text(template.title).font(LMFont.callout).foregroundStyle(LMColor.textPrimary)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(LMColor.textPrimary.opacity(0.05)))
                    .overlay(Capsule().strokeBorder(LMColor.hairline, lineWidth: 1))
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityIdentifier("habits.template.\(template.id)")
            }
        }
    }
}

/// Lays children out left to right, wrapping to new lines.
struct WrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + s.width > width { x = 0; y += line + spacing; line = 0 }
            x += s.width + spacing
            line = max(line, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(width, widest), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            line = max(line, s.height)
        }
    }
}
