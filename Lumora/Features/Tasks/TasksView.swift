import SwiftData
import SwiftUI

/// The things the user plans to focus on, in three calm sections. A task's
/// progress comes from the sessions linked to it; starting a session from a
/// row opens the setup screen with that task chosen.
struct TasksView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<FocusTask> { $0.isPlanned && !$0.isArchived }, sort: \FocusTask.sortOrder)
    private var tasks: [FocusTask]

    @State private var editing: EditorTarget?
    @State private var showCompleted = true
    @State private var editMode: EditMode = .inactive
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Reading `today` re-splits the sections at midnight.
        let _ = app.today
        let sections = app.tasks.planner.arrange(tasks)
        NavigationStack {
            ZStack {
                LMColor.bgBase.ignoresSafeArea()
                if tasks.isEmpty {
                    FittingScrollView(alignment: .center) { emptyState }
                } else {
                    list(sections)
                }
            }
            .navigationTitle(String(localized: "Tasks"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                        .accessibilityIdentifier("tasks.done")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if (sections[.today]?.count ?? 0) > 1 {
                        Button(editMode.isEditing ? String(localized: "Finish") : String(localized: "Reorder")) {
                            withAnimation(LMSpring.settle) { editMode = editMode.isEditing ? .inactive : .active }
                        }
                        .accessibilityIdentifier("tasks.reorder")
                    }
                    Button {
                        editing = .new
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("Add task"))
                    .accessibilityIdentifier("tasks.add")
                }
            }
            .environment(\.editMode, $editMode)
        }
        .tint(LMColor.focus)
        .sheet(item: $editing) { target in
            TaskEditorView(task: target.task)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
        .telemetryScreen("tasks")
    }

    // MARK: List

    private func list(_ sections: [TaskSection: [FocusTask]]) -> some View {
        let today = sections[.today] ?? []
        let upcoming = sections[.upcoming] ?? []
        let completed = sections[.completed] ?? []
        return List {
            Section {
                if today.isEmpty {
                    sectionNote(String(localized: "Nothing planned for today. A quiet sky is fine, too."))
                } else {
                    ForEach(today) { row($0) }
                        .onMove { app.tasks.move(today, from: $0, to: $1) }
                }
            } header: {
                header(.today, count: today.count)
            }

            if !upcoming.isEmpty {
                Section {
                    ForEach(upcoming) { row($0) }
                } header: {
                    header(.upcoming, count: upcoming.count)
                }
            }

            if !completed.isEmpty {
                Section {
                    if showCompleted {
                        ForEach(completed) { row($0) }
                    }
                } header: {
                    Button {
                        withAnimation(LMSpring.settle) { showCompleted.toggle() }
                    } label: {
                        HStack {
                            header(.completed, count: completed.count)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(LMColor.textTertiary)
                                .rotationEffect(.degrees(showCompleted ? 0 : -90))
                        }
                        .contentShape(Rectangle())
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Completed, \(completed.count)"))
                    .accessibilityHint(Text(showCompleted ? "Hides completed tasks" : "Shows completed tasks"))
                }
            }

            Color.clear.frame(height: LMSpace.l)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listRowSpacing(LMSpace.xs)
        .accessibilityIdentifier("tasks.list")
    }

    private func header(_ section: TaskSection, count: Int) -> some View {
        HStack(spacing: LMSpace.xs) {
            EyebrowText(section.title, color: section == .today ? LMColor.calm : LMColor.textTertiary)
            Text("\(count)")
                .font(LMFont.eyebrow.monospacedDigit())
                .foregroundStyle(LMColor.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.top, LMSpace.s)
        .accessibilityAddTraits(.isHeader)
    }

    private func sectionNote(_ text: String) -> some View {
        Text(text)
            .font(LMFont.callout.weight(.regular))
            .foregroundStyle(LMColor.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, LMSpace.xs)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private func row(_ task: FocusTask) -> some View {
        TaskRow(task: task, now: app.clock.now, calendar: app.clock.calendar,
                onOpen: { editing = .edit(task) },
                onStart: { startFocus(task) })
            .listRowInsets(EdgeInsets(top: 0, leading: LMSpace.l, bottom: 0, trailing: LMSpace.l))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    app.haptics.selection()
                    withAnimation(LMSpring.settle) { app.tasks.setCompleted(task, !task.isCompleted) }
                } label: {
                    Label(task.isCompleted ? String(localized: "Reopen") : String(localized: "Done"),
                          systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark")
                }
                .tint(task.isCompleted ? LMColor.focus : LMColor.calm)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    withAnimation(LMSpring.settle) { app.tasks.archive(task) }
                } label: {
                    Label(String(localized: "Archive"), systemImage: "archivebox")
                }
                .tint(Color(hex: Palette.midnightIndigo))
                Button {
                    editing = .edit(task)
                } label: {
                    Label(String(localized: "Edit"), systemImage: "pencil")
                }
                .tint(LMColor.focus)
            }
    }

    private func startFocus(_ task: FocusTask) {
        app.haptics.selection()
        app.focusAfterTasks = task.id
        dismiss()
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: LMSpace.m) {
            PellView(mood: .happy, showsLabel: false)
            Text("Plan what you'll create")
                .font(LMFont.voice(.title))
                .foregroundStyle(LMColor.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Add a few things you'd like to focus on. Choose one when you begin, and watch its stars gather.")
                .font(LMFont.body)
                .foregroundStyle(LMColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            CosmicButton(title: "Add a task", systemImage: "plus", height: 52) {
                editing = .new
            }
            .padding(.top, LMSpace.s)
            .accessibilityIdentifier("tasks.emptyAdd")
        }
        .padding(LMSpace.l)
        .glassCard()
        .padding(LMSpace.l)
    }
}

private enum EditorTarget: Identifiable {
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

/// One task: category glyph, title, project and due day, progress orbs and
/// focused minutes, and a start button.
struct TaskRow: View {
    let task: FocusTask
    var now: Date
    var calendar: Calendar
    var onOpen: () -> Void
    var onStart: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.editMode) private var editMode

    var body: some View {
        let progress = task.progress
        HStack(spacing: LMSpace.s) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: LMSpace.s) {
                    CategoryGlyph(category: task.category, size: 18)
                        .opacity(task.isCompleted ? 0.5 : 1)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(task.title)
                            .font(LMFont.headline)
                            .foregroundStyle(task.isCompleted ? LMColor.textSecondary : LMColor.textPrimary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                        meta
                        if progress.estimate > 0 || progress.sessionsDone > 0 {
                            AdaptiveStack(spacing: LMSpace.xs) {
                                TaskProgressDots(progress: progress, tint: task.category.color)
                                Text(progressText(progress))
                                    .font(LMFont.footnote)
                                    .foregroundStyle(LMColor.textSecondary)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityText(progress)))
            .accessibilityHint(Text("Opens the task"))
            .accessibilityAddTraits(.isButton)

            if task.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(LMColor.calm)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            } else if editMode?.wrappedValue.isEditing != true {
                Button(action: onStart) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LMColor.starlightLabel)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(LMColor.starlightFill))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(Text("Focus on \(task.title)"))
                .accessibilityIdentifier("tasks.start")
            }
        }
        .padding(.horizontal, LMSpace.m)
        .padding(.vertical, LMSpace.s)
        .glassCard(radius: LMRadius.row, tint: task.isCompleted ? nil : task.category.color)
    }

    @ViewBuilder
    private var meta: some View {
        let hasList = !task.listName.isEmpty
        let due = task.isCompleted ? nil : task.dueDate
        let block = task.planBlock
        if hasList || due != nil || block != nil {
            HStack(spacing: LMSpace.xs) {
                if hasList { TaskListTag(name: task.listName) }
                if let block {
                    // A block of a day plan: its day and time.
                    Label("\(TaskFormat.due(block.start, now: now, calendar: calendar)) · \(PlanFormat.range(block))",
                          systemImage: "clock")
                        .font(LMFont.footnote.monospacedDigit())
                        .foregroundStyle(LMColor.calm)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                } else if let due {
                    Label(TaskFormat.due(due, now: now, calendar: calendar), systemImage: "calendar")
                        .font(LMFont.footnote)
                        .foregroundStyle(LMColor.textTertiary)
                        .labelStyle(.titleAndIcon)
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func progressText(_ progress: TaskProgress) -> String {
        progress.focusedMinutes > 0 ? LMFormat.minutes(progress.focusedMinutes) : TaskFormat.sessions(progress)
    }

    private func accessibilityText(_ progress: TaskProgress) -> String {
        var parts = [task.title, task.category.displayName]
        if !task.listName.isEmpty { parts.append(task.listName) }
        parts.append(TaskFormat.sessions(progress))
        if progress.focusedMinutes > 0 { parts.append(LMFormat.spokenMinutes(progress.focusedMinutes)) }
        if task.isCompleted {
            parts.append(String(localized: "done"))
        } else if let block = task.planBlock {
            parts.append(TaskFormat.spokenDue(block.start, now: now, calendar: calendar))
            parts.append(PlanFormat.spokenRange(block))
        } else if let due = task.dueDate {
            parts.append(TaskFormat.spokenDue(due, now: now, calendar: calendar))
        }
        return parts.joined(separator: ", ")
    }
}
