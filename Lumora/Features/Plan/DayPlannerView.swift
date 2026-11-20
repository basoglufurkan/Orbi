import SwiftData
import SwiftUI

/// Plan your day: hour-by-hour blocks on a timeline. Free time between
/// blocks is a tap away from a new block, a "now" line keeps today honest,
/// rows reorder by dragging (the day re-flows around them), and every block
/// can begin a focus in one tap.
struct DayPlannerView: View {
    /// The day to open on; nil means today.
    var initialDay: Date?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.motionLevel) private var motion
    @Query(filter: #Predicate<FocusTask> { $0.isPlanned && !$0.isArchived && !$0.isCompleted }, sort: \FocusTask.sortOrder)
    private var openTasks: [FocusTask]

    @State private var day = Date()
    @State private var editor: BlockEditorTarget?
    @State private var editMode: EditMode = .inactive
    @State private var loaded = false

    private static let daysShown = 7

    var body: some View {
        NavigationStack {
            ZStack {
                LMColor.bgBase.ignoresSafeArea()
                DayPlanReader { scheduled in
                    let tasks = scheduled.filter { task in
                        task.scheduledStart.map { app.clock.calendar.isDate($0, inSameDayAs: day) } ?? false
                    }
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        let timeline = DayTimeline(blocks: tasks.compactMap(\.planBlock), now: app.clock.now)
                        list(tasks: tasks, all: scheduled, timeline: timeline)
                    }
                }
            }
            .navigationTitle(String(localized: "Plan your day"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                        .accessibilityIdentifier("planner.done")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(editMode.isEditing ? String(localized: "Finish") : String(localized: "Reorder")) {
                        withAnimation(LMSpring.settle) { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .accessibilityIdentifier("planner.reorder")
                    Button {
                        editor = .new(start: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("Add a block"))
                    .accessibilityIdentifier("planner.add")
                }
            }
            .environment(\.editMode, $editMode)
        }
        .tint(LMColor.focus)
        .sheet(item: $editor) { target in
            BlockEditorView(task: target.task, day: day, suggestedStart: target.start, fromTask: target.fromTask)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            day = app.clock.calendar.startOfDay(for: initialDay ?? app.clock.now)
        }
        .telemetryScreen("day_planner")
    }

    // MARK: List

    private func list(tasks: [FocusTask], all: [FocusTask], timeline: DayTimeline) -> some View {
        let isToday = app.clock.calendar.isDate(day, inSameDayAs: timeline.now)
        let unscheduled = openTasks.filter { $0.scheduledStart == nil }
        return List {
            Section {
                dayStrip(all: all)
                    .listRowInsets(EdgeInsets(top: LMSpace.xs, leading: 0, bottom: LMSpace.xs, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                if !tasks.isEmpty {
                    summary(timeline: timeline, isToday: isToday)
                        .plannerRow()
                }
            }

            Section {
                if tasks.isEmpty {
                    emptyDay(isToday: isToday)
                        .plannerRow()
                } else {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        if let block = task.planBlock {
                            VStack(spacing: 0) {
                                if isToday, nowLineBefore(index: index, timeline: timeline) {
                                    NowLine(now: timeline.now)
                                }
                                PlannerBlockRow(task: task, block: block, timeline: timeline,
                                                isFirst: index == 0, isLast: index == tasks.count - 1,
                                                onOpen: { editor = .edit(task) },
                                                onFocus: { focus(on: block) })
                                if index < tasks.count - 1, let next = tasks[index + 1].planBlock {
                                    GapRow(after: block, before: next) {
                                        editor = .new(start: block.end)
                                    }
                                } else if isToday, index == tasks.count - 1, timeline.now >= block.end {
                                    NowLine(now: timeline.now)
                                }
                            }
                            .background(alignment: .topLeading) {
                                if !typeSize.isAccessibilitySize {
                                    PlannerLine(isFirst: index == 0, isLast: index == tasks.count - 1)
                                }
                            }
                            .plannerRow()
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    withAnimation(LMSpring.bloom) { app.tasks.setCompleted(task, !task.isCompleted) }
                                    task.isCompleted ? app.haptics.success() : app.haptics.selection()
                                } label: {
                                    Label(task.isCompleted ? String(localized: "Reopen") : String(localized: "Light it"),
                                          systemImage: task.isCompleted ? "arrow.uturn.backward" : "sparkle")
                                }
                                .tint(task.isCompleted ? LMColor.focus : Color(hex: Palette.warmGold))
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    withAnimation(LMSpring.settle) { app.tasks.archive(task) }
                                } label: {
                                    Label(String(localized: "Delete"), systemImage: "trash")
                                }
                                Button {
                                    editor = .edit(task)
                                } label: {
                                    Label(String(localized: "Edit"), systemImage: "pencil")
                                }
                                .tint(LMColor.focus)
                            }
                        }
                    }
                    .onMove { source, destination in
                        let blocks = tasks.compactMap(\.planBlock)
                        withAnimation(LMSpring.settle) {
                            app.tasks.reschedule(DayPlanner.repack(blocks, moving: source, to: destination))
                        }
                        app.haptics.selection()
                    }
                }
            } header: {
                if !tasks.isEmpty {
                    EyebrowText(PlanFormat.day(day, now: timeline.now, calendar: app.clock.calendar), color: LMColor.calm)
                        .accessibilityAddTraits(.isHeader)
                }
            }

            if !unscheduled.isEmpty {
                Section {
                    taskShelf(unscheduled)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } header: {
                    EyebrowText(String(localized: "Give a task a time"))
                        .accessibilityAddTraits(.isHeader)
                }
            }

            Color.clear.frame(height: LMSpace.xl)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(LMSpring.settle, value: tasks.map(\.id))
        .accessibilityIdentifier("planner.list")
    }

    /// The "now" line goes above the first block that begins after now.
    private func nowLineBefore(index: Int, timeline: DayTimeline) -> Bool {
        let blocks = timeline.blocks
        guard index < blocks.count, blocks[index].start > timeline.now else { return false }
        return index == 0 || blocks[index - 1].start <= timeline.now
    }

    private func focus(on block: PlanBlock) {
        app.haptics.selection()
        app.requestPlanFocus(block.id, source: "planner")
    }

    // MARK: Day strip

    private func dayStrip(all: [FocusTask]) -> some View {
        let cal = app.clock.calendar
        let start = cal.startOfDay(for: app.clock.now)
        let days = (0..<Self.daysShown).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LMSpace.xs) {
                ForEach(days, id: \.self) { d in
                    let selected = cal.isDate(d, inSameDayAs: day)
                    let count = all.filter { $0.scheduledStart.map { cal.isDate($0, inSameDayAs: d) } ?? false }.count
                    Button {
                        app.haptics.selection()
                        withAnimation(LMSpring.snap) { day = d }
                    } label: {
                        VStack(spacing: 3) {
                            Text(cal.isDate(d, inSameDayAs: start) ? String(localized: "Today")
                                 : d.formatted(.dateTime.weekday(.abbreviated)))
                                .font(LMFont.eyebrow)
                                .lmTracking(0.8)
                                .foregroundStyle(selected ? LMColor.starlightLabel.opacity(0.8) : LMColor.textTertiary)
                            Text(d.formatted(.dateTime.day()))
                                .font(.system(.title3, design: .rounded, weight: .semibold).monospacedDigit())
                                .foregroundStyle(selected ? LMColor.starlightLabel : LMColor.textPrimary)
                            HStack(spacing: 2) {
                                ForEach(0..<min(count, 4), id: \.self) { _ in
                                    Circle().fill(selected ? LMColor.starlightLabel : LMColor.reward).frame(width: 4, height: 4)
                                }
                            }
                            .frame(height: 4)
                        }
                        .frame(minWidth: 52, minHeight: 64)
                        .padding(.horizontal, 4)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(selected ? LMColor.starlightFill : LMColor.textPrimary.opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(selected ? Color.clear : LMColor.hairline, lineWidth: 1))
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel(Text("\(d.formatted(.dateTime.weekday(.wide).day().month(.wide))), \(count) blocks"))
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, LMSpace.l)
        }
        .scrollClipDisabled()
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityIdentifier("planner.days")
    }

    // MARK: Summary

    private func summary(timeline: DayTimeline, isToday: Bool) -> some View {
        let late = timeline.blocks.filter { !$0.isCompleted && $0.start >= timeline.now }
        return AdaptiveStack(spacing: LMSpace.s) {
            VStack(alignment: .leading, spacing: 3) {
                Text(timeline.blocks.count == 1 ? String(localized: "1 block") : String(localized: "\(timeline.blocks.count) blocks"))
                    .font(LMFont.headline)
                    .foregroundStyle(LMColor.textPrimary)
                Text("\(LMFormat.minutes(timeline.plannedMinutes)) planned · \(timeline.litCount) lit")
                    .font(LMFont.footnote)
                    .foregroundStyle(LMColor.textSecondary)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            if isToday, !late.isEmpty {
                Menu {
                    Section(String(localized: "Push the rest of today")) {
                        ForEach(DayPlanner.lateOptions, id: \.self) { minutes in
                            Button(String(localized: "\(minutes) min later")) {
                                withAnimation(LMSpring.settle) {
                                    app.tasks.reschedule(app.planner.shifted(timeline.blocks, by: minutes))
                                }
                                Telemetry.log(.planShifted(minutes: minutes, blocks: late.count))
                                app.haptics.selection()
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text(String(localized: "Running late?"))
                    }
                        .font(LMFont.footnote.weight(.semibold))
                        .foregroundStyle(LMColor.calm)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(LMColor.calm.opacity(0.12)))
                }
                .accessibilityIdentifier("planner.late")
            }
        }
        .padding(LMSpace.m)
        .glassCard(radius: 22)
    }

    // MARK: Empty and shelf

    private func emptyDay(isToday: Bool) -> some View {
        VStack(spacing: LMSpace.m) {
            ZStack {
                Circle().strokeBorder(LMColor.textTertiary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [2, 6]))
                    .frame(width: 92, height: 92)
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(LMColor.focus)
            }
            .accessibilityHidden(true)
            Text(isToday ? String(localized: "Map today, hour by hour") : String(localized: "Map this day, hour by hour"))
                .font(LMFont.voice(.title2))
                .foregroundStyle(LMColor.textPrimary)
                .multilineTextAlignment(.center)
            Text("Add blocks like 09:00 Write the report or 14:00 Training. They become an orbit you can follow, with reminders when each one begins.")
                .font(LMFont.callout.weight(.regular))
                .foregroundStyle(LMColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            CosmicButton(title: "Add the first block", systemImage: "plus", height: 52) {
                editor = .new(start: nil)
            }
            .accessibilityIdentifier("planner.emptyAdd")
        }
        .padding(LMSpace.l)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    private func taskShelf(_ tasks: [FocusTask]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LMSpace.xs) {
                ForEach(tasks.prefix(12)) { task in
                    Button {
                        editor = .schedule(task)
                    } label: {
                        HStack(spacing: 8) {
                            CategoryGlyph(category: task.category, size: 14)
                            Text(task.title).font(LMFont.callout).foregroundStyle(LMColor.textPrimary).lineLimit(1)
                            Image(systemName: "clock.badge.plus").font(.footnote).foregroundStyle(LMColor.textTertiary)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(LMColor.textPrimary.opacity(0.05)))
                        .overlay(Capsule().strokeBorder(LMColor.hairline, lineWidth: 1))
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel(Text("Give \(task.title) a time"))
                }
            }
            .padding(.horizontal, LMSpace.l)
        }
        .scrollClipDisabled()
    }
}

/// What the block editor opens for.
enum BlockEditorTarget: Identifiable {
    case new(start: Date?)
    case edit(FocusTask)
    /// An existing unscheduled task, getting a time.
    case schedule(FocusTask)

    var id: String {
        switch self {
        case let .new(start): "new-\(start?.timeIntervalSinceReferenceDate ?? 0)"
        case let .edit(task): "edit-\(task.id.uuidString)"
        case let .schedule(task): "schedule-\(task.id.uuidString)"
        }
    }

    var task: FocusTask? {
        if case let .edit(task) = self { return task }
        return nil
    }

    var fromTask: FocusTask? {
        if case let .schedule(task) = self { return task }
        return nil
    }

    var start: Date? {
        if case let .new(start) = self { return start }
        return nil
    }
}

private extension View {
    func plannerRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: LMSpace.l, bottom: 0, trailing: LMSpace.l))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// One block on the planner's timeline: its times, a node on the line, and
/// a card with the title, length, reminders and a focus button.
struct PlannerBlockRow: View {
    let task: FocusTask
    let block: PlanBlock
    let timeline: DayTimeline
    var isFirst: Bool
    var isLast: Bool
    var onOpen: () -> Void
    var onFocus: () -> Void

    @Environment(\.editMode) private var editMode
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let status = timeline.status(of: block)
        HStack(alignment: .top, spacing: LMSpace.s) {
            if !typeSize.isAccessibilitySize {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(PlanFormat.time(block.start))
                        .font(LMFont.callout.monospacedDigit().weight(.semibold))
                        .foregroundStyle(status == .active ? LMColor.calm : LMColor.textPrimary)
                    Text(PlanFormat.time(block.end))
                        .font(LMFont.footnote.monospacedDigit())
                        .foregroundStyle(LMColor.textTertiary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: PlannerMetrics.timeColumn, alignment: .trailing)
                .padding(.top, LMSpace.m)
                .accessibilityHidden(true)

                PlanStopGlyph(status: status, category: block.category, size: 16)
                    .background(Circle().fill(LMColor.bgBase).padding(-3))
                    .padding(.top, PlannerMetrics.nodeTop - 8)
                    .frame(width: PlannerMetrics.nodeColumn)
                    .accessibilityHidden(true)
            }

            HStack(spacing: LMSpace.s) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 5) {
                        if typeSize.isAccessibilitySize {
                            Text(PlanFormat.range(block))
                                .font(LMFont.callout.monospacedDigit().weight(.semibold))
                                .foregroundStyle(status == .active ? LMColor.calm : LMColor.textSecondary)
                        }
                        Text(block.title)
                            .font(LMFont.headline)
                            .foregroundStyle(status == .lit || status == .passed ? LMColor.textSecondary : LMColor.textPrimary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                        meta(status: status)
                        if status == .active {
                            ProgressView(value: timeline.progress(of: block))
                                .tint(LMColor.calm)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(PlanFormat.spoken(block, in: timeline)))
                .accessibilityHint(Text("Opens the block"))
                .accessibilityAddTraits(.isButton)

                if status == .lit {
                    Image(systemName: "sparkle")
                        .font(.title3)
                        .foregroundStyle(LMColor.reward)
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)
                } else if editMode?.wrappedValue.isEditing != true {
                    Button(action: onFocus) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(status == .active ? LMColor.onAccent : LMColor.starlightLabel)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(status == .active ? LMColor.calm : LMColor.starlightFill))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel(Text("Focus on \(block.title)"))
                    .accessibilityIdentifier("planner.focus")
                }
            }
            .padding(.horizontal, LMSpace.m)
            .padding(.vertical, LMSpace.s)
            .glassCard(radius: LMRadius.row, tint: status == .active ? LMColor.calm : (status == .upcoming ? block.category.color : nil),
                       border: status == .active ? LMColor.calm.opacity(0.6) : nil)
            .padding(.vertical, 4)
        }
    }

    private func meta(status: PlanBlockStatus) -> some View {
        HStack(spacing: LMSpace.xs) {
            Text(LMFormat.minutes(block.minutes))
            if status == .active || status == .upcoming {
                Text("·")
                Text(PlanFormat.status(block, in: timeline))
                    .foregroundStyle(status == .active ? LMColor.calm : LMColor.textSecondary)
            }
            if task.remindBeforeMinutes > 0 || task.remindAtStart {
                Image(systemName: "bell.fill").font(.caption2)
            }
            if task.alarmAtStart {
                Image(systemName: "alarm.fill").font(.caption2)
            }
            if task.progress.sessionsDone > 0 {
                TaskProgressDots(progress: task.progress, tint: block.category.color, size: 6)
            }
        }
        .font(LMFont.footnote.monospacedDigit())
        .foregroundStyle(LMColor.textTertiary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// Free time between two blocks; tapping it plans a block there.
struct GapRow: View {
    var after: PlanBlock
    var before: PlanBlock
    var onAdd: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let gap = before.start.timeIntervalSince(after.end)
        if gap >= 10 * 60 {
            Button(action: onAdd) {
                HStack(spacing: LMSpace.s) {
                    if !typeSize.isAccessibilitySize {
                        Color.clear.frame(width: PlannerMetrics.timeColumn + LMSpace.s + PlannerMetrics.nodeColumn)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                        Text("\(PlanFormat.span(gap)) free")
                    }
                    .font(LMFont.footnote)
                    .foregroundStyle(LMColor.textTertiary)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(LMFormat.spokenMinutes(Int(gap / 60))) free. Add a block here"))
        } else if gap < 0 {
            HStack(spacing: 6) {
                if !typeSize.isAccessibilitySize {
                    Color.clear.frame(width: PlannerMetrics.timeColumn + PlannerMetrics.nodeColumn + LMSpace.s * 2 - 6)
                }
                Image(systemName: "exclamationmark.triangle")
                Text("Overlaps the next block")
                Spacer(minLength: 0)
            }
            .font(LMFont.footnote)
            .foregroundStyle(LMColor.warm)
            .frame(minHeight: 28)
        }
    }
}

/// Where now falls on today's timeline.
struct NowLine: View {
    var now: Date
    @Environment(\.motionLevel) private var motion
    @State private var pulse = false

    var body: some View {
        HStack(spacing: LMSpace.s) {
            Text(PlanFormat.time(now))
                .font(LMFont.footnote.monospacedDigit().weight(.semibold))
                .foregroundStyle(LMColor.calm)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: PlannerMetrics.timeColumn, alignment: .trailing)
            Circle()
                .fill(LMColor.calm)
                .frame(width: 8, height: 8)
                .background(Circle().fill(LMColor.calm.opacity(0.4)).scaleEffect(pulse ? 2.4 : 1).opacity(pulse ? 0 : 1))
                .frame(width: PlannerMetrics.nodeColumn)
            Rectangle().fill(LinearGradient(colors: [LMColor.calm, LMColor.calm.opacity(0)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1.5)
        }
        .padding(.vertical, 6)
        .onAppear {
            guard motion.animatesContinuously else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Now, \(PlanFormat.time(now))"))
    }
}

/// The planner timeline's columns.
enum PlannerMetrics {
    static let timeColumn: CGFloat = 62
    static let nodeColumn: CGFloat = 20
    /// From a block row's top to its node's centre.
    static let nodeTop: CGFloat = LMSpace.m + 10
    static var lineX: CGFloat { timeColumn + LMSpace.s + nodeColumn / 2 }
}

/// The timeline's spine behind one cell: it starts at the first node and
/// fades out after the last.
struct PlannerLine: View {
    var isFirst: Bool
    var isLast: Bool

    var body: some View {
        let color = LMColor.textTertiary.opacity(0.35)
        Rectangle()
            .fill(isLast ? AnyShapeStyle(LinearGradient(colors: [color, color.opacity(0)], startPoint: .top, endPoint: .bottom))
                         : AnyShapeStyle(color))
            .frame(width: 1.5)
            .padding(.top, isFirst ? PlannerMetrics.nodeTop : 0)
            .offset(x: PlannerMetrics.lineX - 0.75)
            .accessibilityHidden(true)
    }
}
