import SwiftUI

/// One habit up close: its constellation of recent days, how bright its
/// star burns and how far to the next stage, its numbers, and a heat map of
/// the weeks behind it where a forgotten day can still be logged.
struct HabitDetailView: View {
    var habit: Habit
    var onEdit: () -> Void

    @Environment(AppModel.self) private var app
    @State private var burst = 0
    @State private var appeared = Date()
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let today = app.today
        let calendar = app.clock.calendar
        let stats = habit.stats(today: today, calendar: calendar)
        ScrollView {
            VStack(alignment: .leading, spacing: LMSpace.m) {
                header(stats)
                constellation(today: today, calendar: calendar)
                keepButton(stats)
                numbers(stats)
                if habit.isFocusLinked { focusCard(stats) }
                heatmap(today: today, calendar: calendar)
                details
            }
            .padding(.horizontal, LMSpace.l)
            .padding(.bottom, LMSpace.xl)
            .readableColumn()
        }
        .scrollIndicators(.hidden)
        .background { CosmicBackgroundView(mood: .home, light: 0.3, showsStars: true, starOpacity: 0.5).ignoresSafeArea() }
        .navigationTitle(habit.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(String(localized: "Edit"), action: onEdit)
                    .accessibilityIdentifier("habit.edit")
            }
        }
        .telemetryScreen("habit_detail")
    }

    // MARK: Header

    private func header(_ stats: HabitStats) -> some View {
        let stage = HabitLuminosity(days: stats.currentDays)
        return HStack(spacing: LMSpace.m) {
            HabitStarView(symbol: habit.symbol, hue: habit.hue, streakDays: stats.currentDays,
                          kept: stats.keptToday, size: 84, burst: burst)
                .frame(width: 100, height: 100)
            VStack(alignment: .leading, spacing: 4) {
                EyebrowText(stage.title, color: stage >= .star ? LMColor.reward : LMColor.calm)
                Text(habit.title)
                    .font(LMFont.voice(.title))
                    .foregroundStyle(LMColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(HabitFormat.cadence(habit.cadence, calendar: app.clock.calendar))
                    .font(LMFont.callout.weight(.regular))
                    .foregroundStyle(LMColor.textSecondary)
                if let next = stage.next {
                    let left = max(0, next.threshold - stats.currentDays)
                    Text(next == .nova
                         ? String(localized: "\(left) more days to become a nova")
                         : String(localized: "\(left) more days to \(next.title)"))
                        .font(LMFont.footnote)
                        .foregroundStyle(LMColor.textTertiary)
                } else {
                    Text("A nova: this habit is part of you now.")
                        .font(LMFont.footnote)
                        .foregroundStyle(LMColor.reward)
                }
            }
        }
        .padding(.top, LMSpace.s)
        .accessibilityElement(children: .combine)
    }

    private func constellation(today: DayKey, calendar: Calendar) -> some View {
        HabitConstellationView(habit: habit, today: today, calendar: calendar, appeared: appeared)
            .frame(height: typeSize.isAccessibilitySize ? 140 : 170)
            .frame(maxWidth: .infinity)
            .glassCard(radius: 24)
            .overlay(alignment: .topLeading) {
                EyebrowText(String(localized: "Its constellation"))
                    .padding(LMSpace.s)
            }
    }

    @ViewBuilder
    private func keepButton(_ stats: HabitStats) -> some View {
        if stats.keptToday {
            CosmicButton(title: "Kept today · Undo", systemImage: "checkmark", kind: .secondary, height: 52) {
                app.habits.setKept(habit, on: app.today, false)
            }
            .accessibilityIdentifier("habitDetail.undo")
        } else {
            CosmicButton(title: "Keep it today", systemImage: "sparkle", kind: .reward, height: 56) {
                if app.habits.setKept(habit, on: app.today, true) {
                    app.haptics.success()
                    burst += 1
                }
            }
            .accessibilityIdentifier("habitDetail.keep")
        }
    }

    private func numbers(_ stats: HabitStats) -> some View {
        let unitWeeks = stats.countsWeeks
        return AdaptiveStack(spacing: LMSpace.xs) {
            tile(value: "\(stats.current)", label: unitWeeks ? String(localized: "Week streak") : String(localized: "Day streak"),
                 tint: LMColor.reward)
            tile(value: "\(stats.best)", label: String(localized: "Best"), tint: LMColor.focus)
            tile(value: "\(stats.total)", label: String(localized: "Days kept"), tint: LMColor.calm)
            tile(value: stats.recentRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "–",
                 label: String(localized: "Last 30 days"), tint: LMColor.warm)
        }
    }

    private func tile(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold).monospacedDigit())
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(label)
                .font(LMFont.footnote)
                .foregroundStyle(LMColor.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .padding(.horizontal, 4)
        .glassCard(radius: 18)
        .accessibilityElement(children: .combine)
    }

    private func focusCard(_ stats: HabitStats) -> some View {
        let focused = app.habits.focusedMinutesToday(for: habit)
        let category = habit.focusCategory
        return HStack(spacing: LMSpace.s) {
            VStack(alignment: .leading, spacing: 4) {
                EyebrowText(String(localized: "Kept by focus"), color: LMColor.calm)
                Text(category.map { String(localized: "Focus \(habit.focusMinutes) min on \($0.inlineName) in a day") }
                     ?? String(localized: "Focus \(habit.focusMinutes) min in a day"))
                    .font(LMFont.callout)
                    .foregroundStyle(LMColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressView(value: Double(min(focused, habit.focusMinutes)), total: Double(max(1, habit.focusMinutes)))
                    .tint(habit.hue.color)
                Text("\(focused) of \(habit.focusMinutes) min today")
                    .font(LMFont.footnote.monospacedDigit())
                    .foregroundStyle(LMColor.textSecondary)
            }
            if !stats.keptToday {
                Spacer(minLength: 0)
                Button {
                    app.requestHabitFocus(habit.id)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LMColor.starlightLabel)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(LMColor.starlightFill))
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(Text("Focus on \(habit.title)"))
                .accessibilityIdentifier("habitDetail.focus")
            }
        }
        .padding(LMSpace.m)
        .glassCard(radius: 22, tint: LMColor.calm)
    }

    private func heatmap(today: DayKey, calendar: Calendar) -> some View {
        VStack(alignment: .leading, spacing: LMSpace.xs) {
            HStack {
                EyebrowText(String(localized: "The weeks behind it"))
                Spacer()
                Text("Tap a day to log it")
                    .font(LMFont.footnote)
                    .foregroundStyle(LMColor.textTertiary)
            }
            HabitHeatmap(habit: habit, today: today, calendar: calendar,
                         weeks: typeSize.isAccessibilitySize ? 10 : 18) { day in
                let kept = app.habits.isKept(habit, on: day)
                app.habits.setKept(habit, on: day, !kept)
                if kept { app.haptics.lightTap() } else { app.haptics.success() }
            }
        }
        .padding(LMSpace.m)
        .glassCard(radius: 22)
        .accessibilityIdentifier("habitDetail.heatmap")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            if habit.reminderEnabled {
                Label(String(localized: "Reminder at \(HabitFormat.time(hour: habit.reminderHour, minute: habit.reminderMinute, calendar: app.clock.calendar))"),
                      systemImage: "bell")
            }
            Label(String(localized: "Since \(habit.createdAt.formatted(.dateTime.day().month(.wide).year()))"), systemImage: "sparkles")
        }
        .font(LMFont.footnote)
        .foregroundStyle(LMColor.textTertiary)
        .padding(.horizontal, LMSpace.xs)
    }
}
