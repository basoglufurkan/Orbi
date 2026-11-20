import AppIntents
import SwiftUI
import WidgetKit

struct HabitsEntry: TimelineEntry {
    let date: Date
    let dayKey: String
    let habits: [HabitWidgetItem]

    /// Today's state, or a fresh day once the stored snapshot is from yesterday.
    var items: [HabitWidgetItem] {
        guard dayKey != DayKey(date).rawValue else { return habits }
        return habits.map { item in
            var fresh = item
            fresh.keptToday = false
            fresh.dueToday = true
            return fresh
        }
    }

    var today: [HabitWidgetItem] { items.filter { $0.dueToday || $0.keptToday } }
    var keptCount: Int { today.filter(\.keptToday).count }
}

/// Reads the habits the app publishes with its snapshot; a second entry at
/// midnight opens the new day without the app running.
struct HabitsProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitsEntry {
        HabitsEntry(date: .now, dayKey: DayKey(.now).rawValue, habits: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitsEntry) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let stored = snapshot?.habits ?? []
        let habits = context.isPreview && stored.isEmpty ? Self.sample : stored
        completion(HabitsEntry(date: .now, dayKey: snapshot?.dayKey ?? DayKey(.now).rawValue, habits: habits))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitsEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let habits = snapshot?.habits ?? []
        let day = snapshot?.dayKey ?? DayKey(.now).rawValue
        let now = Date.now
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 5),
                                                 matchingPolicy: .nextTime) ?? now.addingTimeInterval(6 * 3600)
        let entries = [HabitsEntry(date: now, dayKey: day, habits: habits),
                       HabitsEntry(date: midnight, dayKey: day, habits: habits)]
        completion(Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(60))))
    }

    static var sample: [HabitWidgetItem] {
        [
            HabitWidgetItem(id: UUID(), title: String(localized: "Read 20 minutes"), symbol: "book.fill",
                            hueRaw: FocusCategory.reading.rawValue, streak: 12, countsWeeks: false, streakDays: 12,
                            keptToday: true, dueToday: true),
            HabitWidgetItem(id: UUID(), title: String(localized: "Meditate"), symbol: "figure.mind.and.body",
                            hueRaw: FocusCategory.coding.rawValue, streak: 5, countsWeeks: false, streakDays: 5,
                            keptToday: false, dueToday: true),
            HabitWidgetItem(id: UUID(), title: String(localized: "Move your body"), symbol: "figure.walk",
                            hueRaw: FocusCategory.study.rawValue, streak: 3, countsWeeks: true, streakDays: 21,
                            keptToday: false, dueToday: true),
            HabitWidgetItem(id: UUID(), title: String(localized: "Journal"), symbol: "pencil.and.scribble",
                            hueRaw: FocusCategory.creative.rawValue, streak: 30, countsWeeks: false, streakDays: 30,
                            keptToday: true, dueToday: true),
        ]
    }
}

/// Today's habits as stars you can tap to keep, each burning as brightly as its streak.
struct HabitsWidget: Widget {
    let kind = "LumoraHabits"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HabitsProvider()) { entry in
            HabitsWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetStyle.background }
                .widgetURL(DeepLink.habits.appURL)
        }
        .configurationDisplayName("Habits")
        .description("Keep today's habits with a tap and watch their stars brighten.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct HabitsWidgetView: View {
    var entry: HabitsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let today = entry.today
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(entry.keptCount), in: 0...Double(max(1, today.count))) {
                Image(systemName: "sparkle")
            } currentValueLabel: {
                Text("\(entry.keptCount)/\(today.count)").font(.system(.body, design: .rounded).monospacedDigit())
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "Habits").localizedUppercase).font(.caption2.weight(.bold))
                Text(String(localized: "\(entry.keptCount) of \(today.count) kept")).font(.headline)
                if let open = today.first(where: { !$0.keptToday }) {
                    Text("✦ \(open.title)").font(.caption).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            medium(today)
        default:
            small(today)
        }
    }

    // MARK: Home Screen

    private func header(_ today: [HabitWidgetItem]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(String(localized: "Habits").localizedUppercase).font(.caption2.weight(.bold)).lmTracking(1.2)
                .foregroundStyle(WidgetStyle.cyan)
            Spacer(minLength: 4)
            if !today.isEmpty {
                Text("\(entry.keptCount)/\(today.count)").font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(entry.keptCount == today.count ? WidgetStyle.gold : WidgetStyle.secondary)
            }
        }
    }

    @ViewBuilder
    private func small(_ today: [HabitWidgetItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(today)
            if today.isEmpty {
                Spacer(minLength: 0)
                empty
            } else {
                Spacer(minLength: 0)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(today.prefix(4)) { item in
                        Button(intent: ToggleHabitIntent(habitID: item.id)) {
                            WidgetHabitStar(item: item, size: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(item.title))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func medium(_ today: [HabitWidgetItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(today)
            if today.isEmpty {
                Spacer(minLength: 0)
                empty
                Spacer(minLength: 0)
            } else {
                ForEach(today.prefix(4)) { item in
                    Button(intent: ToggleHabitIntent(habitID: item.id)) {
                        HStack(spacing: 8) {
                            WidgetHabitStar(item: item, size: 24)
                            Text(item.title).font(.footnote.weight(.semibold))
                                .foregroundStyle(item.keptToday ? WidgetStyle.secondary : WidgetStyle.text)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if item.streak > 0 {
                                Text(item.countsWeeks ? String(localized: "\(item.streak)w") : String(localized: "\(item.streak)d"))
                                    .font(.caption2.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(WidgetStyle.gold)
                            }
                            Image(systemName: item.keptToday ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(item.keptToday ? WidgetStyle.gold : WidgetStyle.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("No habits yet").font(.headline).foregroundStyle(WidgetStyle.text)
            Text("Start one in the app.").font(.footnote).foregroundStyle(WidgetStyle.secondary)
        }
    }
}

/// A habit's star: its symbol inside a glow as bright as its streak, gold once kept today.
struct WidgetHabitStar: View {
    var item: HabitWidgetItem
    var size: CGFloat

    var body: some View {
        let hue = FocusCategory(storedValue: item.hueRaw).color
        let glow = HabitLuminosity.brightness(days: item.streakDays)
        ZStack {
            Circle().fill(RadialGradient(colors: [(item.keptToday ? WidgetStyle.gold : hue).opacity(0.55 * glow), .clear],
                                         center: .center, startRadius: 0, endRadius: size * 0.6))
            Circle()
                .strokeBorder(item.keptToday ? WidgetStyle.gold : hue.opacity(0.7),
                              style: StrokeStyle(lineWidth: 1.4, dash: item.keptToday ? [] : [2, 3]))
                .padding(size * 0.08)
            Image(systemName: item.symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(item.keptToday ? WidgetStyle.gold : WidgetStyle.text.opacity(0.4 + 0.6 * glow))
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if item.keptToday, size > 30 {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.2, weight: .heavy))
                    .foregroundStyle(WidgetStyle.space)
                    .padding(3)
                    .background(Circle().fill(WidgetStyle.gold))
            }
        }
    }
}
