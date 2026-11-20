import SwiftData
import SwiftUI

/// "Prepare your focus": duration orbs, intention, category, ambience, and
/// a live preview of the star this session will create.
struct FocusSetupView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<FocusTask> { !$0.isArchived && !$0.isCompleted }, sort: \FocusTask.lastUsedAt, order: .reverse)
    private var tasks: [FocusTask]
    @Query(filter: #Predicate<FocusTask> { $0.isPlanned && !$0.isArchived && !$0.isCompleted }, sort: \FocusTask.sortOrder)
    private var plannedTasks: [FocusTask]

    @State private var minutes = 25
    @State private var intention = ""
    @State private var category: FocusCategory = .work
    @State private var ambient: AmbientSound = .silence
    @State private var selectedTaskID: UUID?
    @State private var showCustom = false
    @State private var showTaskPicker = false
    @State private var loaded = false
    @State private var isStarting = false
    @State private var showTogether = false
    @State private var paywall: PlusFeature?
    @FocusState private var intentionFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        StatsReader { stats, _ in
            ZStack {
                CosmicBackgroundView(mood: .focus, light: 0.25)
                ScrollView {
                    VStack(alignment: .leading, spacing: LMSpace.l) {
                        topBar
                        preview(stats: stats)
                        durationSection
                        togetherRow
                        intentionSection
                        categorySection
                        if FeatureFlags.distractionShield, let shield = app.shield as? ScreenTimeShield {
                            SetupShieldSection(shield: shield)
                        }
                        ambientSection
                        Color.clear.frame(height: 90)
                    }
                    .padding(.horizontal, LMSpace.l)
                    .readableColumn()
                }
                .scrollDismissesKeyboard(.interactively)
                .statusBarScrim()
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    start()
                } label: {
                    HStack(spacing: LMSpace.s) {
                        if !typeSize.isAccessibilitySize { Image(systemName: "sparkle") }
                        Text("Start Creating · \(minutes) min")
                    }
                }
                .buttonStyle(CosmicButtonStyle(kind: .reward))
                .disabled(isStarting)
                .opacity(intentionFocused ? 0 : 1)
                .animation(LMSpring.settle, value: intentionFocused)
                .padding(.horizontal, LMSpace.l)
                .readableColumn()
                .padding(.bottom, LMSpace.xs)
                .accessibilityIdentifier("setup.start")
            }
        }
        .onAppear(perform: load)
        .task {
            let name = app.preferences.displayName
            app.pell.offer(.setup(name: name, offersShield: FeatureFlags.distractionShield && app.shield is ScreenTimeShield))
            let hour = app.clock.calendar.component(.hour, from: app.clock.now)
            if hour >= 23 || hour < 4 { app.pell.offer(.lateNight(name: name, day: app.today)) }
        }
        .onDisappear { if app.timer.state.phase == .idle { app.audio.stopAmbient() } }
        .plusPaywall($paywall, screen: "focus_setup")
        .sheet(isPresented: $showCustom) {
            CustomDurationSheet(minutes: $minutes)
                .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(320)])
        }
        .sheet(isPresented: $showTaskPicker) {
            TaskPickerSheet(tasks: plannedTasks, selectedID: selectedTaskID) { task in
                select(task)
                showTaskPicker = false
            }
            .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .telemetryScreen("focus_setup")
    }

    // MARK: Sections

    /// Focus together: same length and category, in one shared galaxy.
    private var togetherRow: some View {
        Button {
            app.haptics.selection()
            showTogether = true
        } label: {
            HStack(spacing: LMSpace.s) {
                Image(systemName: "person.2.fill").foregroundStyle(LMColor.calm)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Focus together").font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
                    Text("Share a galaxy with up to 7 friends while you focus.")
                        .font(LMFont.footnote).foregroundStyle(LMColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(LMColor.textTertiary)
            }
            .padding(LMSpace.m)
            .glassCard(radius: 22)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityIdentifier("setup.together")
        .sheet(isPresented: $showTogether) {
            TogetherSheet(minutes: minutes, category: category)
                .presentationDetents([.large])
        }
    }

    private var topBar: some View {
        ZStack {
            Text("Prepare your focus")
                .font(LMFont.headline)
                .foregroundStyle(LMColor.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button {
                    app.audio.stopAmbient()
                    app.timer.cancelPreparation()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(LMColor.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("Close"))
                .accessibilityIdentifier("setup.close")
                Spacer()
            }
        }
        .padding(.top, LMSpace.s)
    }

    private func preview(stats: ProgressStats) -> some View {
        VStack(spacing: LMSpace.xs) {
            GlowingCelestialBodyView(progress: min(1, Double(minutes) / 90), tint: category.color)
                .frame(height: 190)
                .animation(LMSpring.bloom, value: minutes)
            Text(previewTitle)
                .font(LMFont.title)
                .foregroundStyle(LMColor.textPrimary)
                .multilineTextAlignment(.center)
                .contentTransition(.numericText())
            Text("Brings today to \(stats.todayMinutes + minutes) of \(app.preferences.dailyGoalMinutes) min")
                .font(LMFont.callout.weight(.regular))
                .foregroundStyle(LMColor.textSecondary)
                .contentTransition(.numericText())
            SetupOdysseyLine(minutes: minutes)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .animation(LMSpring.bloom, value: minutes)
        .accessibilityElement(children: .combine)
    }

    private var previewTitle: String {
        let adjective: String = switch minutes {
        case ..<20: String(localized: "A small")
        case ..<40: String(localized: "A bright")
        case ..<60: String(localized: "A radiant")
        default: String(localized: "A brilliant")
        }
        return String(localized: "\(adjective) \(category.displayName) star · +\(minutes) light")
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: LMSpace.s) {
            EyebrowText(String(localized: "Duration"))
            if typeSize.isAccessibilitySize {
                // Larger orbs, three to a row.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3), spacing: LMSpace.s) {
                    durationOrbs(diameter: 100)
                }
            } else {
                // Full-size orbs where they fit; smaller ones on narrow iPhones.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) { durationOrbs(diameter: 72) }
                    HStack(spacing: 0) { durationOrbs(diameter: 60) }
                }
            }
        }
    }

    @ViewBuilder
    private func durationOrbs(diameter: CGFloat) -> some View {
        ForEach(FocusConfiguration.presetsMinutes, id: \.self) { preset in
            DurationOrb(minutes: preset, isSelected: minutes == preset, diameter: diameter) {
                app.haptics.selection()
                minutes = preset
            }
            .frame(maxWidth: .infinity)
        }
        DurationOrb(minutes: FocusConfiguration.presetsMinutes.contains(minutes) ? nil : minutes,
                    isSelected: !FocusConfiguration.presetsMinutes.contains(minutes), diameter: diameter) {
            app.haptics.selection()
            showCustom = true
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("setup.customDuration")
    }

    private var intentionSection: some View {
        VStack(alignment: .leading, spacing: LMSpace.s) {
            EyebrowText(String(localized: "Intention"))
            taskChoice
            TextField(String(localized: "What will you create?"), text: $intention)
                .font(LMFont.headline.weight(.medium))
                .foregroundStyle(LMColor.textPrimary)
                .focused($intentionFocused)
                .submitLabel(.done)
                .padding(.horizontal, 20)
                .frame(minHeight: 56)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(LMColor.textPrimary.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(intentionFocused ? LMColor.focus : LMColor.hairline, lineWidth: intentionFocused ? 1.5 : 1))
                .onChange(of: intention) { _, new in
                    if let id = selectedTaskID, (tasks + plannedTasks).first(where: { $0.id == id })?.title != new { selectedTaskID = nil }
                }
                .accessibilityIdentifier("setup.intention")

            let suggestions = tasks.prefix(6).filter { $0.title != intention }
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: LMSpace.xs) {
                        ForEach(Array(suggestions)) { task in
                            Button {
                                select(task)
                            } label: {
                                HStack(spacing: 6) {
                                    CategoryGlyph(category: task.category, size: 11)
                                    Text(task.title).font(LMFont.footnote).lineLimit(1)
                                }
                                .foregroundStyle(LMColor.textSecondary)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(Capsule().fill(LMColor.textPrimary.opacity(0.05)))
                            }
                            .buttonStyle(PressScaleStyle())
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private var selectedPlannedTask: FocusTask? {
        guard let id = selectedTaskID else { return nil }
        return plannedTasks.first { $0.id == id }
    }

    /// The chosen planned task, or a way to choose one when there are any.
    @ViewBuilder
    private var taskChoice: some View {
        if let task = selectedPlannedTask {
            let progress = task.progress
            HStack(spacing: LMSpace.s) {
                Button {
                    showTaskPicker = true
                } label: {
                    HStack(spacing: LMSpace.s) {
                        CategoryGlyph(category: task.category, size: 20)
                        VStack(alignment: .leading, spacing: 4) {
                            EyebrowText(String(localized: "From your tasks"), color: task.category.color)
                            Text(nextSessionText(progress))
                                .font(LMFont.callout)
                                .foregroundStyle(LMColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            TaskProgressDots(progress: progress, tint: task.category.color)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Task \(task.title), \(nextSessionText(progress))"))
                .accessibilityHint(Text("Choose a different task"))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("setup.selectedTask")
                Button {
                    app.haptics.selection()
                    selectedTaskID = nil
                    intention = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(LMColor.textTertiary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("Clear task"))
            }
            .padding(.leading, LMSpace.m)
            .padding(.trailing, LMSpace.xxs)
            .padding(.vertical, LMSpace.s)
            .glassCard(radius: 20, tint: task.category.color, border: task.category.color.opacity(0.35))
        } else if !plannedTasks.isEmpty {
            Button {
                app.haptics.selection()
                showTaskPicker = true
            } label: {
                HStack(spacing: LMSpace.s) {
                    Image(systemName: "checklist")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(LMColor.calm)
                        .accessibilityHidden(true)
                    Text("Choose from your tasks")
                        .font(LMFont.headline.weight(.medium))
                        .foregroundStyle(LMColor.textPrimary)
                    Spacer(minLength: 0)
                    Text("\(plannedTasks.count)")
                        .font(LMFont.callout.monospacedDigit())
                        .foregroundStyle(LMColor.textTertiary)
                        .accessibilityHidden(true)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(LMColor.textTertiary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, LMSpace.m)
                .frame(minHeight: 52)
                .glassCard(radius: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityHint(Text("\(plannedTasks.count) planned"))
            .accessibilityIdentifier("setup.chooseTask")
        }
    }

    /// "Session 3 of 4 for Essay draft".
    private func nextSessionText(_ progress: TaskProgress) -> String {
        let title = selectedPlannedTask?.title ?? intention
        let next = progress.sessionsDone + 1
        if progress.hasEstimate, next <= progress.estimate {
            return String(localized: "Session \(next) of \(progress.estimate) for \(title)")
        }
        return String(localized: "Session \(next) for \(title)")
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: LMSpace.s) {
            EyebrowText(String(localized: "Category"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LMSpace.xs) {
                    ForEach(FocusCategory.allCases) { c in
                        CategoryChip(category: c, isSelected: c == category) {
                            app.haptics.selection()
                            withAnimation(LMSpring.snap) { category = c }
                        }
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private var ambientSection: some View {
        VStack(alignment: .leading, spacing: LMSpace.s) {
            EyebrowText(String(localized: "Ambient sound"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LMSpace.xs) {
                    ForEach(AmbientSound.allCases) { sound in
                        let locked = sound.isPlus && !app.plus.isActive
                        SelectChip(title: sound.title,
                                   systemImage: locked ? "lock.fill" : sound == .silence ? "speaker.slash" : "waveform",
                                   isSelected: sound == ambient) {
                            app.haptics.selection()
                            guard !locked else { return paywall = .ambience }
                            ambient = sound
                            // Preview the chosen ambience; the session keeps it.
                            app.audio.setAmbient(sound, volume: app.preferences.ambientVolume)
                        }
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        let prefs = app.preferences
        // An active iOS Focus filter (e.g. "Work") presets category and ambience.
        let preset = FocusFilterPresetStore.standard.load()
        minutes = prefs.defaultFocusMinutes
        category = preset?.category ?? prefs.lastCategory
        ambient = (preset?.ambient ?? prefs.ambient).playable
        // Opened from a link that named a length or category.
        if let prefill = app.setupPrefill {
            app.setupPrefill = nil
            if let wanted = prefill.minutes { minutes = wanted }
            if let wanted = prefill.category { category = wanted }
        }
        // Started from the Tasks screen.
        if let id = app.setupTaskID {
            app.setupTaskID = nil
            if let task = app.tasks.fetch(id: id) { select(task) }
        }
    }

    private func select(_ task: FocusTask) {
        app.haptics.selection()
        intention = task.title
        category = task.category
        selectedTaskID = task.id
    }

    private func start() {
        guard !isStarting else { return }
        isStarting = true
        intentionFocused = false
        let prefs = app.preferences
        prefs.lastCategory = category
        prefs.ambient = ambient
        app.dataStore.save()
        let config = FocusConfiguration(plannedSeconds: minutes * 60, category: category,
                                        intention: intention.trimmingCharacters(in: .whitespacesAndNewlines),
                                        taskID: selectedTaskID)
        app.timer.start(config)
    }
}

/// Today's and upcoming planned tasks to focus on.
private struct TaskPickerSheet: View {
    var tasks: [FocusTask]
    var selectedID: UUID?
    var onPick: (FocusTask) -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        let sections = app.tasks.planner.arrange(tasks)
        NavigationStack {
            ZStack {
                LMColor.bgBase.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: LMSpace.s) {
                        ForEach([TaskSection.today, .upcoming]) { section in
                            if let rows = sections[section], !rows.isEmpty {
                                EyebrowText(section.title, color: section == .today ? LMColor.calm : LMColor.textTertiary)
                                    .padding(.top, LMSpace.s)
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(rows) { row($0) }
                            }
                        }
                    }
                    .padding(.horizontal, LMSpace.l)
                    .readableColumn()
                    .padding(.bottom, LMSpace.l)
                }
            }
            .navigationTitle(String(localized: "Choose a task"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationBackground(LMColor.bgBase)
    }

    private func row(_ task: FocusTask) -> some View {
        let progress = task.progress
        let selected = task.id == selectedID
        return Button {
            onPick(task)
        } label: {
            HStack(spacing: LMSpace.s) {
                CategoryGlyph(category: task.category, size: 18)
                VStack(alignment: .leading, spacing: 6) {
                    Text(task.title)
                        .font(LMFont.headline)
                        .foregroundStyle(LMColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: LMSpace.xs) {
                        TaskProgressDots(progress: progress, tint: task.category.color)
                        Text(TaskFormat.sessions(progress)).font(LMFont.footnote).foregroundStyle(LMColor.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(LMColor.focus)
                }
            }
            .padding(LMSpace.m)
            .frame(minHeight: 56)
            .glassCard(radius: LMRadius.row, border: selected ? LMColor.focus : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(task.title), \(task.category.displayName), \(TaskFormat.sessions(progress))"))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("taskPicker.row")
    }
}

private struct CustomDurationSheet: View {
    @Binding var minutes: Int
    @Environment(\.dismiss) private var dismiss
    @State private var value = 30

    var body: some View {
        VStack(spacing: LMSpace.m) {
            Text("Custom duration").font(LMFont.title).foregroundStyle(LMColor.textPrimary)
            Picker("Minutes", selection: $value) {
                ForEach(Array(stride(from: FocusConfiguration.customRangeMinutes.lowerBound,
                                     through: FocusConfiguration.customRangeMinutes.upperBound, by: 5)), id: \.self) {
                    Text("\($0) min").tag($0)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 150)
            CosmicButton(title: "Use \(value) minutes", height: 52) {
                minutes = value
                dismiss()
            }
        }
        .padding(LMSpace.l)
        .onAppear { value = max(5, (minutes / 5) * 5) }
        .presentationBackground(LMColor.bgRaised)
    }
}
