import SwiftUI

/// Add or edit a habit: its name, symbol and colour, how often, whether
/// focus keeps it, and a reminder. Editing also offers archive and delete.
struct HabitEditorView: View {
    let target: HabitEditorTarget

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft = HabitDraft()
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var showAllSymbols = false
    @FocusState private var titleFocused: Bool

    private enum Kind: Hashable { case daily, days, weekly }

    private var habit: Habit? {
        if case let .edit(habit) = target { return habit }
        return nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LMColor.bgBase.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: LMSpace.l) {
                        preview
                        titleSection
                        lookSection
                        scheduleSection
                        focusSection
                        reminderSection
                        if let habit { manageSection(habit) }
                    }
                    .padding(LMSpace.l)
                    .readableColumn(640)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(habit == nil ? String(localized: "New habit") : String(localized: "Edit habit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(habit == nil ? String(localized: "Add") : String(localized: "Save")) { save() }
                        .fontWeight(.semibold)
                        .disabled(!draft.isValid)
                        .accessibilityIdentifier("habitEditor.save")
                }
            }
        }
        .tint(LMColor.focus)
        .onAppear(perform: load)
        .confirmationDialog(String(localized: "Delete this habit?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(String(localized: "Delete habit and its history"), role: .destructive) {
                if let habit { app.habits.delete(habit) }
                dismiss()
            }
        } message: {
            Text("Every day you kept it goes too. Archiving keeps the history.")
        }
    }

    // MARK: Sections

    private var preview: some View {
        HStack {
            Spacer()
            HabitStarView(symbol: draft.symbol, hue: draft.hue, streakDays: 21, kept: false, size: 72)
                .frame(width: 96, height: 96)
                .animation(LMSpring.bloom, value: draft.symbol)
            Spacer()
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: LMSpace.xs) {
            EyebrowText(String(localized: "Habit"))
            TextField(String(localized: "Read 20 pages"), text: $draft.title)
                .font(LMFont.headline)
                .focused($titleFocused)
                .submitLabel(.done)
                .padding(.horizontal, LMSpace.m)
                .frame(minHeight: 52)
                .glassCard(radius: 16, border: titleFocused ? LMColor.focus : nil)
                .accessibilityIdentifier("habitEditor.title")
        }
    }

    private var lookSection: some View {
        VStack(alignment: .leading, spacing: LMSpace.s) {
            EyebrowText(String(localized: "Symbol and colour"))
            let symbols = showAllSymbols ? HabitSymbols.all : Array(HabitSymbols.all.prefix(12))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(symbols, id: \.self) { symbol in
                    let selected = draft.symbol == symbol
                    Button {
                        withAnimation(LMSpring.snap) { draft.symbol = symbol }
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(selected ? draft.hue.color : LMColor.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selected ? draft.hue.color.opacity(0.15) : LMColor.textPrimary.opacity(0.04)))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(selected ? draft.hue.color : LMColor.hairline, lineWidth: selected ? 1.5 : 1))
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel(Text(symbol.replacingOccurrences(of: ".", with: " ")))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            if !showAllSymbols {
                Button(String(localized: "More symbols")) { withAnimation(LMSpring.settle) { showAllSymbols = true } }
                    .font(LMFont.callout)
                    .frame(minHeight: 44)
            }
            HStack(spacing: LMSpace.s) {
                ForEach(FocusCategory.allCases) { hue in
                    let selected = draft.hue == hue
                    Button {
                        withAnimation(LMSpring.snap) { draft.hue = hue }
                    } label: {
                        StarShape(points: hue.starPoints)
                            .fill(hue.color)
                            .frame(width: 22, height: 22)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(selected ? hue.color.opacity(0.18) : .clear))
                            .overlay(Circle().strokeBorder(selected ? hue.color : LMColor.hairline, lineWidth: selected ? 2 : 1))
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel(Text(hue.displayName))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var kind: Binding<Kind> {
        Binding {
            switch draft.cadence {
            case .daily: .daily
            case .weekdays: .days
            case .timesPerWeek: .weekly
            }
        } set: { kind in
            switch kind {
            case .daily: draft.cadence = .daily
            case .days: draft.cadence = .weekdays([2, 3, 4, 5, 6])
            case .weekly: draft.cadence = .timesPerWeek(3)
            }
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: LMSpace.s) {
            EyebrowText(String(localized: "How often"))
            CosmicSegmented(options: [(Kind.daily, String(localized: "Every day")),
                                      (Kind.days, String(localized: "Some days")),
                                      (Kind.weekly, String(localized: "Per week"))],
                            selection: kind)
            switch draft.cadence {
            case .daily:
                EmptyView()
            case let .weekdays(days):
                let cal = app.clock.calendar
                HStack(spacing: 4) {
                    ForEach(HabitCalendar(cal).orderedWeekdays, id: \.self) { weekday in
                        let on = days.contains(weekday)
                        Button {
                            var next = days
                            if on { next.remove(weekday) } else { next.insert(weekday) }
                            withAnimation(LMSpring.snap) { draft.cadence = .weekdays(next) }
                        } label: {
                            Text(cal.veryShortWeekdaySymbols[weekday - 1])
                                .font(LMFont.headline)
                                .foregroundStyle(on ? LMColor.starlightLabel : LMColor.textSecondary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Circle().fill(on ? LMColor.starlightFill : LMColor.textPrimary.opacity(0.05)))
                        }
                        .buttonStyle(PressScaleStyle())
                        .accessibilityLabel(Text(cal.weekdaySymbols[weekday - 1]))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                if days.isEmpty {
                    Text("Pick at least one day.").font(LMFont.footnote).foregroundStyle(LMColor.warm)
                }
            case let .timesPerWeek(n):
                Stepper(value: Binding { n } set: { draft.cadence = .timesPerWeek($0) }, in: HabitCadence.weeklyRange) {
                    Text(HabitFormat.cadence(draft.cadence, calendar: app.clock.calendar))
                        .font(LMFont.headline)
                        .foregroundStyle(LMColor.textPrimary)
                }
                .padding(.horizontal, LMSpace.m)
                .frame(minHeight: 52)
                .glassCard(radius: 16)
                Text("Any days you like. The streak counts weeks that reach it.")
                    .font(LMFont.footnote)
                    .foregroundStyle(LMColor.textTertiary)
            }
        }
    }

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: LMSpace.s) {
            EyebrowText(String(localized: "Focus"))
            Toggle(isOn: Binding { draft.focusMinutes > 0 } set: { on in
                withAnimation(LMSpring.settle) { draft.focusMinutes = on ? 20 : 0 }
            }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep it by focusing").font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
                    Text("Focus sessions count toward it, and it's kept by itself once you reach the minutes.")
                        .font(LMFont.footnote)
                        .foregroundStyle(LMColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(LMSpace.m)
            .glassCard(radius: 16)
            .accessibilityIdentifier("habitEditor.focusToggle")
            if draft.focusMinutes > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: LMSpace.xs) {
                        ForEach(HabitDraft.focusOptions, id: \.self) { minutes in
                            SelectChip(title: String(localized: "\(minutes) min"), isSelected: draft.focusMinutes == minutes,
                                       tint: LMColor.focus) { draft.focusMinutes = minutes }
                        }
                    }
                }
                .scrollClipDisabled()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: LMSpace.xs) {
                        SelectChip(title: String(localized: "Any focus"), systemImage: "sparkle",
                                   isSelected: draft.focusCategory == nil) { draft.focusCategory = nil }
                        ForEach(FocusCategory.allCases) { category in
                            CategoryChip(category: category, isSelected: draft.focusCategory == category) {
                                draft.focusCategory = category
                            }
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: LMSpace.s) {
            EyebrowText(String(localized: "Reminder"))
            VStack(spacing: 0) {
                Toggle(isOn: Binding { draft.reminderEnabled } set: { on in
                    withAnimation(LMSpring.settle) { draft.reminderEnabled = on }
                    if on { Task { await askForNotifications() } }
                }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remind me").font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
                        Text("Only on days it's still open.").font(LMFont.footnote).foregroundStyle(LMColor.textSecondary)
                    }
                }
                .padding(LMSpace.m)
                .accessibilityIdentifier("habitEditor.reminder")
                if draft.reminderEnabled {
                    Divider().overlay(LMColor.hairline)
                    DatePicker(String(localized: "Time"), selection: reminderTime, displayedComponents: .hourAndMinute)
                        .font(LMFont.headline)
                        .padding(.horizontal, LMSpace.m)
                        .frame(minHeight: 52)
                }
            }
            .glassCard(radius: 16)
        }
    }

    private var reminderTime: Binding<Date> {
        Binding {
            app.clock.calendar.date(bySettingHour: draft.reminderHour, minute: draft.reminderMinute, second: 0, of: app.clock.now) ?? app.clock.now
        } set: { date in
            let c = app.clock.calendar.dateComponents([.hour, .minute], from: date)
            draft.reminderHour = c.hour ?? 8
            draft.reminderMinute = c.minute ?? 0
        }
    }

    private func manageSection(_ habit: Habit) -> some View {
        VStack(spacing: LMSpace.s) {
            CosmicButton(title: habit.isArchived ? "Restore habit" : "Archive habit",
                         systemImage: habit.isArchived ? "arrow.uturn.backward" : "archivebox", kind: .secondary, height: 52) {
                app.habits.setArchived(habit, !habit.isArchived)
                dismiss()
            }
            Button(String(localized: "Delete habit"), role: .destructive) { confirmDelete = true }
                .font(LMFont.callout)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.top, LMSpace.s)
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch target {
        case let .new(template):
            draft = template.map(HabitDraft.init) ?? HabitDraft()
            if template == nil { titleFocused = true }
        case let .edit(habit):
            draft = HabitDraft(habit)
        }
    }

    private func save() {
        guard draft.isValid else { return }
        switch target {
        case let .new(template):
            app.habits.create(draft, template: template?.id)
            app.haptics.success()
        case let .edit(habit):
            app.habits.update(habit, with: draft)
        }
        dismiss()
    }

    private func askForNotifications() async {
        if await app.notifications.authorizationStatus() == .notDetermined {
            await app.notifications.requestAuthorization(source: "habit_reminder")
        }
    }
}
