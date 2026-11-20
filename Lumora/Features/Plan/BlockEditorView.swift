import SwiftData
import SwiftUI
import UserNotifications

/// Add or edit a block of the day: what, when (start, length, end), its
/// category, and how it reminds you — minutes before, as it begins, or as
/// a real alarm. Every block is a planned task, so it also shows in Tasks.
struct BlockEditorView: View {
    /// The block being edited; nil adds one.
    let task: FocusTask?
    /// The day a new block goes on.
    var day: Date
    /// Where a new block starts (free time tapped in the planner); nil finds the next free slot.
    var suggestedStart: Date?
    /// An unscheduled task getting a time.
    var fromTask: FocusTask?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(filter: #Predicate<FocusTask> { $0.isPlanned && !$0.isArchived && $0.scheduledStart != nil })
    private var scheduled: [FocusTask]

    @State private var draft = TaskDraft()
    @State private var start = Date()
    @State private var minutes = DayPlanner.defaultMinutes
    @State private var reminders = PlanReminderSettings.standard
    @State private var notificationsDenied = false
    @State private var linkedTask: FocusTask?
    @State private var loaded = false
    @FocusState private var titleFocused: Bool

    init(task: FocusTask?, day: Date, suggestedStart: Date? = nil, fromTask: FocusTask? = nil) {
        self.task = task
        self.day = day
        self.suggestedStart = suggestedStart
        self.fromTask = fromTask
    }

    private var editing: FocusTask? { task ?? linkedTask }

    var body: some View {
        NavigationStack {
            ZStack {
                LMColor.bgBase.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: LMSpace.l) {
                        titleSection
                        timeSection
                        categorySection
                        remindersSection
                        if let editing { manageSection(editing) }
                    }
                    .padding(LMSpace.l)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(task == nil ? String(localized: "New block") : String(localized: "Edit block"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(task == nil ? String(localized: "Add") : String(localized: "Save")) { save() }
                        .fontWeight(.semibold)
                        .disabled(!draft.isValid)
                        .accessibilityIdentifier("blockEditor.save")
                }
            }
        }
        .tint(LMColor.focus)
        .onAppear(perform: load)
        .task { notificationsDenied = await app.notifications.authorizationStatus() == .denied }
    }

    // MARK: Sections

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: LMSpace.s) {
            EyebrowText(String(localized: "Block"))
            TextField(String(localized: "What will you do?"), text: $draft.title)
                .font(LMFont.headline.weight(.medium))
                .foregroundStyle(LMColor.textPrimary)
                .focused($titleFocused)
                .submitLabel(.done)
                .padding(.horizontal, 20)
                .frame(minHeight: 56)
                .planField(focused: titleFocused)
                .accessibilityIdentifier("blockEditor.title")
            if task == nil, linkedTask == nil, !draft.trimmedTitle.isEmpty || !candidates.isEmpty {
                suggestions
            }
        }
    }

    /// Unscheduled tasks that match what's typed: picking one gives that task the time.
    private var candidates: [FocusTask] {
        let typed = draft.trimmedTitle.localizedLowercase
        let open = app.tasks.unscheduledTasks()
        let matching = typed.isEmpty ? open : open.filter { $0.title.localizedLowercase.contains(typed) }
        return Array(matching.prefix(8))
    }

    @ViewBuilder
    private var suggestions: some View {
        let list = candidates
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("From your tasks")
                    .font(LMFont.footnote)
                    .foregroundStyle(LMColor.textTertiary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: LMSpace.xs) {
                        ForEach(list) { candidate in
                            Button {
                                app.haptics.selection()
                                link(candidate)
                            } label: {
                                HStack(spacing: 6) {
                                    CategoryGlyph(category: candidate.category, size: 12)
                                    Text(candidate.title).font(LMFont.callout).lineLimit(1)
                                }
                                .foregroundStyle(LMColor.textPrimary)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 40)
                                .background(Capsule().fill(LMColor.textPrimary.opacity(0.05)))
                                .overlay(Capsule().strokeBorder(LMColor.hairline, lineWidth: 1))
                            }
                            .buttonStyle(PressScaleStyle())
                            .accessibilityLabel(Text("Use the task \(candidate.title)"))
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private var timeSection: some View {
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))
        let planner = app.planner
        let others = scheduled.compactMap(\.planBlock)
        let clashes = planner.overlaps(start: start, minutes: minutes, excluding: editing?.id, in: others)
        return VStack(alignment: .leading, spacing: LMSpace.s) {
            EyebrowText(String(localized: "When"))
            VStack(alignment: .leading, spacing: LMSpace.m) {
                HStack(alignment: .firstTextBaseline, spacing: LMSpace.s) {
                    Text(PlanFormat.time(start))
                        .contentTransition(.numericText())
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(LMColor.textTertiary)
                    Text(PlanFormat.time(end))
                        .contentTransition(.numericText())
                        .foregroundStyle(LMColor.textSecondary)
                    Spacer(minLength: 0)
                    Text(LMFormat.minutes(minutes))
                        .font(LMFont.callout)
                        .foregroundStyle(LMColor.calm)
                        .contentTransition(.numericText())
                }
                .font(.system(.largeTitle, design: .rounded, weight: .light).monospacedDigit())
                .foregroundStyle(LMColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(PlanFormat.time(start)) to \(PlanFormat.time(end)), \(LMFormat.spokenMinutes(minutes))"))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: LMSpace.xs) {
                        ForEach(DayPlanner.durationPresets, id: \.self) { preset in
                            SelectChip(title: LMFormat.minutes(preset), isSelected: minutes == preset, tint: LMColor.calm) {
                                app.haptics.selection()
                                withAnimation(LMSpring.snap) { minutes = preset }
                            }
                        }
                    }
                }
                .scrollClipDisabled()
                .accessibilityIdentifier("blockEditor.durations")

                VStack(spacing: 0) {
                    DatePicker(String(localized: "Day"), selection: dayBinding, displayedComponents: .date)
                        .frame(minHeight: 48)
                    SettingsDivider()
                    DatePicker(String(localized: "Starts"), selection: $start.animation(LMSpring.snap), displayedComponents: .hourAndMinute)
                        .frame(minHeight: 48)
                        .accessibilityIdentifier("blockEditor.start")
                    SettingsDivider()
                    DatePicker(String(localized: "Ends"), selection: endBinding, displayedComponents: .hourAndMinute)
                        .frame(minHeight: 48)
                        .accessibilityIdentifier("blockEditor.end")
                }
                .font(LMFont.body)
                .foregroundStyle(LMColor.textPrimary)
            }
            .padding(LMSpace.m)
            .glassCard(radius: 22)

            if !clashes.isEmpty {
                Label {
                    Text(clashes.count == 1
                         ? String(localized: "Overlaps \(clashes[0].title) (\(PlanFormat.range(clashes[0])))")
                         : String(localized: "Overlaps \(clashes.count) blocks"))
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(LMFont.footnote)
                .foregroundStyle(LMColor.warm)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
            }
        }
        .animation(LMSpring.settle, value: clashes.map(\.id))
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: LMSpace.s) {
            EyebrowText(String(localized: "Category"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LMSpace.xs) {
                    ForEach(FocusCategory.allCases) { c in
                        CategoryChip(category: c, isSelected: c == draft.category) {
                            app.haptics.selection()
                            withAnimation(LMSpring.snap) { draft.category = c }
                        }
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: LMSpace.s) {
            EyebrowText(String(localized: "Reminders"))
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: LMSpace.s) {
                    Text("Before it begins")
                        .font(LMFont.body)
                        .foregroundStyle(LMColor.textPrimary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: LMSpace.xs) {
                            ForEach(PlanReminderSettings.leadOptions, id: \.self) { lead in
                                SelectChip(title: lead == 0 ? String(localized: "Off") : String(localized: "\(lead) min"),
                                           isSelected: reminders.beforeMinutes == lead) {
                                    app.haptics.selection()
                                    withAnimation(LMSpring.snap) { reminders.beforeMinutes = lead }
                                }
                                .accessibilityLabel(Text(lead == 0 ? String(localized: "No early reminder")
                                                         : String(localized: "\(lead) minutes before")))
                            }
                        }
                    }
                    .scrollClipDisabled()
                    .accessibilityIdentifier("blockEditor.lead")
                }
                .padding(LMSpace.m)
                SettingsDivider()
                Toggle(isOn: $reminders.atStart.animation(LMSpring.snap)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("When it begins").font(LMFont.body).foregroundStyle(LMColor.textPrimary)
                        Text("A notification with Begin focus")
                            .font(LMFont.footnote)
                            .foregroundStyle(LMColor.textSecondary)
                    }
                }
                .padding(.horizontal, LMSpace.m)
                .frame(minHeight: 60)
                .accessibilityIdentifier("blockEditor.atStart")
                if app.planAlarms.isSupported {
                    SettingsDivider()
                    Toggle(isOn: $reminders.alarm.animation(LMSpring.snap)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label {
                                Text("Ring as an alarm")
                            } icon: {
                                Image(systemName: "alarm.fill").foregroundStyle(LMColor.reward)
                            }
                            .font(LMFont.body)
                            .foregroundStyle(LMColor.textPrimary)
                            Text(app.planAlarms.access == .denied
                                 ? String(localized: "Alarms are off for Orbi. You can allow them in Settings.")
                                 : String(localized: "Rings like a clock alarm, even in Silent mode or a Focus."))
                                .font(LMFont.footnote)
                                .foregroundStyle(LMColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, LMSpace.m)
                    .frame(minHeight: 64)
                    .accessibilityIdentifier("blockEditor.alarm")
                }
            }
            .glassCard(radius: 22)
            if notificationsDenied, reminders.beforeMinutes > 0 || reminders.atStart {
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Label(String(localized: "Notifications are off for Orbi. Turn them on in Settings."),
                          systemImage: "bell.slash")
                        .font(LMFont.footnote)
                        .foregroundStyle(LMColor.warm)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func manageSection(_ task: FocusTask) -> some View {
        VStack(spacing: LMSpace.s) {
            CosmicButton(title: task.isCompleted ? "Reopen" : "Mark as lit",
                         systemImage: task.isCompleted ? "arrow.uturn.backward" : "sparkle",
                         kind: .secondary, height: 52) {
                app.tasks.setCompleted(task, !task.isCompleted)
                dismiss()
            }
            .accessibilityIdentifier("blockEditor.toggleLit")
            if self.task != nil {
                CosmicButton(title: "Keep as a task, without a time", systemImage: "clock.badge.xmark",
                             kind: .ghost, height: 48) {
                    app.tasks.unschedule(task)
                    dismiss()
                }
                CosmicButton(title: "Delete block", systemImage: "trash", kind: .ghost, height: 48) {
                    app.tasks.archive(task)
                    dismiss()
                }
                .foregroundStyle(LMColor.warm)
                .accessibilityIdentifier("blockEditor.delete")
                Text("Its focus sessions and stars stay in your universe.")
                    .font(LMFont.footnote)
                    .foregroundStyle(LMColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, LMSpace.s)
    }

    // MARK: Bindings

    /// Changing the day keeps the time of day.
    private var dayBinding: Binding<Date> {
        Binding {
            start
        } set: { newDay in
            let cal = app.clock.calendar
            let time = cal.dateComponents([.hour, .minute], from: start)
            start = cal.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: newDay) ?? newDay
        }
    }

    /// Setting the end sets the length; an end before the start runs past midnight.
    private var endBinding: Binding<Date> {
        Binding {
            start.addingTimeInterval(TimeInterval(minutes * 60))
        } set: { newEnd in
            let cal = app.clock.calendar
            let s = cal.dateComponents([.hour, .minute], from: start), e = cal.dateComponents([.hour, .minute], from: newEnd)
            let startMinute = (s.hour ?? 0) * 60 + (s.minute ?? 0), endMinute = (e.hour ?? 0) * 60 + (e.minute ?? 0)
            let length = (endMinute - startMinute + 1440) % 1440
            guard length >= BlockSchedule.minuteRange.lowerBound else { return }
            withAnimation(LMSpring.snap) { minutes = min(BlockSchedule.minuteRange.upperBound, length) }
        }
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let task {
            fill(from: task)
        } else if let fromTask {
            link(fromTask)
        } else {
            draft.category = app.preferences.lastCategory
            reminders = .lastUsed
            minutes = DayPlanner.defaultMinutes
            start = suggestedStart ?? app.planner.suggestedStart(on: day, minutes: minutes, among: scheduled.compactMap(\.planBlock))
            titleFocused = true
        }
    }

    private func fill(from task: FocusTask) {
        draft = TaskDraft(task)
        if let schedule = draft.schedule {
            start = schedule.start
            minutes = schedule.minutes
            reminders = schedule.reminders
        }
    }

    /// Plan an existing task instead of creating a new one.
    private func link(_ candidate: FocusTask) {
        linkedTask = candidate
        let keepStart = loaded && task == nil ? start : nil
        draft = TaskDraft(candidate)
        reminders = .lastUsed
        // The task's estimate becomes the block's length: three sessions, about 90 minutes.
        if candidate.estimatedSessions > 0 {
            let focus = app.preferences.defaultFocusMinutes
            let raw = candidate.estimatedSessions * focus + (candidate.estimatedSessions - 1) * 5
            minutes = min(BlockSchedule.minuteRange.upperBound, Int((Double(raw) / 15).rounded(.up)) * 15)
        }
        let blocks = scheduled.compactMap(\.planBlock)
        if let keepStart, fromTask == nil {
            start = keepStart
        } else {
            start = suggestedStart ?? app.planner.suggestedStart(on: day, minutes: minutes, among: blocks)
        }
        titleFocused = false
    }

    private func save() {
        guard draft.isValid else { return }
        let isNew = editing == nil || editing?.scheduledStart == nil
        draft.schedule = BlockSchedule(start: start, minutes: minutes, reminders: reminders)
        if isNew, editing == nil {
            draft.estimatedSessions = DayPlanner.estimatedSessions(minutes: minutes, focusMinutes: app.preferences.defaultFocusMinutes)
        }
        PlanReminderSettings.lastUsed = reminders
        if let editing {
            app.tasks.update(editing, with: draft)
        } else {
            app.tasks.create(draft)
        }
        Telemetry.log(.planBlockSaved(isNew: isNew, minutes: minutes, reminderMinutes: reminders.beforeMinutes,
                                      atStart: reminders.atStart, alarm: reminders.alarm))
        app.haptics.selection()
        let wantsNotifications = reminders.beforeMinutes > 0 || reminders.atStart
        let wantsAlarm = reminders.alarm
        let notifications = app.notifications, alarms = app.planAlarms
        Task { @MainActor [app] in
            var changed = false
            if wantsNotifications, await notifications.authorizationStatus() == .notDetermined {
                changed = await notifications.requestAuthorization(source: "plan")
            }
            if wantsAlarm, alarms.access == .notDetermined {
                changed = await alarms.requestAuthorization() || changed
            }
            if changed { app.syncPlan() }
        }
        dismiss()
    }
}
