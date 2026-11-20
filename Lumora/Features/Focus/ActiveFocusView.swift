import SwiftUI

/// The main focus screen: the living star, a highly readable countdown, a
/// calm line of copy, and two controls. The countdown is recomputed from the
/// segment's dates once per second; it never counts ticks.
struct ActiveFocusView: View {
    @Environment(AppModel.self) private var app
    /// Kept out of the String Catalog: a developer tool, never in store builds.
    private static let finishNowLabel = "Finish now"
    @Environment(\.motionLevel) private var motion
    /// Compact height: an iPhone turned sideways during a session.
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize: CGFloat = 88
    @State private var confirmEnd = false
    @State private var actionLock = false
    @State private var lastFinalMinuteTick: UUID?

    var body: some View {
        if let segment = app.timer.state.focusSegment, let config = segment.focus {
            content(segment: segment, config: config)
                // The only screen that may turn sideways on iPhone.
                .onAppear { OrientationLock.allowsLandscape = true }
                .onDisappear { OrientationLock.allowsLandscape = false }
            .telemetryScreen("focus_active")
        }
    }

    private func content(segment: TimerSegment, config: FocusConfiguration) -> some View {
        // Text updates once per (segment) second, aligned to the start.
        TimelineView(.periodic(from: segment.startedAt, by: max(0.1, 1 / segment.timeScale))) { timeline in
            let now = timeline.date
            let p = segment.progress(at: now)
            let remaining = segment.remaining(at: now)
            ZStack {
                CosmicBackgroundView(mood: .focus, light: p,
                                     starOpacity: (0.35 + 0.65 * p) * (segment.isPaused ? 0.55 : 1))
                if verticalSizeClass == .compact {
                    // Sideways: the star on the left, time and controls on the right.
                    HStack(spacing: 0) {
                        stage(segment: segment, config: config, now: now)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        FittingScrollView {
                            VStack(spacing: 0) {
                                header(config: config)
                                Spacer(minLength: LMSpace.s)
                                timerText(remaining: remaining, paused: segment.isPaused)
                                copyLine(progress: p, remaining: remaining, paused: segment.isPaused)
                                Spacer(minLength: LMSpace.m)
                                controls(paused: segment.isPaused, segment: segment)
                                    .padding(.bottom, LMSpace.s)
                            }
                            .padding(.horizontal, LMSpace.m)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .ignoresSafeArea(edges: .vertical)
                } else {
                    stage(segment: segment, config: config, now: now)
                        .ignoresSafeArea()

                    // Scrolls only when large text can't fit; the controls stay reachable.
                    FittingScrollView {
                        VStack(spacing: 0) {
                            header(config: config)
                            ExpeditionChip(segment: segment, now: now)
                                .padding(.top, LMSpace.xs)
                            Spacer(minLength: LMSpace.l)
                            timerText(remaining: remaining, paused: segment.isPaused)
                            copyLine(progress: p, remaining: remaining, paused: segment.isPaused)
                            Spacer().frame(height: LMSpace.xl)
                            controls(paused: segment.isPaused, segment: segment)
                                .padding(.bottom, LMSpace.l)
                        }
                        .padding(.horizontal, LMSpace.l)
                        .readableColumn()
                    }
                }
            }
            .onChange(of: remaining <= 60) { _, final in
                guard final, app.preferences.finalMinuteTick, lastFinalMinuteTick != segment.id else { return }
                lastFinalMinuteTick = segment.id
                app.haptics.finalMinuteTick()
            }
        }
        .confirmationDialog(endTitle(segment: segment), isPresented: $confirmEnd, titleVisibility: .visible) {
            Button(String(localized: "End session"), role: .destructive) { app.timer.endEarly() }
            Button(String(localized: "Keep focusing"), role: .cancel) {}
        } message: {
            Text(endMessage(segment: segment))
        }
    }

    // MARK: Pieces

    /// The living star, or while focusing together, the shared galaxy with
    /// everyone in the room at their desks.
    @ViewBuilder
    private func stage(segment: TimerSegment, config: FocusConfiguration, now: Date) -> some View {
        let together = app.together
        if together.phase == .focusing {
            let people = together.present(at: now).map {
                TogetherGalaxyView.Person(id: $0.slot, name: $0.name, isMe: $0.slot == together.slot, isHost: $0.isHost)
            }
            TogetherGalaxyView(people: people, category: config.category)
        } else {
            FocusSceneView(segment: segment, category: config.category)
        }
    }

    private func copyLine(progress p: Double, remaining: TimeInterval, paused: Bool) -> some View {
        Text(Self.copy(progress: p, remaining: remaining, paused: paused))
            .font(LMFont.voice(.title3))
            .foregroundStyle(LMColor.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, LMSpace.xs)
            .animation(LMCurve.drift.animation(duration: 0.8), value: Self.copyStage(progress: p, remaining: remaining, paused: paused))
    }

    private func header(config: FocusConfiguration) -> some View {
        ZStack(alignment: .top) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    CategoryGlyph(category: config.category, size: 12)
                    EyebrowText("\(config.category.displayName) · \(String(localized: "Star")) #\(nextStarNumber)",
                                color: config.category.color)
                        .multilineTextAlignment(.center)
                }
                if !config.intention.isEmpty {
                    Text(config.intention)
                        .font(LMFont.headline.weight(.medium))
                        .foregroundStyle(LMColor.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 56)
            .accessibilityElement(children: .combine)

            HStack {
                OpenTimerWindowButton()
                Spacer()
                AmbientMenuButton()
            }
        }
        .padding(.top, LMSpace.m)
    }

    private func timerText(remaining: TimeInterval, paused: Bool) -> some View {
        Text(LMFormat.clock(remaining))
            .font(LMFont.timer(size: min(timerSize, 120)))
            .tracking(-2)
            .foregroundStyle(LMColor.textPrimary.opacity(paused ? 0.6 : 1))
            .contentTransition(.numericText(countsDown: true))
            .animation(motion == .reduced ? nil : .easeOut(duration: 0.25), value: Int(remaining.rounded(.up)))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityLabel(Text(spokenRemaining(remaining)))
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityIdentifier("focus.timer")
    }

    private func controls(paused: Bool, segment: TimerSegment) -> some View {
        HStack(spacing: LMSpace.xl) {
            RoundControlButton(systemImage: "stop.fill", label: "End session", size: 56) {
                confirmEnd = true
            }
            .accessibilityIdentifier("focus.end")
            RoundControlButton(systemImage: paused ? "play.fill" : "pause.fill",
                               label: paused ? "Resume" : "Pause", size: 76, prominent: true) {
                guard !actionLock else { return }
                actionLock = true
                if paused { app.timer.resume() } else { app.timer.pause() }
                // Swallow rapid double taps; the engine also ignores invalid actions.
                Task { try? await Task.sleep(for: .milliseconds(350)); actionLock = false }
            }
            .accessibilityIdentifier("focus.pauseResume")
            // Developer installs only (Debug, or a build put straight on a device):
            // complete the session now instead of waiting. Hidden under UI
            // automation so tests and marketing captures stay true to release.
            if BuildInfo.isDeveloperInstall, !app.launchOptions.isUITesting {
                RoundControlButton(systemImage: "forward.end.fill", label: LocalizedStringKey(Self.finishNowLabel), size: 56) {
                    app.timer.debugFinishNow()
                }
            } else {
                Color.clear.frame(width: 56, height: 56)
            }
        }
    }

    private var nextStarNumber: Int {
        (app.dataStore.progress()?.starCount ?? 0) + 1
    }

    // MARK: Copy

    static func copyStage(progress p: Double, remaining: TimeInterval, paused: Bool) -> Int {
        if paused { return 5 }
        if p <= 0.001 { return 0 }
        if remaining <= 60 { return 4 }
        if p >= 0.8 { return 3 }
        if p >= 0.3 { return 2 }
        return 1
    }

    static func copy(progress p: Double, remaining: TimeInterval, paused: Bool) -> String {
        switch copyStage(progress: p, remaining: remaining, paused: paused) {
        case 0: String(localized: "A new star is waiting to begin.")
        case 1: String(localized: "Settle in. The light is gathering.")
        case 2: String(localized: "You're building something beautiful.")
        case 3: String(localized: "Almost there. It's starting to shine.")
        case 4: String(localized: "One more breath of light.")
        default: String(localized: "Paused. Your light is waiting.")
        }
    }

    private func spokenRemaining(_ remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded(.up))
        return String(localized: "\(total / 60) minutes \(total % 60) seconds remaining")
    }

    private func endTitle(segment: TimerSegment) -> String {
        String(localized: "End this session?")
    }

    private func endMessage(segment: TimerSegment) -> String {
        let focused = segment.elapsed(at: app.clock.now)
        return focused >= Double(app.rules.minimumQualifyingSeconds)
            ? String(localized: "You'll keep a smaller star for the \(Int(focused / 60)) minutes you focused. Nothing is lost.")
            : String(localized: "Sessions shorter than \(app.rules.minimumQualifyingSeconds / 60) minutes rest without a star. Your universe stays exactly as it is.")
    }
}

/// Ambient sound switcher available during focus.
struct AmbientMenuButton: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Menu {
            // Orbi+ sounds are offered on the setup screen, not mid-focus.
            ForEach(AmbientSound.allCases.filter { !$0.isPlus || app.plus.isActive }) { sound in
                Button {
                    app.preferences.ambient = sound
                    app.dataStore.save()
                    Telemetry.log(.ambienceChanged(sound: sound.rawValue, during: "focus"))
                    app.audio.setAmbient(sound, volume: app.preferences.ambientVolume)
                } label: {
                    if app.preferences.ambient.playable == sound {
                        Label(sound.title, systemImage: "checkmark")
                    } else {
                        Text(sound.title)
                    }
                }
            }
        } label: {
            Image(systemName: app.preferences.ambient == .silence ? "speaker.slash" : "waveform")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(LMColor.textSecondary)
                .frame(width: 52, height: 52)
                .background(Circle().fill(LMColor.textPrimary.opacity(0.06)))
        }
        .accessibilityLabel(Text("Ambient sound"))
    }
}
