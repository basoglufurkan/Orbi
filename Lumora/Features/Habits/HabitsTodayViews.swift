import SwiftUI

/// Today's habits under Today's orbit: the steady stars beside the day's route.
struct HabitOrbitStrip: View {
    @Environment(AppModel.self) private var app
    @State private var bursts: [UUID: Int] = [:]

    var body: some View {
        HabitsReader { habits in
            let today = app.today, cal = app.clock.calendar
            let stats = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0.stats(today: today, calendar: cal)) })
            let todays = habits.filter { stats[$0.id].map { $0.dueToday || $0.keptToday } ?? false }
            if !todays.isEmpty {
                let kept = todays.filter { stats[$0.id]?.keptToday == true }.count
                HStack(spacing: LMSpace.xs) {
                    VStack(alignment: .leading, spacing: 0) {
                        EyebrowText(String(localized: "Habits"), color: LMColor.calm)
                        Text("\(kept)/\(todays.count)")
                            .font(LMFont.footnote.monospacedDigit())
                            .foregroundStyle(kept == todays.count ? LMColor.reward : LMColor.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(todays) { habit in
                                if let s = stats[habit.id] {
                                    Button {
                                        if app.habits.toggleToday(habit, source: "orbit") {
                                            app.haptics.success()
                                            bursts[habit.id, default: 0] += 1
                                        } else {
                                            app.haptics.lightTap()
                                        }
                                    } label: {
                                        HabitStarView(symbol: habit.symbol, hue: habit.hue, streakDays: s.currentDays,
                                                      kept: s.keptToday, size: 30, burst: bursts[habit.id] ?? 0)
                                            .frame(width: 44, height: 44)
                                            .contentShape(Circle())
                                    }
                                    .buttonStyle(PressScaleStyle())
                                    .accessibilityLabel(Text(habit.title))
                                    .accessibilityValue(Text(s.keptToday ? "Kept today" : "Not kept yet"))
                                }
                            }
                        }
                    }
                    .scrollClipDisabled()
                }
                .padding(.horizontal, LMSpace.l)
                .accessibilityIdentifier("orbit.habits")
            }
        }
    }
}

/// On a session's summary: the habits that focus just kept.
struct HabitSummaryCard: View {
    var sessionID: UUID
    @Environment(AppModel.self) private var app

    var body: some View {
        if let titles = app.habitsKeptByFocus[sessionID], !titles.isEmpty {
            HStack(spacing: LMSpace.s) {
                HabitStarView(symbol: "checkmark", hue: .study, streakDays: 30, kept: true, size: 34)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    EyebrowText(String(localized: "Habit kept"), color: LMColor.reward)
                    Text(titles.formatted(.list(type: .and)))
                        .font(LMFont.headline)
                        .foregroundStyle(LMColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(LMSpace.m)
            .glassCard(radius: 22, tint: LMColor.reward)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("celebration.habit")
        }
    }
}
