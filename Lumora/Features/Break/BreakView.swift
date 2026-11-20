import SwiftUI

/// Break mode: a cooler atmosphere, Pell the companion moon, an optional
/// breathing guide, and gentle ways to continue.
struct BreakView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.motionLevel) private var motion
    @State private var breathing = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let segment = app.timer.state.breakSegment {
            TimelineView(.periodic(from: segment.startedAt, by: max(0.1, 1 / segment.timeScale))) { timeline in
                let remaining = segment.remaining(at: timeline.date)
                ZStack {
                    CosmicBackgroundView(mood: .rest, light: 0.4, starOpacity: 0.7)
                    HorizonGlow().ignoresSafeArea()
                    FittingScrollView {
                        VStack(spacing: 0) {
                            StatusPill(text: "\(segment.kind == .longBreak ? String(localized: "Long break") : String(localized: "Break")) · \(LMFormat.clock(remaining))",
                                       systemImage: "moon", tint: LMColor.calm)
                                .padding(.top, LMSpace.m)
                                .accessibilityLabel(Text("Break, \(Int(remaining / 60)) minutes \(Int(remaining) % 60) seconds remaining"))
                                .accessibilityIdentifier("break.countdown")
                            PellView(mood: segment.kind == .longBreak ? .sleepy : .calm, breathing: breathing,
                                     greetUntil: segment.startedAt.addingTimeInterval(4))
                                .frame(width: typeSize.isAccessibilitySize ? 240 : 150)
                                .frame(minHeight: 150)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.trailing, LMSpace.m)
                            BreathingGuideView(active: breathing)
                                .frame(width: typeSize.isAccessibilitySize ? 300 : 260,
                                       height: typeSize.isAccessibilitySize ? 300 : 260)
                            Spacer(minLength: LMSpace.m)
                            Text("Rest is part of the light.")
                                .font(LMFont.voice(.title))
                                .foregroundStyle(LMColor.textPrimary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(settlingLine)
                                .font(LMFont.callout.weight(.regular))
                                .foregroundStyle(LMColor.textSecondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, LMSpace.xs)
                            Spacer(minLength: LMSpace.l)
                            AdaptiveStack(horizontalAlignment: .center, spacing: LMSpace.s) {
                                Button {
                                    app.haptics.selection()
                                    withAnimation(LMSpring.settle) { breathing.toggle() }
                                } label: {
                                    Label(breathing ? String(localized: "Rest without guide") : String(localized: "Breathe with Pell"),
                                          systemImage: "circle.circle")
                                }
                                .buttonStyle(CosmicButtonStyle(kind: .starlight, height: 56))
                                .accessibilityIdentifier("break.breathe")
                                RoundControlButton(systemImage: app.preferences.ambient == .silence ? "speaker.slash" : "waveform",
                                                   label: "Ambient sound", size: 56) {
                                    toggleAmbient()
                                }
                            }
                            Button {
                                app.haptics.selection()
                                app.timer.prepare()
                            } label: {
                                Text("I'm ready for the next focus")
                                    .font(LMFont.headline.weight(.medium))
                                    .foregroundStyle(LMColor.calm)
                                    .multilineTextAlignment(.center)
                                    .frame(minHeight: 48)
                            }
                            .accessibilityIdentifier("break.skip")
                            .padding(.bottom, LMSpace.s)
                        }
                        .padding(.horizontal, LMSpace.l)
                        .readableColumn()
                    }
                }
            }
            .telemetryScreen("break")
        }
    }

    private var settlingLine: String {
        if let star = app.dataStore.progress()?.starCount, star > 0 {
            return String(localized: "Star #\(star) is settling in. Let your eyes go soft.")
        }
        return String(localized: "Let your eyes go soft.")
    }

    private func toggleAmbient() {
        let prefs = app.preferences
        prefs.ambient = prefs.ambient == .silence ? .tides : .silence
        app.dataStore.save()
        app.audio.setAmbient(prefs.ambient == .silence ? .silence : .tides, volume: prefs.ambientVolume)
    }
}

/// Pell, the companion moon: proud for a moment as a break begins (a star was
/// just born), then floats and blinks, breathes along with the guide (eyes
/// open on the in-breath, closed on the out-breath) and smiles when tapped.
/// Labelled.
struct PellView: View {
    var mood: PellExpression = .calm
    var breathing = false
    /// Proud until then, if it's still ahead when Pell appears.
    var greetUntil: Date?
    var showsLabel = true

    @Environment(\.motionLevel) private var motion
    @State private var delighted = false
    @State private var greeting = false

    var body: some View {
        VStack(spacing: 6) {
            TimelineView(.animation(minimumInterval: motion.frameInterval(30), paused: !breathing)) { tl in
                let face = expression(at: tl.date)
                // The canvas overflows the 120 × 110 frame by 50 pt for the halo: a 40 pt moon.
                PellFace(expression: face.expression, swell: face.swell, fill: 0.19)
            }
            .padding(-50) // let the halo fade naturally past the layout frame
            .frame(width: 120, height: 110)
            .contentShape(Circle().inset(by: 20))
            .onTapGesture { greet() }
            .task {
                guard let greetUntil, greetUntil > .now else { return }
                greeting = true
                try? await Task.sleep(for: .seconds(greetUntil.timeIntervalSinceNow))
                greeting = false
            }
            if showsLabel {
                Text("Pell, your\ncompanion")
                    .font(LMFont.footnote)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(LMColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Pell, your companion moon"))
        .accessibilityValue(Text(expression(at: .now).expression.spokenName))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { greet() }
        .sensoryFeedback(.impact(weight: .light), trigger: delighted) { _, new in new }
    }

    /// Same 10 s rhythm as `BreathingGuideView`: 4 s in, 6 s out.
    private func expression(at date: Date) -> (expression: PellExpression, swell: CGFloat) {
        if delighted { return (.happy, 1.04) }
        if greeting, !breathing { return (.proud, 1) }
        guard breathing else { return (mood, 1) }
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10)
        guard motion != .reduced else { return (phase < 4 ? .calm : .resting, 1) }
        let inhale = phase < 4
        let u = inhale ? phase / 4 : 1 - (phase - 4) / 6
        return (inhale ? .calm : .resting, 0.96 + 0.08 * LMCurve.drift.value(u))
    }

    private func greet() {
        guard !delighted else { return }
        delighted = true
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            delighted = false
        }
    }
}

/// Breathing guide: 4 s in, 6 s out. Shows "Pell is here" when idle.
struct BreathingGuideView: View {
    var active: Bool
    @Environment(\.motionLevel) private var motion

    var body: some View {
        TimelineView(.animation(minimumInterval: motion.frameInterval(30), paused: !active)) { tl in
            let cycle = 10.0
            let phase = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
            let inhale = phase < 4
            let u = inhale ? phase / 4 : 1 - (phase - 4) / 6
            let eased = LMCurve.drift.value(u)
            let scale = active ? (motion == .reduced ? 1 : 0.78 + 0.26 * eased) : 0.9
            ZStack {
                Circle()
                    .strokeBorder(LMColor.textPrimary.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                Circle()
                    .fill(RadialGradient(colors: [LMColor.calm.opacity(0.22), LMColor.calm.opacity(0.02)],
                                         center: .center, startRadius: 0, endRadius: 110))
                    .overlay(Circle().strokeBorder(LMColor.textPrimary.opacity(0.28), lineWidth: 1))
                    .scaleEffect(scale * 0.8)
                Text(active ? (inhale ? String(localized: "Breathe in") : String(localized: "Breathe out")) : String(localized: "Pell is here"))
                    .font(LMFont.title)
                    .foregroundStyle(LMColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 44)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.6), value: inhale)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(active ? (inhale ? "Breathe in" : "Breathe out") : "Pell is here"))
        }
    }
}

/// The soft curve of a planet's horizon at the bottom of the break screen.
private struct HorizonGlow: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                Ellipse()
                    .fill(LinearGradient(colors: [Color(hex: 0x1B3550).opacity(0.85), Color(hex: 0x0E1E33).opacity(0.4)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 2.2, height: w * 1.6)
                    .overlay(Ellipse().stroke(LMColor.calm.opacity(0.35), lineWidth: 1.2))
                    .position(x: w / 2, y: geo.size.height * 0.72 + w * 0.8)
            }
            .shadow(color: LMColor.calm.opacity(0.3), radius: 30)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Shown when a break runs out while Lumora is open.
struct BreakCompleteView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            CosmicBackgroundView(mood: .rest, light: 0.4)
            FittingScrollView {
                VStack(spacing: LMSpace.m) {
                    Spacer()
                    PellView(mood: .happy).frame(minHeight: 150)
                    Text("Your break is complete.")
                        .font(LMFont.voice(.largeTitle))
                        .foregroundStyle(LMColor.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Pell will keep the light warm whenever you're ready.")
                        .font(LMFont.body)
                        .foregroundStyle(LMColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    CosmicButton(title: "Begin next focus", systemImage: "sparkle") {
                        app.showBreakComplete = false
                        app.timer.prepare()
                    }
                    CosmicButton(title: "Back to my universe", kind: .secondary, height: 52) {
                        app.showBreakComplete = false
                    }
                }
                .padding(LMSpace.l)
            }
        }
    }
}
