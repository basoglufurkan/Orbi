import SwiftUI

/// The completion cinematic. The reward is already persisted before this
/// view exists (it is built from a `SessionReward` loaded from the store),
/// so skipping, backgrounding or killing the app mid-sequence can never lose
/// or duplicate anything — this layer is purely presentational.
struct CelebrationSequenceView: View {
    let reward: SessionReward
    var autoBreak = false

    @Environment(AppModel.self) private var app
    @Environment(\.motionLevel) private var motion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    @State private var start = Date.now
    @State private var started = false
    @State private var showSummary = false
    @State private var finished = false
    @State private var particles: [CelebrationParticle] = []

    var body: some View {
        let plan = CelebrationPlan.make(for: reward, motion: motion)
        GeometryReader { geo in
            let full = CGSize(width: geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing,
                              height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom)
            let layout = CelebrationLayout(size: full, reward: reward, plan: plan)
            ZStack {
                CosmicBackgroundView(mood: .reward, light: 0.6, showsStars: false)

                TimelineView(.animation(minimumInterval: finished ? 1.0 / 15 : 1.0 / 60,
                                        paused: (finished && !motion.animatesContinuously) || scenePhase != .active)) { timeline in
                    let t = started ? timeline.date.timeIntervalSince(start) : 0
                    ZStack {
                        Canvas { ctx, _ in
                            CelebrationRenderer.draw(&ctx, t: t, plan: plan, layout: layout, particles: particles,
                                                     planetPalette: reward.planetBorn.map { .named($0.hue) },
                                                     dark: colorScheme == .dark,
                                                     ambientTime: motion.animatesContinuously && t > 1 ? timeline.date.timeIntervalSinceReferenceDate : nil)
                        }
                        .ignoresSafeArea()

                        DissolvingTimerEcho(t: t, reduced: plan.kind == .reduced || plan.kind == .tooShort)

                        if plan.kind != .milestone, plan.kind != .tooShort, let star = reward.star {
                            Text("\(String(localized: "Star")) #\(star.ordinal)".localizedUppercase)
                                .font(LMFont.eyebrow).lmTracking(1.6)
                                .foregroundStyle(LMColor.calm)
                                .position(x: min(full.width - 60, layout.starFinal.x + 54),
                                          y: layout.starFinal.y + 30 - geo.safeAreaInsets.top)
                                .opacity(plan.kind == .reduced ? beat(t, 0.4, 0.8) : beat(t, 4.2, 4.6))
                                .accessibilityHidden(true)
                        }
                    }
                }

                if showSummary {
                    CelebrationSummaryView(reward: reward, plan: plan, autoBreak: autoBreak)
                        .transition(.identity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { skip(plan: plan) }
            .accessibilityAction(named: Text("Skip animation")) { skip(plan: plan, force: true) }
        }
        .task { await run(plan: plan) }
    }

    private func run(plan: CelebrationPlan) async {
        guard !started else { return }
        particles = CelebrationParticle.make(count: motion.particleBudget, category: reward.category,
                                             seed: StableHash.fnv1a(reward.sessionID.uuidString))
        start = .now
        started = true
        switch plan.kind {
        case .tooShort:
            app.haptics.lightTap()
        default:
            app.haptics.playCelebration(milestone: plan.kind == .milestone, reduced: plan.kind == .reduced)
            if let cue = plan.soundCue { app.audio.play(cue) }
        }
        try? await Task.sleep(for: .seconds(plan.summaryAt))
        revealSummary()
        try? await Task.sleep(for: .seconds(max(0, plan.duration - plan.summaryAt)))
        finished = true
    }

    private func revealSummary() {
        guard !showSummary else { return }
        showSummary = true
        let announcement: String
        if let star = reward.star {
            announcement = reward.planetBorn.map { String(localized: "\($0.name) is born. Star \(star.ordinal) added.") }
                ?? String(localized: "You did it. Star \(star.ordinal) added.")
        } else {
            announcement = String(localized: "Session ended. Your universe is unchanged.")
        }
        AccessibilityNotification.Announcement(announcement).post()
    }

    /// Tap anywhere after 1.5 s to jump to the summary; the star is placed either way.
    private func skip(plan: CelebrationPlan, force: Bool = false) {
        guard started, !showSummary else { return }
        let t = Date.now.timeIntervalSince(start)
        guard force || t >= plan.skippableAfter else { return }
        app.haptics.stopCelebration()
        app.audio.stopCues()
        start = Date.now.addingTimeInterval(-plan.summaryAt)
        revealSummary()
    }
}

/// Re-creates the focus screen's timer position so "00:00" can dissolve in
/// place (opacity 1 → 0, blur 0 → 8, scale 0.96, easeOutCubic, 0.12–0.50 s).
private struct DissolvingTimerEcho: View {
    var t: Double
    var reduced: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize: CGFloat = 88

    var body: some View {
        let u = reduced ? beat(t, 0, 0.4) : LMCurve.easeOutCubic.value(beat(t, 0.12, 0.5))
        VStack(spacing: 0) {
            Color.clear.frame(height: 80)
            Spacer()
            Text("00:00")
                .font(LMFont.timer(size: min(timerSize, 120)))
                .tracking(-2)
                .foregroundStyle(LMColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(" ").font(LMFont.voice(.title3)).padding(.top, LMSpace.xs)
            Spacer().frame(height: LMSpace.xl)
            Color.clear.frame(height: 76).padding(.bottom, LMSpace.l)
        }
        .padding(.horizontal, LMSpace.l)
        .opacity(1 - u)
        .blur(radius: 8 * u)
        .scaleEffect(1 - 0.04 * u)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
