import Foundation

/// The task list's sections. Nothing is ever "overdue": a task whose day has
/// passed simply stays in Today.
enum TaskSection: String, CaseIterable, Identifiable, Sendable {
    case today, upcoming, completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: String(localized: "Today")
        case .upcoming: String(localized: "Upcoming")
        case .completed: String(localized: "Completed")
        }
    }
}

/// What the planner needs from a task; `FocusTask` conforms.
protocol PlannableTask: SendableMetatype {
    var id: UUID { get }
    var createdAt: Date { get }
    var dueDate: Date? { get }
    var isCompleted: Bool { get }
    var completedAt: Date? { get }
    var sortOrder: Double { get }
}

extension FocusTask: PlannableTask {}

/// Pure sectioning and ordering rules for the task list.
struct TaskPlanner {
    var calendar: Calendar
    var now: Date

    /// Today: no due date, or due today or earlier. Upcoming: due after today.
    func section(of task: some PlannableTask) -> TaskSection {
        if task.isCompleted { return .completed }
        guard let due = task.dueDate else { return .today }
        return calendar.startOfDay(for: due) > calendar.startOfDay(for: now) ? .upcoming : .today
    }

    /// Today in manual order; Upcoming by due day, then manual order;
    /// Completed most recent first.
    func arrange<T: PlannableTask>(_ tasks: [T]) -> [TaskSection: [T]] {
        var result = Dictionary(grouping: tasks) { section(of: $0) }
        result[.today]?.sort(by: Self.manualOrder)
        result[.upcoming]?.sort { a, b in
            let da = calendar.startOfDay(for: a.dueDate ?? now), db = calendar.startOfDay(for: b.dueDate ?? now)
            return da != db ? da < db : Self.manualOrder(a, b)
        }
        result[.completed]?.sort { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        return result
    }

    static func manualOrder(_ a: some PlannableTask, _ b: some PlannableTask) -> Bool {
        if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
        return a.createdAt < b.createdAt
    }

    /// New sort orders after moving `source` rows to `destination` (List
    /// `onMove` semantics) within one section. The section keeps the order
    /// values it already had, so other sections are unaffected; ties are
    /// spread apart first.
    static func reorder(ids: [UUID], orders: [Double], moving source: IndexSet, to destination: Int) -> [UUID: Double] {
        precondition(ids.count == orders.count)
        let moving = source.sorted().map { ids[$0] }
        var remaining = ids.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: max(0, min(insertAt, remaining.count)))

        var slots = orders.sorted()
        for i in slots.indices.dropFirst() where slots[i] <= slots[i - 1] {
            slots[i] = slots[i - 1] + 1
        }
        return Dictionary(uniqueKeysWithValues: zip(remaining, slots))
    }
}
