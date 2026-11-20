import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen + Dynamic Island for an active session. Shows only time and
/// the star — no counts, no nagging. Countdown and progress are rendered by
/// the system from dates, so they stay exact without app updates.
struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            LockScreenActivityView(context: context)
                .activityBackgroundTint(Color(hex: Palette.deepSpace).opacity(0.92))
                .activitySystemActionForegroundColor(Color(hex: Palette.softWhite))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityStarGlyph(categoryRaw: context.attributes.categoryRaw, size: 26)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityTimeText(state: context.state, stale: context.isStale)
                        .font(.system(.title2, weight: .light).monospacedDigit())
                        .foregroundStyle(ActivityCopy.timeColor(context.state, stale: context.isStale))
                        .frame(maxWidth: 110, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(title(context))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(hex: Palette.starlightCyan))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            ActivityStatusLine(context: context).font(.callout)
                            ActivityProgress(state: context.state, stale: context.isStale)
                            ActivityNextBlockLine(state: context.state, stale: context.isStale)
                        }
                        ActivityPauseButton(state: context.state, stale: context.isStale)
                    }
                }
            } compactLeading: {
                ActivityStarGlyph(categoryRaw: context.attributes.categoryRaw, size: 16)
            } compactTrailing: {
                HStack(spacing: 2) {
                    if context.state.mode == .paused {
                        Image(systemName: "pause.fill").font(.system(size: 8, weight: .bold))
                    }
                    ActivityTimeText(state: context.state, stale: context.isStale)
                        .font(.caption.monospacedDigit())
                }
                .foregroundStyle(ActivityCopy.timeColor(context.state, stale: context.isStale))
                .frame(maxWidth: 60)
            } minimal: {
                ActivityStarGlyph(categoryRaw: context.attributes.categoryRaw, size: 14)
            }
            .keylineTint(Color(hex: Palette.cosmicViolet))
        }
    }

    private func title(_ context: ActivityViewContext<FocusActivityAttributes>) -> String {
        if context.attributes.categoryRaw == "break" { return String(localized: "Break · Pell is here").localizedUppercase }
        let name = FocusCategory(rawValue: context.attributes.categoryRaw)?.displayName ?? String(localized: "Focus")
        return String(localized: "\(name) · Star #\(context.attributes.starNumber)").localizedUppercase
    }
}

private struct LockScreenActivityView: View {
    let context: ActivityViewContext<FocusActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            ActivityStarGlyph(categoryRaw: context.attributes.categoryRaw, size: 34)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.caption.weight(.bold))
                    .lmTracking(1.2)
                    .foregroundStyle(Color(hex: Palette.starlightCyan))
                ActivityStatusLine(context: context)
                    .font(.callout.weight(.medium))
                ActivityProgress(state: context.state, stale: context.isStale)
                ActivityNextBlockLine(state: context.state, stale: context.isStale)
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            // Date-driven timer text is greedy; size it to the longest value it can show.
            ActivityTimeText(state: context.state, stale: context.isStale)
                .font(.system(size: 34, weight: .ultraLight).monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(ActivityCopy.timeColor(context.state, stale: context.isStale))
                .frame(width: timeWidth, alignment: .trailing)
            ActivityPauseButton(state: context.state, stale: context.isStale)
        }
        .padding(16)
    }

    private var timeWidth: CGFloat {
        if ActivityCopy.isDone(context.state, stale: context.isStale) { return 40 }
        return context.state.endDate.timeIntervalSince(context.state.startDate) >= 3600 ? 118 : 90
    }

    private var headline: String {
        if context.attributes.categoryRaw == "break" { return String(localized: "Break").localizedUppercase }
        let name = FocusCategory(rawValue: context.attributes.categoryRaw)?.displayName ?? String(localized: "Focus")
        return String(localized: "\(name) · Star #\(context.attributes.starNumber)").localizedUppercase
    }

}

/// State-aware copy and colors shared by the Lock Screen and Dynamic Island.
enum ActivityCopy {
    static func isDone(_ state: FocusActivityAttributes.ContentState, stale: Bool) -> Bool {
        state.mode == .complete || (stale && state.mode != .paused)
    }

    static func status(_ attributes: FocusActivityAttributes, _ state: FocusActivityAttributes.ContentState, stale: Bool) -> String {
        let isBreak = attributes.categoryRaw == "break"
        if isDone(state, stale: stale) { return isBreak ? String(localized: "Break complete. Ready when you are.") : String(localized: "A new star is born.") }
        if state.mode == .paused {
            return attributes.intention.isEmpty ? String(localized: "Paused. Your light is waiting.") : String(localized: "Paused · \(attributes.intention)")
        }
        if !attributes.intention.isEmpty { return attributes.intention }
        return state.mode == .onBreak ? String(localized: "Rest is part of the light.") : String(localized: "The light is gathering.")
    }

    static func timeColor(_ state: FocusActivityAttributes.ContentState, stale: Bool) -> Color {
        if isDone(state, stale: stale) { return Color(hex: Palette.warmGold) }
        return state.mode == .paused ? Color(hex: 0xB9BCE3) : Color(hex: Palette.softWhite)
    }
}

/// Second line of the activity: intention while running, a gold cue when
/// paused or finished.
struct ActivityStatusLine: View {
    let context: ActivityViewContext<FocusActivityAttributes>

    var body: some View {
        let state = context.state
        let highlighted = state.mode == .paused || ActivityCopy.isDone(state, stale: context.isStale)
        HStack(spacing: 5) {
            if state.mode == .paused {
                Image(systemName: "pause.fill").font(.caption2.weight(.bold))
            }
            Text(ActivityCopy.status(context.attributes, state, stale: context.isStale))
                .lineLimit(1).minimumScaleFactor(0.85)
        }
        .foregroundStyle(highlighted ? Color(hex: Palette.warmGold) : Color(hex: Palette.softWhite))
    }
}

/// Pause / resume without opening the app. The intents are
/// `LiveActivityIntent`s, so they run in the app's process and go through the
/// same `FocusSessionController` as the in-app buttons; the activity is then
/// updated by the app, never by the widget.
struct ActivityPauseButton: View {
    var state: FocusActivityAttributes.ContentState
    var stale: Bool

    var body: some View {
        if !stale, state.mode == .focusing {
            Button(intent: PauseFocusIntent()) {
                Image(systemName: "pause.fill")
            }
            .buttonStyle(ActivityControlStyle())
            .accessibilityLabel("Pause focus")
        } else if state.mode == .paused {
            Button(intent: ResumeFocusIntent()) {
                Image(systemName: "play.fill")
            }
            .buttonStyle(ActivityControlStyle())
            .accessibilityLabel("Resume focus")
        }
    }
}

private struct ActivityControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color(hex: Palette.softWhite))
            .frame(width: 38, height: 38)
            .background(Circle().fill(Color(hex: Palette.cosmicViolet).opacity(configuration.isPressed ? 0.5 : 0.35)))
            .overlay(Circle().strokeBorder(Color(hex: Palette.softWhite).opacity(0.18)))
    }
}

struct ActivityTimeText: View {
    var state: FocusActivityAttributes.ContentState
    var stale: Bool

    var body: some View {
        if state.mode == .complete || (stale && state.mode != .paused) {
            Text("✦")
        } else if state.mode == .paused, let remaining = state.pausedRemaining {
            Text(Self.format(remaining))
        } else {
            Text(timerInterval: state.startDate...max(state.startDate, state.endDate), countsDown: true)
                .multilineTextAlignment(.trailing)
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        // Same shape as the system's `Text(timerInterval:)` so pausing doesn't reflow the time.
        let total = max(0, Int(seconds.rounded(.up)))
        let h = total / 3600, m = total % 3600 / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

struct ActivityProgress: View {
    var state: FocusActivityAttributes.ContentState
    var stale: Bool

    var body: some View {
        Group {
            if state.mode == .complete || stale {
                ProgressView(value: 1)
            } else if state.mode == .paused {
                ProgressView(value: state.pausedProgress ?? 0)
            } else {
                ProgressView(timerInterval: state.startDate...max(state.startDate, state.endDate), countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            }
        }
        .tint(state.mode == .onBreak ? Color(hex: Palette.starlightCyan) : (state.mode == .complete || stale ? Color(hex: Palette.warmGold) : Color(hex: Palette.cosmicViolet)))
        .labelsHidden()
    }
}

struct ActivityStarGlyph: View {
    var categoryRaw: String
    var size: CGFloat

    var body: some View {
        let category = FocusCategory(rawValue: categoryRaw)
        ZStack {
            Circle().fill((category?.color ?? Color(hex: 0xDDE6F2)).opacity(0.5)).frame(width: size * 1.5, height: size * 1.5).blur(radius: size * 0.25)
            if let category {
                StarShape(points: category.starPoints).fill(Color.white).frame(width: size, height: size)
            } else {
                Image(systemName: "moon.fill").font(.system(size: size * 0.7)).foregroundStyle(Color(hex: 0xDDE6F2))
            }
        }
    }
}

/// The day plan's next block beneath the countdown: "Next · 14:00 Training".
struct ActivityNextBlockLine: View {
    let state: FocusActivityAttributes.ContentState
    let stale: Bool

    var body: some View {
        if let title = state.nextBlockTitle, let start = state.nextBlockStart, !ActivityCopy.isDone(state, stale: stale) {
            let time = start.formatted(.dateTime.hour().minute())
            HStack(spacing: 5) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 9, weight: .semibold))
                Text("Next · \(time) \(title)")
                    .lineLimit(1)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color(hex: 0x8C90C2))
        }
    }
}
