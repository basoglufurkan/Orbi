import SwiftUI
import WidgetKit

struct PlanEntry: TimelineEntry {
    let date: Date
    let blocks: [PlanBlock]

    var timeline: DayTimeline {
        DayTimeline(blocks: DayTimeline.blocks(blocks, on: date, calendar: .current), now: date)
    }
}

/// Reads the day plan the app publishes with its snapshot and puts an
/// entry at every block start and end, so "now" and "next" change on time
/// without the app running. Countdowns are drawn by the system from dates.
struct PlanProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlanEntry {
        PlanEntry(date: .now, blocks: Self.sample(now: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (PlanEntry) -> Void) {
        let stored = WidgetSnapshot.load()?.plan ?? []
        let blocks = context.isPreview && stored.isEmpty ? Self.sample(now: .now) : stored
        completion(PlanEntry(date: .now, blocks: blocks))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlanEntry>) -> Void) {
        let blocks = WidgetSnapshot.load()?.plan ?? []
        let now = Date.now
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 5),
                                                 matchingPolicy: .nextTime) ?? now.addingTimeInterval(6 * 3600)
        var dates = [now] + DayTimeline(blocks: blocks, now: now).boundaries(limit: 30)
        dates.append(midnight)
        let entries = Array(Set(dates)).sorted().map { PlanEntry(date: $0, blocks: blocks) }
        completion(Timeline(entries: entries, policy: .after(max(midnight, entries.last?.date ?? midnight).addingTimeInterval(60))))
    }

    static func sample(now: Date) -> [PlanBlock] {
        let start = now.addingTimeInterval(-50 * 60)
        func block(_ title: String, _ category: FocusCategory, _ offset: Double, _ minutes: Int, done: Bool) -> PlanBlock {
            PlanBlock(id: UUID(), title: title, categoryRaw: category.rawValue,
                      start: start.addingTimeInterval(offset * 60), minutes: minutes, isCompleted: done)
        }
        return [
            block(String(localized: "Morning pages"), .creative, -90, 30, done: true),
            block(String(localized: "Write the report"), .work, 0, 90, done: false),
            block(String(localized: "Training"), .study, 150, 60, done: false),
            block(String(localized: "Read a chapter"), .reading, 270, 45, done: false),
        ]
    }
}

/// Today's orbit: what's now or next, with a live countdown, and the day's
/// stops as a small route.
struct DayOrbitWidget: Widget {
    let kind = "LumoraDayOrbit"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlanProvider()) { entry in
            DayOrbitWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetStyle.background }
                .widgetURL(DeepLink.plan.appURL)
        }
        .configurationDisplayName("Today's orbit")
        .description("Your planned blocks, and the time until the next one.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct DayOrbitWidgetView: View {
    var entry: PlanEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let timeline = entry.timeline
        switch family {
        case .accessoryInline:
            inline(timeline)
        case .accessoryRectangular:
            rectangular(timeline)
        case .systemMedium:
            HStack(alignment: .top, spacing: 14) {
                primary(timeline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                upcoming(timeline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            primary(timeline)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: Home Screen

    @ViewBuilder
    private func primary(_ timeline: DayTimeline) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Today's orbit").localizedUppercase).font(.caption2.weight(.bold)).lmTracking(1.2).foregroundStyle(WidgetStyle.cyan)
            if !timeline.blocks.isEmpty {
                WidgetOrbitStrip(timeline: timeline)
                    .frame(height: 22)
                    .padding(.vertical, 2)
            }
            Spacer(minLength: 0)
            if let current = timeline.current {
                Text(String(localized: "Now · until \(Self.time(current.end))").localizedUppercase).font(.caption2.weight(.semibold)).foregroundStyle(WidgetStyle.cyan)
                Text(current.title).font(.headline).foregroundStyle(WidgetStyle.text).lineLimit(2)
                Text(timerInterval: entry.date...max(entry.date, current.end), countsDown: true)
                    .font(.system(.title2, weight: .light).monospacedDigit())
                    .foregroundStyle(WidgetStyle.text)
            } else if let next = timeline.next {
                Text(String(localized: "Next · at \(Self.time(next.start))").localizedUppercase).font(.caption2.weight(.semibold)).foregroundStyle(WidgetStyle.violet)
                Text(next.title).font(.headline).foregroundStyle(WidgetStyle.text).lineLimit(2)
                Text(timerInterval: entry.date...max(entry.date, next.start), countsDown: true)
                    .font(.system(.title2, weight: .light).monospacedDigit())
                    .foregroundStyle(WidgetStyle.secondary)
            } else if timeline.blocks.isEmpty {
                Text("Nothing planned").font(.headline).foregroundStyle(WidgetStyle.text)
                Text("Plan your day in Orbi.").font(.footnote).foregroundStyle(WidgetStyle.secondary)
            } else {
                Text("✦ " + String(localized: "\(timeline.litCount) of \(timeline.blocks.count) lit")).font(.headline).foregroundStyle(WidgetStyle.gold)
                Text("Today's orbit is complete.").font(.footnote).foregroundStyle(WidgetStyle.secondary)
            }
        }
    }

    @ViewBuilder
    private func upcoming(_ timeline: DayTimeline) -> some View {
        let rows = Array(timeline.blocks.filter { !$0.isCompleted && $0.end > entry.date }.prefix(3))
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "\(timeline.litCount) of \(timeline.blocks.count) lit").localizedUppercase).font(.caption2.weight(.bold)).lmTracking(1.2)
                .foregroundStyle(WidgetStyle.gold)
            if rows.isEmpty {
                Text(timeline.blocks.isEmpty ? String(localized: "Your blocks will appear here.") : String(localized: "Every stop is lit."))
                    .font(.footnote).foregroundStyle(WidgetStyle.secondary)
            }
            ForEach(rows) { block in
                HStack(spacing: 7) {
                    StarShape(points: block.category.starPoints)
                        .fill(block.contains(entry.date) ? WidgetStyle.cyan : block.category.color)
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(block.title).font(.footnote.weight(.semibold)).foregroundStyle(WidgetStyle.text).lineLimit(1)
                        Text("\(Self.time(block.start))–\(Self.time(block.end))").font(.caption2.monospacedDigit())
                            .foregroundStyle(WidgetStyle.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Lock Screen

    @ViewBuilder
    private func rectangular(_ timeline: DayTimeline) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let current = timeline.current {
                Text(String(localized: "Now · until \(Self.time(current.end))").localizedUppercase).font(.caption2.weight(.bold))
                Text(current.title).font(.headline).lineLimit(1)
                Text(timerInterval: entry.date...max(entry.date, current.end), countsDown: true).font(.caption.monospacedDigit())
            } else if let next = timeline.next {
                Text(String(localized: "Next · at \(Self.time(next.start))").localizedUppercase).font(.caption2.weight(.bold))
                Text(next.title).font(.headline).lineLimit(1)
                Text(timerInterval: entry.date...max(entry.date, next.start), countsDown: true).font(.caption.monospacedDigit())
            } else {
                Text(String(localized: "Today's orbit").localizedUppercase).font(.caption2.weight(.bold))
                Text(timeline.blocks.isEmpty ? String(localized: "Nothing planned") : "✦ " + String(localized: "\(timeline.litCount) of \(timeline.blocks.count) lit"))
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func inline(_ timeline: DayTimeline) -> some View {
        if let current = timeline.current {
            Text("✦ \(current.title) · until \(Self.time(current.end))")
        } else if let next = timeline.next {
            Text("✦ \(Self.time(next.start)) \(next.title)")
        } else {
            Text("✦ " + String(localized: "\(timeline.litCount) of \(timeline.blocks.count) lit"))
        }
    }

    /// The person's own clock: "14:00" or "2:00 PM".
    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }
}

/// The day's stops on a gentle wave, lit ones gold, now marked by a dot.
struct WidgetOrbitStrip: View {
    var timeline: DayTimeline

    var body: some View {
        Canvas { g, size in
            let n = timeline.blocks.count
            guard n > 0 else { return }
            let pad: CGFloat = 6
            func point(_ s: Double) -> CGPoint {
                CGPoint(x: pad + (size.width - pad * 2) * CGFloat((s + 0.5) / Double(n)),
                        y: size.height / 2 + CGFloat(sin(.pi * (s + 0.5))) * size.height * 0.24)
            }
            func path(_ a: Double, _ b: Double) -> Path {
                var p = Path()
                guard b > a else { return p }
                p.move(to: point(a))
                var s = a
                while s < b { s = min(b, s + 0.05); p.addLine(to: point(s)) }
                return p
            }
            let cursor = min(Double(n) - 0.5, max(-0.5, timeline.cursor))
            g.stroke(path(cursor, Double(n) - 0.5), with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 1.2, dash: [1.5, 4]))
            g.stroke(path(-0.5, cursor), with: .linearGradient(Gradient(colors: [WidgetStyle.violet, WidgetStyle.gold]),
                                                               startPoint: point(-0.5), endPoint: point(cursor)), lineWidth: 1.8)
            for (k, block) in timeline.blocks.enumerated() {
                let p = point(Double(k))
                switch timeline.status(of: block) {
                case .lit:
                    g.fill(StarShape.path(center: p, radius: 5.5, points: max(4, block.category.starPoints)), with: .color(WidgetStyle.gold))
                case .active:
                    g.fill(Path(ellipseIn: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)), with: .color(WidgetStyle.cyan))
                case .upcoming:
                    g.stroke(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)), with: .color(block.category.color), lineWidth: 1.2)
                case .passed:
                    g.stroke(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(.gray), lineWidth: 1)
                }
            }
            if timeline.current == nil {
                let p = point(cursor)
                g.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(.white))
            }
        }
    }
}
