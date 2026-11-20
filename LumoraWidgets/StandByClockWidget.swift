import SwiftUI
import WidgetKit

/// A night-sky clock for StandBy (and the Home Screen): your own stars
/// behind a large, quiet time, with today's focus underneath. In StandBy's
/// night mode the system tints it red, so it never lights up a dark room.
struct StandByClockWidget: Widget {
    let kind = "LumoraStandByClock"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            StandByClockView(entry: entry)
                .containerBackground(for: .widget) { UniverseBackdrop() }
                .widgetURL(DeepLink.screen(.universe).appURL)
        }
        .configurationDisplayName("Night sky clock")
        .description("The time over your own stars. Made for StandBy while your iPhone charges.")
        .supportedFamilies([.systemSmall])
        .containerBackgroundRemovable(false)
    }
}

struct StandByClockView: View {
    var entry: SnapshotEntry
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let s = entry.snapshot
        ZStack {
            if !s.stars.isEmpty {
                MiniSky(stars: s.stars, glyphScale: 0.7, glow: renderingMode == .fullColor)
                    .opacity(0.55)
            }
            VStack(spacing: 2) {
                Spacer(minLength: 0)
                // A live clock: the system updates it every minute without a new timeline.
                Text(entry.date, style: .time)
                    .font(.system(size: 44, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(WidgetStyle.text)
                    .widgetAccentable()
                Text(String(localized: "\(entry.todayMinutes) min of light today"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WidgetStyle.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
        }
    }
}
