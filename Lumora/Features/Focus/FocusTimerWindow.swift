import SwiftUI

/// A small, separate window with just the running timer, for iPad: keep it
/// beside your work in Split View or Stage Manager. It reads the same timer
/// as the main window, so pausing in one pauses both.
struct FocusTimerWindow: View {
    static let id = "focus-timer"

    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            CosmicBackgroundView(mood: .focus, light: 0.4, starOpacity: 0.6)
            if let segment = app.timer.state.focusSegment, let config = segment.focus {
                running(segment: segment, config: config)
            } else {
                idle
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private func running(segment: TimerSegment, config: FocusConfiguration) -> some View {
        TimelineView(.periodic(from: segment.startedAt, by: max(0.1, 1 / segment.timeScale))) { timeline in
            let remaining = segment.remaining(at: timeline.date)
            VStack(spacing: LMSpace.m) {
                HStack(spacing: 6) {
                    CategoryGlyph(category: config.category, size: 12)
                    EyebrowText(config.category.displayName, color: config.category.color)
                }
                if !config.intention.isEmpty {
                    Text(config.intention)
                        .font(LMFont.headline.weight(.medium)).foregroundStyle(LMColor.textPrimary)
                        .lineLimit(2).multilineTextAlignment(.center)
                }
                ZStack {
                    Circle().stroke(LMColor.textPrimary.opacity(0.08), lineWidth: 4)
                    Circle().trim(from: 0, to: segment.progress(at: timeline.date))
                        .stroke(config.category.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(LMFormat.clock(remaining))
                        .font(LMFont.timer(size: 56))
                        .monospacedDigit()
                        .foregroundStyle(LMColor.textPrimary.opacity(segment.isPaused ? 0.6 : 1))
                        .contentTransition(.numericText(countsDown: true))
                }
                .frame(width: 220, height: 220)
                HStack(spacing: LMSpace.l) {
                    RoundControlButton(systemImage: segment.isPaused ? "play.fill" : "pause.fill",
                                       label: segment.isPaused ? "Resume" : "Pause", size: 60, prominent: true) {
                        segment.isPaused ? app.timer.resume() : app.timer.pause()
                    }
                }
            }
            .padding(LMSpace.l)
        }
    }

    private var idle: some View {
        VStack(spacing: LMSpace.m) {
            Image(systemName: "sparkle").font(.largeTitle).foregroundStyle(LMColor.reward)
            Text("No focus running").font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
            CosmicButton(title: "Start focus", systemImage: "sparkle", kind: .reward, height: 52) {
                _ = try? FocusIntentRunner(timer: app.timer, dataStore: app.dataStore, presets: .standard)
                    .start(minutes: nil, category: nil)
            }
            .frame(maxWidth: 280)
        }
        .padding(LMSpace.l)
    }
}

/// Opens the timer in its own window (iPad, where windows are supported).
struct OpenTimerWindowButton: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    var body: some View {
        if supportsMultipleWindows, UIDevice.current.userInterfaceIdiom == .pad {
            Button {
                openWindow(id: FocusTimerWindow.id)
            } label: {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(LMColor.textSecondary)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(LMColor.textPrimary.opacity(0.06)))
            }
            .accessibilityLabel(Text("Open the timer in a new window"))
            .accessibilityIdentifier("focus.openWindow")
        }
    }
}
