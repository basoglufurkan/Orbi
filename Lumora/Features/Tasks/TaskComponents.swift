import SwiftUI

/// Sessions done against the estimate as a row of small orbs: filled in the
/// category hue for each session, hollow for the ones still planned.
/// Decorative; callers describe progress in their accessibility label.
struct TaskProgressDots: View {
    var progress: TaskProgress
    var tint: Color
    var size: CGFloat = 7

    private static let maxDots = 8

    var body: some View {
        let total = max(progress.estimate, progress.sessionsDone)
        if total == 0 {
            EmptyView()
        } else if total > Self.maxDots {
            Text(progress.hasEstimate ? "\(progress.sessionsDone)/\(progress.estimate)" : "\(progress.sessionsDone)")
                .font(LMFont.footnote.monospacedDigit())
                .foregroundStyle(LMColor.textSecondary)
                .accessibilityHidden(true)
        } else {
            HStack(spacing: size * 0.6) {
                ForEach(0..<total, id: \.self) { i in
                    let filled = i < progress.sessionsDone
                    Circle()
                        .fill(filled ? tint : Color.clear)
                        .overlay(Circle().strokeBorder(filled ? tint : LMColor.textTertiary.opacity(0.6), lineWidth: 1))
                        .frame(width: size, height: size)
                        .shadow(color: filled ? tint.opacity(0.6) : .clear, radius: 3)
                }
            }
            .accessibilityHidden(true)
        }
    }
}

enum TaskFormat {
    /// "2 of 4 sessions", "1 session", "No sessions yet".
    static func sessions(_ progress: TaskProgress) -> String {
        if progress.hasEstimate {
            return progress.estimate == 1
                ? String(localized: "\(progress.sessionsDone) of 1 session")
                : String(localized: "\(progress.sessionsDone) of \(progress.estimate) sessions")
        }
        switch progress.sessionsDone {
        case 0: return String(localized: "No sessions yet")
        case 1: return String(localized: "1 session")
        default: return String(localized: "\(progress.sessionsDone) sessions")
        }
    }

    /// "Today", "Tomorrow", "Fri", "Oct 24". A day that has passed reads
    /// "Since Oct 18": a gentle note, never an alarm.
    static func due(_ date: Date, now: Date, calendar: Calendar) -> String {
        let day = calendar.startOfDay(for: date), today = calendar.startOfDay(for: now)
        let offset = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch offset {
        case ..<0: return String(localized: "Since \(LMFormat.shortDate(date))")
        case 0: return String(localized: "Today")
        case 1: return String(localized: "Tomorrow")
        case 2...6: return date.formatted(.dateTime.weekday(.abbreviated))
        default: return LMFormat.shortDate(date)
        }
    }

    /// Spoken due date for VoiceOver.
    static func spokenDue(_ date: Date, now: Date, calendar: Calendar) -> String {
        let day = calendar.startOfDay(for: date), today = calendar.startOfDay(for: now)
        if day < today { return String(localized: "planned since \(date.formatted(.dateTime.month(.wide).day()))") }
        if day == today { return String(localized: "planned for today") }
        if calendar.isDate(day, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: today) ?? today) {
            return String(localized: "planned for tomorrow")
        }
        return String(localized: "planned for \(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))")
    }
}

/// Small capsule for a task's project or list name.
struct TaskListTag: View {
    var name: String

    var body: some View {
        Text(name)
            .font(LMFont.footnote)
            .foregroundStyle(LMColor.calm)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(LMColor.calm.opacity(0.12)))
    }
}
