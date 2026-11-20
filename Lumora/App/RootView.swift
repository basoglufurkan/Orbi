import SwiftUI

/// Chooses onboarding vs. the main experience, presents the focus flow as a
/// full-screen layer whenever a session (or its reward) is in progress, and
/// forwards lifecycle and calendar events to the app model.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// The opening Pell animation, once per cold launch.
    @State private var showsSplash = true
    /// iCloud restored a universe while onboarding was showing.
    @State private var showsWelcomeBack = false

    var body: some View {
        let motion = app.preferences.motion.resolve(systemReduceMotion: reduceMotion, lowPower: lowPower)
        // Gyro depth only at full motion in the foreground; otherwise depth is static.
        let parallaxAllowed = motion == .full && scenePhase == .active
        ZStack {
            #if DEBUG
            if app.launchOptions.gallery {
                OdysseyGalleryView(section: app.launchOptions.gallerySection)
            } else if app.preferences.hasCompletedOnboarding {
                MainTabView()
                    // Hidden under the focus screen: its sky and loops rest.
                    .environment(\.motionLevel, focusFlowPresented.wrappedValue ? .reduced : motion)
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
            #else
            if app.preferences.hasCompletedOnboarding {
                MainTabView()
                    .environment(\.motionLevel, focusFlowPresented.wrappedValue ? .reduced : motion)
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
            #endif
            if showsWelcomeBack {
                WelcomeBackView { showsWelcomeBack = false }
                    .transition(.opacity)
                    .zIndex(1)
            }
            if showsSplash, !app.launchOptions.isUITesting, !app.launchOptions.gallery {
                PellSplash { showsSplash = false }
                    .zIndex(1)
            }
        }
        .animation(LMCurve.emerge.animation(duration: 1.2), value: app.preferences.hasCompletedOnboarding)
        .animation(.easeInOut(duration: 0.6), value: showsWelcomeBack)
        .onChange(of: app.preferences.hasCompletedOnboarding) { was, done in
            if done, !was, !app.onboardedThisLaunch {
                showsWelcomeBack = true
                app.queueIntroOffer()
            }
            if done { app.openPendingLink() }
        }
        .fullScreenCover(isPresented: app.launchOptions.gallery ? .constant(false) : focusFlowPresented) {
            FocusFlowView()
                .environment(\.motionLevel, motion)
                .environment(\.parallax, app.parallax)
                .preferredColorScheme(app.colorScheme)
        }
        .environment(\.motionLevel, motion)
        .environment(\.parallax, app.parallax)
        .preferredColorScheme(app.colorScheme)
        // Widgets, notifications, shared web links and friends' invites.
        .onOpenURL { url in
            guard let link = DeepLink(url: url) else { return }
            Telemetry.log(.deepLinkOpened(target: link.analyticsName, web: url.scheme?.lowercased() != DeepLink.scheme))
            app.open(link)
        }
        .sheet(isPresented: joinSheetPresented) {
            TogetherSheet(minutes: app.preferences.defaultFocusMinutes, category: app.preferences.lastCategory)
                .environment(\.motionLevel, motion)
                .preferredColorScheme(app.colorScheme)
        }
        .sheet(isPresented: paywallPresented) {
            PlusPaywallView(feature: app.paywallFeature, source: app.paywallSource)
                .presentationCornerRadius(32)
                .environment(\.motionLevel, motion)
                .preferredColorScheme(app.colorScheme)
        }
        .fullScreenCover(isPresented: introOfferPresented) {
            PlusIntroOfferView()
                .environment(\.motionLevel, motion)
                .preferredColorScheme(app.colorScheme)
        }
        .onChange(of: scenePhase) { _, phase in app.handleScenePhase(phase) }
        .onChange(of: parallaxAllowed, initial: true) { _, allowed in app.parallax.isAllowed = allowed }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in app.refreshDay() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange).receive(on: RunLoop.main)) { _ in app.refreshDay() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification).receive(on: RunLoop.main)) { _ in app.refreshDay() }
    }

    /// After onboarding, once nothing else is up (a first focus finishes first).
    private var introOfferPresented: Binding<Bool> {
        Binding(
            get: { app.isShowingIntroOffer && !focusFlowPresented.wrappedValue && !showsWelcomeBack
                && !app.isShowingPaywall && app.together.pendingJoinCode == nil },
            set: { if !$0 { app.isShowingIntroOffer = false } }
        )
    }

    /// The join sheet follows an opened invite until the friends are focusing.
    private var joinSheetPresented: Binding<Bool> {
        Binding(
            // A link opened before onboarding waits until there's a universe to come back to.
            get: { app.together.pendingJoinCode != nil && app.preferences.hasCompletedOnboarding && !focusFlowPresented.wrappedValue },
            set: { if !$0 { app.together.pendingJoinCode = nil } }
        )
    }

    /// Orbi+ from a link or after the third star, once nothing else is in front.
    private var paywallPresented: Binding<Bool> {
        Binding(
            get: {
                app.isShowingPaywall && app.preferences.hasCompletedOnboarding && !focusFlowPresented.wrappedValue
                    && !joinSheetPresented.wrappedValue && !app.isShowingSettings && !app.isShowingTasks
            },
            set: { if !$0 { app.isShowingPaywall = false; app.paywallFeature = nil } }
        )
    }

    private var focusFlowPresented: Binding<Bool> {
        Binding(
            get: {
                let state = app.timer.state
                // "Later" on an unsaved session steps out until the next try.
                if app.recordErrorDeferred, state.pendingResult != nil, app.timer.pendingReward == nil { return false }
                return state.phase != .idle || state.pendingResult != nil || app.showBreakComplete
            },
            set: { presented in
                guard !presented else { return }
                if app.timer.state.phase == .preparing { app.timer.cancelPreparation() }
            })
    }
}
