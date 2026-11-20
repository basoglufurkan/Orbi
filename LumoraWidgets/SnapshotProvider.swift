import SwiftUI
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// Minutes for `date`'s day (0 once the stored snapshot is from yesterday).
    var todayMinutes: Int { snapshot.minutesToday(now: date) }
    var goalProgress: Double {
        snapshot.goalMinutes > 0 ? min(1, Double(todayMinutes) / Double(snapshot.goalMinutes)) : 0
    }
}

/// Reads the snapshot the app publishes to the App Group. Widgets never
/// open the SwiftData store. A second entry at local midnight resets
/// "today" without the app having to run.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .placeholder : (WidgetSnapshot.load() ?? .placeholder)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load() ?? WidgetSnapshot(
            generatedAt: .now, dayKey: DayKey(.now).rawValue, todayMinutes: 0, goalMinutes: 120, rhythmDays: 0,
            totalStars: 0, planets: 0, constellations: 0, stars: [], nextWorldName: "Velora", sessionsToNextWorld: 10)
        let now = Date.now
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 5),
                                                 matchingPolicy: .nextTime) ?? now.addingTimeInterval(3600 * 6)
        let entries = [SnapshotEntry(date: now, snapshot: snapshot), SnapshotEntry(date: midnight, snapshot: snapshot)]
        completion(Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(60))))
    }
}

enum WidgetStyle {
    static let space = Color(hex: Palette.deepSpace)
    static let raised = Color(hex: Palette.midnightIndigo)
    static let text = Color(hex: Palette.softWhite)
    static let secondary = Color(hex: 0xB9BCE3)
    static let tertiary = Color(hex: 0x8C90C2)
    static let violet = Color(hex: Palette.cosmicViolet)
    static let gold = Color(hex: Palette.warmGold)
    static let cyan = Color(hex: Palette.starlightCyan)

    static var background: some View {
        ZStack {
            space
            RadialGradient(colors: [violet.opacity(0.35), .clear], center: UnitPoint(x: 0.3, y: 0.2), startRadius: 0, endRadius: 180)
        }
    }

    static func minutes(_ m: Int) -> String {
        let h = m / 60, r = m % 60
        if h == 0 { return String(localized: "\(r)m") }
        return r == 0 ? String(localized: "\(h)h") : String(localized: "\(h)h \(r)m")
    }
}

/// Linear goal bar with a track that stays visible at 0% on Deep Space.
struct WidgetBar: View {
    var progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(progress >= 1 ? WidgetStyle.gold : WidgetStyle.violet)
                    .frame(width: progress > 0 ? max(6, geo.size.width * min(1, progress)) : 0)
            }
        }
        .frame(height: 5)
    }
}

/// Small progress ring used by several widgets.
struct WidgetRing: View {
    var progress: Double
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(progress >= 1 ? WidgetStyle.gold : WidgetStyle.violet,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
