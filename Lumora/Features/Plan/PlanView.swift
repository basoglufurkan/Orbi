import SwiftData
import SwiftUI

/// Plan: the day ahead in one calm place. Today's orbit (the hour-by-hour
/// plan) leads, today's habits wait as stars to keep in a tap, and the tasks
/// for today sit below with a session one tap away. Each section opens its
/// full screen, so Today keeps the sky to itself.
struct PlanView: View {
    @Environment(AppModel.self) private var app
    @State private var path: [UUID] = []
    @State private var habitEditor: HabitEditorTarget?
    @State private var taskEditor: PlanTaskTarget?
    @State private var addingBlock = false

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                CosmicBackgroundView(mood: .home, light: 0.35, starOpacity: 0.6)
                ScrollView {
                    VStack(alignment: .leading, spacing: LMSpace.l) {
                        header
                        PlanOrbitSection()
                        PlanHabitsSection(onOpen: { path.append($0) }, onEdit: { habitEditor = .edit($0) })
                        PlanTasksSection(onEdit: { taskEditor = .edit($0) }, onNew: { taskEditor = .new })
                        Color.clear.frame(height: 76)
                    }
                    .padding(.horizontal, LMSpace.l)
                    .readableColumn()
                }
                .scrollIndicators(.hidden)
                .statusBarScrim()
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let habit = app.habits.fetch(id: id) {
                    HabitDetailView(habit: habit) { habitEditor = .edit(habit) }
                        // Clear of the orbit bar that floats over every tab.
                        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 64) }
                }
            }
        }
        .tint(LMColor.focus)
        // A habit deleted from its editor takes its page with it.
        .sheet(item: $habitEditor, onDismiss: { path.removeAll { app.habits.fetch(id: $0) == nil } }) { target in
            HabitEditorView(target: target)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
        .sheet(item: $taskEditor) { target in
            TaskEditorView(task: target.task)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
        .sheet(isPresented: $addingBlock) {
            BlockEditorView(task: nil, day: app.clock.calendar.startOfDay(for: app.clock.now))
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
    }

    // MARK: Header

    private var header: some View {
        // Reading `today` turns the date over at midnight.
        let _ = app.today
        return HStack(alignment: .top, spacing: LMSpace.s) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Plan")
                    .font(LMFont.largeTitle)
                    .foregroundStyle(LMColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(app.clock.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(LMFont.callout.weight(.regular))
                    .foregroundStyle(LMColor.textSecondary)
            }
            Spacer(minLength: LMSpace.s)
            addMenu
        }
        .padding(.top, LMSpace.m)
    }

    /// One place to add anything the day holds.
    private var addMenu: some View {
        Menu {
            Button { addingBlock = true } label: {
                Label(String(localized: "Add a block"), systemImage: "calendar.badge.plus")
            }
            Button { taskEditor = .new } label: {
                Label(String(localized: "New task"), systemImage: "checklist")
            }
            Button { habitEditor = .new(nil) } label: {
                Label(String(localized: "New habit"), systemImage: "sparkles")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LMColor.textPrimary)
                .frame(width: 44, height: 44)
                .glassCard(radius: 22)
        }
        .accessibilityLabel(Text("Add to your plan"))
        .accessibilityIdentifier("plan.add")
    }
}

/// What the task editor opens for on Plan.
private enum PlanTaskTarget: Identifiable {
    case new
    case edit(FocusTask)

    var id: String {
        switch self {
        case .new: "new"
        case let .edit(task): task.id.uuidString
        }
    }

    var task: FocusTask? {
        if case let .edit(task) = self { return task }
        return nil
    }
}

// MARK: - Sections

/// A section's title row: its name, how it stands, and where it leads.
private struct PlanSectionHeader: View {
    var title: String
    var detail: String?
    var detailColor: Color = LMColor.textSecondary
    var link: String?
    var linkID = ""
    var onLink: () -> Void = {}

    @Environment(AppModel.self) private var app

    var body: some View {
        // One line where it fits; otherwise how it stands moves under the
        // title, and at the largest sizes everything gets a line of its own.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: LMSpace.xs) {
                titleText
                detailText
                Spacer(minLength: LMSpace.xs)
                linkButton
            }
            .frame(minHeight: 44)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: LMSpace.xs) {
                    titleText
                    Spacer(minLength: LMSpace.xs)
                    linkButton
                }
                .frame(minHeight: 44)
                detailText
                    .padding(.bottom, LMSpace.xs)
            }
            VStack(alignment: .leading, spacing: LMSpace.xxs) {
                titleText
                detailText
                linkButton
            }
            .padding(.top, LMSpace.xs)
        }
    }

    private var titleText: some View {
        EyebrowText(title, color: LMColor.calm)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var detailText: some View {
        if let detail {
            Text(detail)
                .font(LMFont.footnote.monospacedDigit())
                .foregroundStyle(detailColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText())
        }
    }

    @ViewBuilder
    private var linkButton: some View {
        if let link {
            Button {
                app.haptics.selection()
                onLink()
            } label: {
                HStack(spacing: 3) {
                    Text(link)
                    Image(systemName: "chevron.forward").font(.caption2.weight(.bold))
                }
                .font(LMFont.footnote.weight(.semibold))
                .foregroundStyle(LMColor.focus)
                .lineLimit(1)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(linkID)
        }
    }
}

/// An empty section's invitation: a dashed orb, what to do, and a plus.
private struct PlanInvitation: View {
    var title: String
    var detail: String
    var symbol: String
    var tint: Color
    var id: String
    var action: () -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            app.haptics.selection()
            action()
        } label: {
            HStack(spacing: LMSpace.s) {
                ZStack {
                    Circle().strokeBorder(tint.opacity(0.6), style: StrokeStyle(lineWidth: 1.25, dash: [2, 4]))
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(LMFont.headline)
                        .foregroundStyle(LMColor.textPrimary)
                    Text(detail)
                        .font(LMFont.footnote)
                        .foregroundStyle(LMColor.textSecondary)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LMColor.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, LMSpace.m)
            .padding(.vertical, LMSpace.s)
            .glassCard(radius: 22)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityIdentifier(id)
    }
}

/// Today's orbit: what's now or next, and the day's route at a glance.
private struct PlanOrbitSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        // Reading `today` moves the orbit to the new day at midnight.
        let _ = app.today
        DayPlanReader { scheduled in
            let blocks = scheduled.filter { task in
                task.scheduledStart.map { app.clock.calendar.isDate($0, inSameDayAs: app.clock.now) } ?? false
            }.compactMap(\.planBlock)
            let lit = blocks.filter(\.isCompleted).count
            VStack(alignment: .leading, spacing: LMSpace.xxs) {
                PlanSectionHeader(title: String(localized: "Today's orbit"),
                                  detail: blocks.isEmpty ? nil : String(localized: "\(lit) of \(blocks.count) lit"),
                                  detailColor: LMColor.reward,
                                  link: blocks.isEmpty ? nil : String(localized: "Plan your day"),
                                  linkID: "plan.planner") { app.isShowingPlanner = true }
                DayOrbitCard(blocks: blocks)
            }
        }
    }
}

/// Today's habits as stars: tap a star to keep it, its name to open it.
private struct PlanHabitsSection: View {
    var onOpen: (UUID) -> Void
    var onEdit: (Habit) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var bursts: [UUID: Int] = [:]

    var body: some View {
        HabitsReader { habits in
            let today = app.today, calendar = app.clock.calendar
            let stats = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0.stats(today: today, calendar: calendar)) })
            let todays = habits.filter { stats[$0.id].map { $0.dueToday || $0.keptToday } ?? false }
            let kept = todays.filter { stats[$0.id]?.keptToday == true }.count
            let allKept = !todays.isEmpty && kept == todays.count
            VStack(alignment: .leading, spacing: LMSpace.xxs) {
                PlanSectionHeader(title: String(localized: "Habits"),
                                  detail: todays.isEmpty ? nil : String(localized: "\(kept) of \(todays.count) kept today"),
                                  detailColor: allKept ? LMColor.reward : LMColor.textSecondary,
                                  link: habits.isEmpty ? nil : String(localized: "See all"),
                                  linkID: "plan.habits", onLink: openSheet)
                if habits.isEmpty {
                    PlanInvitation(title: String(localized: "Start a habit"),
                                   detail: String(localized: "Each one becomes a star that brightens."),
                                   symbol: "sparkles", tint: LMColor.reward, id: "plan.habitsInvite", action: openSheet)
                } else if todays.isEmpty {
                    restDay
                } else {
                    grid(todays, stats: stats, allKept: allKept)
                }
            }
        }
    }

    private func grid(_ habits: [Habit], stats: [UUID: HabitStats], allKept: Bool) -> some View {
        // Up to four in a row, as few rows as it takes, balanced.
        let perRow = typeSize.isAccessibilitySize ? 2
            : habits.count <= 4 ? habits.count : min(4, (habits.count + 1) / 2)
        return CenteredGrid(columns: max(1, perRow), spacing: LMSpace.xs) {
            ForEach(habits) { habit in
                if let s = stats[habit.id] {
                    PlanHabitTile(habit: habit, stats: s, burst: bursts[habit.id] ?? 0,
                                  onToggle: { toggle(habit) }, onOpen: { onOpen(habit.id) })
                        .contextMenu {
                            Button { onEdit(habit) } label: {
                                Label(String(localized: "Edit habit"), systemImage: "pencil")
                            }
                            if habit.isFocusLinked, !s.keptToday {
                                Button { app.requestHabitFocus(habit.id, source: "plan_tab") } label: {
                                    Label(String(localized: "Focus on \(habit.title)"), systemImage: "play.fill")
                                }
                            }
                        }
                }
            }
        }
        .padding(.horizontal, LMSpace.xs)
        .padding(.vertical, LMSpace.s)
        .glassCard(radius: 22, tint: allKept ? LMColor.reward : nil)
    }

    private var restDay: some View {
        HStack(spacing: LMSpace.s) {
            Image(systemName: "moon.stars")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LMColor.calm)
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Rest day").font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
                Text("Rest is part of the light.").font(LMFont.footnote).foregroundStyle(LMColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LMSpace.m)
        .padding(.vertical, LMSpace.s)
        .glassCard(radius: 22)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plan.habitsRest")
    }

    private func openSheet() {
        app.habitsSource = "plan_tab"
        app.isShowingHabits = true
    }

    private func toggle(_ habit: Habit) {
        if app.habits.toggleToday(habit, source: "plan_tab") {
            app.haptics.success()
            bursts[habit.id, default: 0] += 1
        } else {
            app.haptics.lightTap()
        }
    }
}

/// Equal columns filled row by row, with a short last row centred under the
/// others, so a handful of stars never leans to one side.
private struct CenteredGrid: Layout {
    var columns: Int
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? CGFloat(columns) * 80
        let cell = width / CGFloat(columns)
        let heights = rows(subviews.count).map { row in rowHeight(row, cell: cell, subviews: subviews) }
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cell = bounds.width / CGFloat(columns)
        var y = bounds.minY
        for row in rows(subviews.count) {
            let height = rowHeight(row, cell: cell, subviews: subviews)
            let inset = CGFloat(columns - row.count) * cell / 2
            for (k, index) in row.enumerated() {
                subviews[index].place(at: CGPoint(x: bounds.minX + inset + CGFloat(k) * cell, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(width: cell, height: height))
            }
            y += height + spacing
        }
    }

    private func rows(_ count: Int) -> [Range<Int>] {
        stride(from: 0, to: count, by: columns).map { $0..<min(count, $0 + columns) }
    }

    private func rowHeight(_ row: Range<Int>, cell: CGFloat, subviews: Subviews) -> CGFloat {
        row.map { subviews[$0].sizeThatFits(ProposedViewSize(width: cell, height: nil)).height }.max() ?? 0
    }
}

/// One habit on Plan: its star (tap to keep) over its name and its run.
private struct PlanHabitTile: View {
    var habit: Habit
    var stats: HabitStats
    var burst: Int
    var onToggle: () -> Void
    var onOpen: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HabitStarView(symbol: habit.symbol, hue: habit.hue, streakDays: stats.currentDays,
                              kept: stats.keptToday, size: 38, burst: burst)
                    .frame(width: 56, height: 56)
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(Text(habit.title))
            .accessibilityValue(Text(stats.keptToday ? "Kept today" : "Not kept yet"))
            .accessibilityHint(Text(stats.keptToday ? "Opens today again" : "Marks it kept for today"))
            .accessibilityAddTraits(stats.keptToday ? .isSelected : [])
            .accessibilityIdentifier("plan.habit")

            Button(action: onOpen) {
                VStack(spacing: 2) {
                    Text(habit.title)
                        .font(LMFont.footnote)
                        .foregroundStyle(LMColor.textPrimary)
                        .lineLimit(1)
                    Text(stats.current > 0 ? HabitFormat.shortStreak(stats.current, weeks: stats.countsWeeks) : " ")
                        .font(LMFont.eyebrow.monospacedDigit())
                        .foregroundStyle(LMColor.reward)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(habit.title))
            .accessibilityHint(Text("Opens the habit"))
            .accessibilityIdentifier("plan.habitOpen")
        }
        .frame(maxWidth: .infinity)
        .animation(LMSpring.settle, value: stats.keptToday)
    }
}

/// Today's tasks (the ones not already a stop on today's orbit), each a
/// session away.
private struct PlanTasksSection: View {
    var onEdit: (FocusTask) -> Void
    var onNew: () -> Void

    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<FocusTask> { $0.isPlanned && !$0.isArchived }, sort: \FocusTask.sortOrder)
    private var tasks: [FocusTask]

    /// More than this and the rest wait behind "See all".
    private static let shown = 4

    var body: some View {
        // Reading `today` re-splits the list at midnight.
        let _ = app.today
        let calendar = app.clock.calendar, now = app.clock.now
        let todays = (app.tasks.planner.arrange(tasks)[.today] ?? []).filter { task in
            !(task.scheduledStart.map { calendar.isDate($0, inSameDayAs: now) } ?? false)
        }
        VStack(alignment: .leading, spacing: LMSpace.xxs) {
            PlanSectionHeader(title: String(localized: "Tasks"),
                              detail: todays.isEmpty ? nil : "\(todays.count)",
                              link: tasks.isEmpty ? nil : String(localized: "See all"),
                              linkID: "plan.tasks") { app.isShowingTasks = true }
            if tasks.isEmpty {
                PlanInvitation(title: String(localized: "Add a task"),
                               detail: String(localized: "Choose one when you begin, and watch its stars gather."),
                               symbol: "checklist", tint: LMColor.calm, id: "plan.tasksInvite", action: onNew)
            } else if todays.isEmpty {
                Text("Nothing planned for today. A quiet sky is fine, too.")
                    .font(LMFont.callout.weight(.regular))
                    .foregroundStyle(LMColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, LMSpace.xs)
            } else {
                VStack(spacing: LMSpace.xs) {
                    ForEach(todays.prefix(Self.shown)) { task in
                        TaskRow(task: task, now: now, calendar: calendar,
                                onOpen: { onEdit(task) },
                                onStart: {
                                    app.haptics.selection()
                                    app.beginFocus(taskID: task.id)
                                })
                            .contextMenu {
                                Button {
                                    withAnimation(LMSpring.settle) { app.tasks.setCompleted(task, true) }
                                    app.haptics.success()
                                } label: {
                                    Label(String(localized: "Done"), systemImage: "checkmark")
                                }
                                Button { onEdit(task) } label: {
                                    Label(String(localized: "Edit"), systemImage: "pencil")
                                }
                                Button {
                                    withAnimation(LMSpring.settle) { app.tasks.archive(task) }
                                } label: {
                                    Label(String(localized: "Archive"), systemImage: "archivebox")
                                }
                            }
                    }
                }
            }
        }
    }
}
