import SwiftUI
import WidgetKit

/// Today's focus progress (Home Screen small/medium + Lock Screen).
struct TodayProgressWidget: Widget {
    let kind = "LumoraTodayProgress"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            TodayProgressView(entry: entry)
                .containerBackground(for: .widget) { WidgetStyle.background }
                .widgetURL(DeepLink.focus(minutes: nil, category: nil).appURL)
        }
        .configurationDisplayName("Today's light")
        .description("Minutes of focus gathered today.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct TodayProgressView: View {
    var entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("✦ \(entry.todayMinutes) of \(entry.snapshot.goalMinutes) min today")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("ORBI").font(.caption2.weight(.bold))
                Text("\(entry.todayMinutes) of \(entry.snapshot.goalMinutes) min").font(.headline)
                Gauge(value: entry.goalProgress) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
            }
        case .systemMedium:
            HStack(spacing: 16) {
                ZStack {
                    WidgetRing(progress: entry.goalProgress, lineWidth: 8)
                    Image(systemName: "sparkle").font(.title3).foregroundStyle(WidgetStyle.text)
                }
                .frame(width: 86, height: 86)
                VStack(alignment: .leading, spacing: 4) {
                    Text("TODAY").font(.caption2.weight(.bold)).lmTracking(1.4).foregroundStyle(WidgetStyle.cyan)
                    Text(WidgetStyle.minutes(entry.todayMinutes)).font(.system(.title, weight: .semibold)).foregroundStyle(WidgetStyle.text)
                    Text("of \(WidgetStyle.minutes(entry.snapshot.goalMinutes)) goal").font(.footnote).foregroundStyle(WidgetStyle.secondary)
                    if entry.snapshot.rhythmDays > 0 {
                        Text("✦ \(entry.snapshot.rhythmDays)-day rhythm").font(.footnote.weight(.semibold)).foregroundStyle(WidgetStyle.gold)
                    }
                }
                .layoutPriority(1)
                // A sliver of the user's sky fills the trailing side, fading in from the text.
                if entry.snapshot.stars.isEmpty {
                    Spacer(minLength: 0)
                } else {
                    MiniSky(stars: Array(entry.snapshot.stars.prefix(12)), glyphScale: 1.1, glow: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .leading, endPoint: .trailing))
                }
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text("TODAY").font(.caption2.weight(.bold)).lmTracking(1.4).foregroundStyle(WidgetStyle.cyan)
                Spacer(minLength: 0)
                Text(WidgetStyle.minutes(entry.todayMinutes)).font(.system(.title, weight: .semibold)).foregroundStyle(WidgetStyle.text)
                Text("of \(WidgetStyle.minutes(entry.snapshot.goalMinutes))").font(.footnote).foregroundStyle(WidgetStyle.secondary)
                WidgetBar(progress: entry.goalProgress)
            }
        }
    }
}

/// Daily goal completion as a ring (Home Screen small + Lock Screen circular).
struct DailyGoalWidget: Widget {
    let kind = "LumoraDailyGoal"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            DailyGoalView(entry: entry)
                .containerBackground(for: .widget) { WidgetStyle.background }
                .widgetURL(DeepLink.focus(minutes: nil, category: nil).appURL)
        }
        .configurationDisplayName("Daily goal")
        .description("How close today is to your goal.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct DailyGoalView: View {
    var entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryCircular {
            Gauge(value: entry.goalProgress) {
                Image(systemName: "sparkle")
            } currentValueLabel: {
                Text("\(Int(entry.goalProgress * 100))%").minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircularCapacity)
        } else {
            VStack(spacing: 8) {
                ZStack {
                    WidgetRing(progress: entry.goalProgress, lineWidth: 9)
                    VStack(spacing: 0) {
                        Text("\(Int(entry.goalProgress * 100))%").font(.system(.title2, weight: .semibold)).foregroundStyle(WidgetStyle.text)
                        Text("goal").font(.caption2).foregroundStyle(WidgetStyle.tertiary)
                    }
                }
                .padding(4)
                Text(entry.goalProgress >= 1 ? "Goal reached ✦" : "\(max(0, entry.snapshot.goalMinutes - entry.todayMinutes)) min to go")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(entry.goalProgress >= 1 ? WidgetStyle.gold : WidgetStyle.secondary)
            }
        }
    }
}

/// Current rhythm ("streak"), framed kindly.
struct RhythmWidget: Widget {
    let kind = "LumoraRhythm"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            RhythmView(entry: entry)
                .containerBackground(for: .widget) { WidgetStyle.background }
                .widgetURL(DeepLink.screen(.insights).appURL)
        }
        .configurationDisplayName("Rhythm")
        .description("Your current rhythm of focus days. One rest day a week is free.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

struct RhythmView: View {
    var entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let days = entry.snapshot.rhythmDays
        switch family {
        case .accessoryInline:
            Text(days > 0 ? "✦ \(days)-day rhythm" : "✦ Your sky is waiting")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "sparkle").font(.caption2)
                    Text("\(days)").font(.title3.weight(.semibold)).minimumScaleFactor(0.6)
                    (days == 1 ? Text("day") : Text("days")).font(.caption2)
                }
                .padding(.vertical, 2)
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text("RHYTHM").font(.caption2.weight(.bold)).lmTracking(1.4).foregroundStyle(WidgetStyle.gold)
                Spacer(minLength: 0)
                Text(days > 0 ? "\(days)" : "—").font(.system(size: 44, weight: .light)).foregroundStyle(WidgetStyle.text)
                (days == 1 ? Text("day") : Text("days")).font(.footnote).foregroundStyle(WidgetStyle.secondary)
                Text(days > 0 ? "Rest days are part of it." : "One session starts it.")
                    .font(.caption2).foregroundStyle(WidgetStyle.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
