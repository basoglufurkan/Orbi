import SwiftData
import SwiftUI

/// Add or edit a planned task: title, category, estimate, project, due day
/// and notes. Editing also offers done/reopen and archive.
struct TaskEditorView: View {
    /// nil adds a new task.
    let task: FocusTask?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<FocusTask> { $0.isPlanned && !$0.isArchived }) private var planned: [FocusTask]

    @State private var draft = TaskDraft()
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var loaded = false
    @FocusState private var titleFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            ZStack {
                LMColor.bgBase.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: LMSpace.l) {
                        if let task, task.progress.sessionsDone > 0 { progressCard(task) }
                        titleSection
                        categorySection
                        estimateSection
                        listSection
                        if draft.schedule != nil { scheduleSection } else { dueSection }
                        notesSection
                        if let task { manageSection(task) }
                    }
                    .padding(LMSpace.l)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(task == nil ? String(localized: "New task") : String(localized: "Edit task"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(task == nil ? String(localized: "Add") : String(localized: "Save")) { save() }
                        .fontWeight(.semibold)
                        .disabled(!draft.isValid)
                        .accessibilityIdentifier("taskEditor.save")
                }
            }
        }
        .tint(LMColor.focus)
        .onAppear(perform: load)
    }

    // MARK: Sections

    private func progressCard(_ task: FocusTask) -> some View {
        let progress = task.progress
        return HStack(spacing: LMSpace.s) {
            CategoryGlyph(category: task.category, size: 24)
            VStack(alignment: .leading, spacing: 6) {
                Text(TaskFormat.sessions(progress))
                    .font(LMFont.headline)
                    .foregroundStyle(LMColor.textPrimary)
                TaskProgressDots(progress: progress, tint: task.category.color, size: 9)
                Text("\(LMFormat.minutes(progress.focusedMinutes)) of focus so far")
                    .font(LMFont.footnote)
                    .foregroundStyle(LMColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(LMSpace.m)
        .glassCard(radius: 22, tint: task.category.color, border: task.category.color.opacity(0.35))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(TaskFormat.sessions(progress)), \(LMFormat.spokenMinutes(progress.focusedMinutes)) of focus so far"))
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: LMSpace.s) {
            EyebrowText(String(localized: "Task"))
            TextField(String(localized: "What would you like to create?"), text: $draft.title)
                .font(LMFont.headline.weight(.medium))
                .foregroundStyle(LMColor.textPrimary)
                .focused($titleFocused)
                .submitLabel(.done)
                .padding(.horizontal, 20)
                .frame(minHeight: 56)
                .fieldBackground(focused: titleFocused)
                .accessibilityIdentifier("taskEditor.title")
        }
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

    private var estimateSection: some View {
        let minutes = draft.estimatedSessions * app.preferences.defaultFocusMinutes
        return VStack(alignment: .leading, spacing: LMSpace.s) {
            EyebrowText(String(localized: "Estimate"))
            AdaptiveStack(spacing: LMSpace.s) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(draft.estimatedSessions == 1 ? String(localized: "1 session") : String(localized: "\(draft.estimatedSessions) sessions"))
                        .font(LMFont.headline)
                        .foregroundStyle(LMColor.textPrimary)
                        .contentTransition(.numericText())
                    Text("About \(LMFormat.minutes(minutes)) of focus")
                        .font(LMFont.footnote)
                        .foregroundStyle(LMColor.textSecondary)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Stepper(String(localized: "Sessions"), value: $draft.estimatedSessions.animation(LMSpring.snap),
                        in: TaskDraft.estimateRange)
                    .labelsHidden()
                    .accessibilityLabel(Text("Estimated sessions"))
                    .accessibilityValue(Text("\(draft.estimatedSessions)"))
                    .accessibilityIdentifier("taskEditor.estimate")
            }
            .padding(LMSpace.m)
            .glassCard(radius: 22)
        }
    }

    private var listSection: some View {
        let existing = Array(Set(planned.map(\.listName).filter { !$0.isEmpty })).sorted()
        return VStack(alignment: .leading, spacing: LMSpace.s) {
            EyebrowText(String(localized: "Project or list"))
            TextField(String(localized: "Optional, like “Thesis”"), text: $draft.listName)
                .font(LMFont.body)
                .foregroundStyle(LMColor.textPrimary)
                .submitLabel(.done)
                .padding(.horizontal, 20)
                .frame(minHeight: 52)
                .fieldBackground(focused: false)
                .accessibilityLabel(Text("Project or list"))
            if !existing.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: LMSpace.xs) {
                        ForEach(existing, id: \.self) { name in
                            SelectChip(title: name, systemImage: "tag", isSelected: draft.listName == name) {
                                app.haptics.selection()
                                draft.listName = draft.listName == name ? "" : name
                            }
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private var dueSection: some View {
        VStack(alignment: .leading, spacing: LMSpace.s) {
            EyebrowText(String(localized: "When"))
            VStack(spacing: 0) {
                Toggle(isOn: $hasDueDate.animation(LMSpring.settle)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Plan for a day").font(LMFont.body).foregroundStyle(LMColor.textPrimary)
                        Text(hasDueDate ? String(localized: "It moves to Today when the day comes")
                                        : String(localized: "Without a day it stays in Today"))
                            .font(LMFont.footnote)
                            .foregroundStyle(LMColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, LMSpace.m)
                .frame(minHeight: 60)
                .accessibilityIdentifier("taskEditor.hasDue")
                if hasDueDate {
                    SettingsDivider()
                    DatePicker(String(localized: "Day"), selection: $dueDate, displayedComponents: .date)
                        .font(LMFont.body)
                        .foregroundStyle(LMColor.textPrimary)
                        .padding(.horizontal, LMSpace.m)
                        .frame(minHeight: 56)
                        .accessibilityIdentifier("taskEditor.due")
                }
            }
            .glassCard(radius: 22)
        }
    }

    /// A block of a day plan: its time lives in the planner.
    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: LMSpace.s) {
            EyebrowText(String(localized: "When"))
            if let schedule = draft.schedule {
                let block = PlanBlock(id: task?.id ?? UUID(), title: draft.title, categoryRaw: draft.category.rawValue,
                                      start: schedule.start, minutes: schedule.minutes, isCompleted: false)
                HStack(spacing: LMSpace.s) {
                    Image(systemName: "clock").foregroundStyle(LMColor.calm)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(TaskFormat.due(block.start, now: app.clock.now, calendar: app.clock.calendar)) · \(PlanFormat.range(block))")
                            .font(LMFont.body.monospacedDigit())
                            .foregroundStyle(LMColor.textPrimary)
                        Text("On your day plan")
                            .font(LMFont.footnote)
                            .foregroundStyle(LMColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Button(String(localized: "Remove time")) {
                        withAnimation(LMSpring.settle) {
                            draft.schedule = nil
                            hasDueDate = true
                            dueDate = block.start
                        }
                    }
                    .font(LMFont.callout.weight(.semibold))
                    .accessibilityIdentifier("taskEditor.removeTime")
                }
                .padding(LMSpace.m)
                .glassCard(radius: 22)
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: LMSpace.s) {
            EyebrowText(String(localized: "Notes"))
            TextField(String(localized: "Anything to remember when you begin"), text: $draft.notes, axis: .vertical)
                .font(LMFont.body)
                .foregroundStyle(LMColor.textPrimary)
                .lineLimit(3...8)
                .padding(16)
                .fieldBackground(focused: false)
                .accessibilityLabel(Text("Notes"))
                .accessibilityIdentifier("taskEditor.notes")
        }
    }

    private func manageSection(_ task: FocusTask) -> some View {
        VStack(spacing: LMSpace.s) {
            CosmicButton(title: task.isCompleted ? "Reopen task" : "Mark as done",
                         systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark",
                         kind: .secondary, height: 52) {
                app.tasks.setCompleted(task, !task.isCompleted)
                dismiss()
            }
            .accessibilityIdentifier("taskEditor.toggleDone")
            CosmicButton(title: "Archive", systemImage: "archivebox", kind: .ghost, height: 48) {
                app.tasks.archive(task)
                dismiss()
            }
            Text("Archiving hides the task. Its stars stay in your universe.")
                .font(LMFont.footnote)
                .foregroundStyle(LMColor.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, LMSpace.s)
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let task {
            draft = TaskDraft(task)
        } else {
            draft.category = app.preferences.lastCategory
            titleFocused = true
        }
        hasDueDate = draft.dueDate != nil
        dueDate = draft.dueDate ?? app.clock.now
    }

    private func save() {
        guard draft.isValid else { return }
        draft.dueDate = hasDueDate ? dueDate : nil
        if let task {
            app.tasks.update(task, with: draft)
        } else {
            app.tasks.create(draft)
        }
        app.haptics.selection()
        dismiss()
    }
}

private extension View {
    /// The setup screen's text-field surface.
    func fieldBackground(focused: Bool) -> some View {
        background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(LMColor.textPrimary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(focused ? LMColor.focus : LMColor.hairline, lineWidth: focused ? 1.5 : 1))
    }
}
