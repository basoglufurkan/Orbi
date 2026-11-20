import Foundation
import Observation
import SwiftData
import SwiftUI
import os

/// The five destinations behind the orbit bar. Today is the sky and one
/// clear action; Plan holds the day's orbit, habits and tasks. The
/// Collection opens over Insights rather than taking a sixth place.
enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case today, plan, universe, odyssey, insights
    var id: String { rawValue }

    /// Where a screen link lands; the Collection's is Insights, with the
    /// Collection opened on top (`AppModel.open`).
    init(_ screen: DeepLink.Screen) {
        self = screen == .collection ? .insights : AppTab(rawValue: screen.rawValue) ?? .today
    }

    var title: String {
        switch self {
        case .today: String(localized: "Today")
        case .plan: String(localized: "Plan")
        case .universe: String(localized: "Universe")
        case .odyssey: String(localized: "Odyssey")
        case .insights: String(localized: "Insights")
        }
    }

    var symbol: String {
        switch self {
        case .today: "sparkle"
        case .plan: "calendar"
        case .universe: "circle.circle"
        case .odyssey: "location.north"
        case .insights: "chart.bar"
        }
    }
}

/// Composition root. Builds every service once, wires dependencies, and owns
/// app-wide navigation state. Views receive it through the environment.
@MainActor
@Observable
final class AppModel {
    let dataStore: DataStore
    let clock: DateProvider
    let rules: RewardRules
    let launchOptions: LaunchOptions

    let timer: FocusSessionController
    let rewards: RewardService
    let tasks: TaskStore
    let habits: HabitStore
    let haptics: HapticsService
    let audio: AudioService
    let notifications: NotificationService
    let liveActivities: LiveActivityService
    let widgets: WidgetSyncService
    let shield: DistractionShielding
    /// Gyro depth for backgrounds; visual only, never read by the timer.
    let parallax: MotionParallaxService
    /// The game layer: worlds, expeditions, terraforming, horizons, ranks.
    let odyssey: OdysseyService
    let watch = WatchSyncService()
    let together: TogetherService
    let plus: PlusStore
    /// Pell's notes, peeking in from the edge of the screen.
    let pell = PellGuide()

    var selectedTab: AppTab = .today
    /// Object the universe explorer should fly to when it next appears.
    var universeFocus: UUID?
    var isShowingSettings = false
    var isShowingTasks = false
    /// Every cosmic artifact, opened over Insights (or from Today's latest).
    var isShowingCollection = false
    /// Task the setup screen should preselect when it next opens.
    var setupTaskID: UUID?
    /// Length and category a focus link asked the setup screen to start from.
    var setupPrefill: (minutes: Int?, category: FocusCategory?)?
    /// A link asked for the Year in review; Insights opens it on arrival.
    var pendingYearInReview = false
    /// A link opened before onboarding finished; followed once it has.
    var pendingLink: DeepLink?
    /// Set by the Tasks sheet: start focusing on this task once it closes.
    var focusAfterTasks: UUID?
    /// Today's orbit: the day plan drawn as a route (full screen).
    var isShowingDayOrbit = false
    /// The hour-by-hour planner, opened from Plan.
    var isShowingPlanner = false
    /// A focus asked for from a plan block while a plan screen was up; it
    /// starts once that screen has gone (a full-screen cover can't appear on top).
    var pendingPlanFocus: PlanFocusRequest?
    /// The Habits sheet, opened from Plan.
    var isShowingHabits = false
    /// Where the Habits sheet was opened from, for analytics.
    var habitsSource = "link"
    /// A focus asked for from a habit while its sheet was up; it starts once the sheet has gone.
    var pendingHabitFocus: UUID?
    /// Habits a recorded session kept, by session, for its summary.
    var habitsKeptByFocus: [UUID: [String]] = [:]
    /// Alarms for plan blocks (AlarmKit, iOS 26.1+).
    let planAlarms = PlanAlarmService()
    /// World the Odyssey tab should open when it next appears.
    var odysseyFocusWorld: Int?
    /// A break ran out while the app was open; offer the next step.
    var showBreakComplete = false
    /// The Orbi+ paywall over the main screens, from a link. Locked items
    /// inside sheets present their own.
    var isShowingPaywall = false
    var paywallFeature: PlusFeature?
    /// Why the root paywall opened, for analytics.
    var paywallSource = "link"
    /// Where the next focus session is being started from, for analytics.
    var focusSource = "app"
    /// The person stepped past a session that couldn't be saved yet; it's
    /// kept and retried whenever the app comes forward.
    var recordErrorDeferred = false
    /// Bumped on midnight / time-zone changes so day-based views recompute.
    private(set) var dayToken = 0
    /// Bumped when iCloud brought changes that replace rows views hold on to.
    private(set) var syncToken = 0
    /// Onboarding was finished on this device this launch, so a universe
    /// appearing now is the user's own doing, not iCloud bringing one back.
    private(set) var onboardedThisLaunch = false
    let cloud: CloudSync
    /// Optional Sign in with Apple; everything works without it.
    let account = AppleAccount()
    private(set) var lastError: String?

    @ObservationIgnored private let logger = Logger(subsystem: "com.mobapptech.lumora", category: "App")

    init(container: ModelContainer, launchOptions: LaunchOptions = .parse(),
         clock providedClock: DateProvider = SystemDateProvider(), cloudSync: Bool = false) {
        let clock: DateProvider = {
            #if DEBUG
            if let minutes = launchOptions.clockMinutes { return OffsetDateProvider(minutesAfterMidnight: minutes) }
            #endif
            return providedClock
        }()
        let dataStore = DataStore(container: container)
        self.cloud = CloudSync(isActive: cloudSync)
        if launchOptions.resetData {
            do {
                try dataStore.eraseAll()
            } catch {
                Logger(subsystem: "com.mobapptech.lumora", category: "App").error("Reset failed: \(error.localizedDescription)")
            }
        }

        self.dataStore = dataStore
        self.clock = clock
        self.rules = .standard
        self.launchOptions = launchOptions
        self.parallax = MotionParallaxService(fakeTilt: launchOptions.fakeTilt)

        let haptics = HapticsService()
        let audio = AudioService()
        let notifications = NotificationService()
        let liveActivities = LiveActivityService()
        let widgets = WidgetSyncService(context: dataStore.context, clock: clock)
        // UI tests and in-memory runs never touch the real Screen Time settings.
        let shield: DistractionShielding = launchOptions.isUITesting || launchOptions.inMemory
            ? UnavailableDistractionShield() : ScreenTimeShield()
        let rewards = RewardService(context: dataStore.context, clock: clock,
                                    goalMinutes: { dataStore.preferences().dailyGoalMinutes })

        haptics.isEnabled = { dataStore.preferences().hapticsEnabled }
        audio.cuesEnabled = { dataStore.preferences().soundEnabled }

        let context = dataStore.context
        let effects = TimerEffectsCoordinator(
            preferences: { dataStore.preferences() }, haptics: haptics, audio: audio,
            notifications: notifications, liveActivities: liveActivities, widgets: widgets,
            shield: shield,
            nextStarNumber: {
                let star = CelestialKind.star.rawValue
                let count = (try? context.fetchCount(FetchDescriptor<CelestialObject>(predicate: #Predicate { $0.kindRaw == star }))) ?? 0
                return count + 1
            })

        let timer = FocusSessionController(
            store: SwiftDataTimerStateStore(context: dataStore.context),
            recorder: rewards, effects: effects, clock: clock,
            timerDefaults: { dataStore.preferences().timerDefaults })
        #if DEBUG
        let scale = launchOptions.timeScale
        timer.timeScale = { scale > 1 ? scale : DebugSettings.timeScale }
        #endif

        self.haptics = haptics
        self.audio = audio
        self.notifications = notifications
        self.liveActivities = liveActivities
        self.widgets = widgets
        self.shield = shield
        self.rewards = rewards
        self.tasks = TaskStore(context: dataStore.context, clock: clock)
        self.habits = HabitStore(context: dataStore.context, clock: clock)
        self.timer = timer
        let odyssey = OdysseyService(context: dataStore.context, clock: clock)
        self.odyssey = odyssey
        let togetherBackend: TogetherBackend
        #if DEBUG
        togetherBackend = launchOptions.togetherDemo
            ? LocalTogetherBackend(simulatedFriends: ["Ece", "Mert", "Ayla", "Deniz"]) : CloudKitTogetherBackend()
        #else
        togetherBackend = CloudKitTogetherBackend()
        #endif
        let together = TogetherService(backend: togetherBackend, context: dataStore.context, clock: clock)
        together.startFocus = { [weak timer] config in
            guard let timer, !timer.state.phase.isFocusActive else { return false }
            effects.focusContext = { ("together", true) }
            defer { effects.focusContext = nil }
            timer.start(config)
            return timer.state.phase == .focusing
        }
        self.together = together
        // Analytics first, so RevenueCat can be told Firebase's install ID.
        Telemetry.start(enabled: !launchOptions.isUITesting && !launchOptions.inMemory && !LaunchOptions.isRunningUnitTests)
        let plus = PlusStore(override: launchOptions.plusOverride,
                             enabled: !launchOptions.isUITesting && !launchOptions.inMemory && !LaunchOptions.isRunningUnitTests)
        self.plus = plus
        // Orbi+ ending puts back the free sky, sound and ship finish.
        plus.didChange = { [weak self, weak odyssey] _ in
            odyssey?.refreshPlus()
            self?.updateTelemetryProperties()
        }
        // Each recorded session can make worlds emerge, land the ship, or
        // complete a horizon. Idempotent, so duplicates are harmless.
        rewards.didCommit = { [weak self, weak odyssey, weak together] reward in
            odyssey?.sync(after: reward.sessionID)
            self?.creditHabits(after: reward)
            self?.logTelemetry(for: reward)
            Task { await together?.sessionRecorded(sessionID: reward.sessionID, completed: reward.outcome == .completed) }
        }
        odyssey.didChange = { [weak widgets] in widgets?.publish(goalMinutes: dataStore.preferences().dailyGoalMinutes) }
        widgets.odysseyInfo = { [weak odyssey] in
            guard let s = odyssey?.snapshot else { return (nil, nil, 0) }
            return (s.expedition?.world.blueprint.name, s.expedition?.fraction, s.balance)
        }

        effects.focusContext = { [weak self] in
            let source = self?.focusSource ?? "app"
            self?.focusSource = "app"
            return (source, false)
        }
        effects.onEvent = { [weak self] event in
            if case .breakFinished(_, skipped: false) = event { self?.showBreakComplete = true }
            if case .focusStarted = event {
                self?.showBreakComplete = false
                // Today has its focus now: no invitation tonight.
                self?.syncReminders()
            }
            self?.watch.publish()
        }

        // The daily invitation became "only on days without a focus" and is on
        // by default, in the early evening; earlier installs switch over once.
        let invitationKey = "lumora.dailyInvitation.v2"
        if !UserDefaults.standard.bool(forKey: invitationKey) {
            UserDefaults.standard.set(true, forKey: invitationKey)
            let p = preferences
            if !p.dailyReminderEnabled {
                p.dailyReminderEnabled = true
                if p.dailyReminderHour == 9, p.dailyReminderMinute == 0 { p.dailyReminderHour = 18 }
                dataStore.save()
            }
        }

        if launchOptions.skipOnboarding, !preferences.hasCompletedOnboarding {
            completeOnboarding(name: "")
        }
        if launchOptions.introOffer { queueIntroOffer() }
        #if DEBUG
        if launchOptions.demoSessions > 0 {
            DemoDataSeeder.seed(sessions: launchOptions.demoSessions, into: self)
        }
        if launchOptions.demoPlan, preferences.hasCompletedOnboarding {
            DemoDataSeeder.seedPlan(into: self)
        }
        if launchOptions.demoHabits, preferences.hasCompletedOnboarding {
            DemoDataSeeder.seedHabits(into: self)
        }
        #endif
        dataStore.mergeDuplicates()
        if preferences.hasCompletedOnboarding {
            let universe = dataStore.ensureUniverse(createdAt: clock.now, calendar: clock.calendar)
            // A newer placement redraws the sky once, so every device agrees.
            let layoutKey = "lumora.skyLayoutVersion"
            let outdated = UserDefaults.standard.integer(forKey: layoutKey) < UniverseLayout.version
            rewards.rebuildUniverseIfNeeded(createdAt: universe.createdAt, force: outdated)
            UserDefaults.standard.set(UniverseLayout.version, forKey: layoutKey)
        }
        cloud.didReceiveChanges = { [weak self] in self?.applySyncedChanges() }
        notifications.onOpenLink = { [weak self] link in
            self?.focusSource = "notification"
            self?.open(link)
        }
        notifications.onPlanFocus = { [weak self] block in self?.requestPlanFocus(block, source: "notification") }
        notifications.onHabitDone = { [weak self] habit, day in self?.keepHabit(habit, day: day, source: "notification") }
        // Habits: reminders and widgets follow every change.
        habits.didSave = { [weak self] in self?.syncHabits() }
        widgets.habits = { [weak self] in self?.habits.widgetItems() ?? [] }
        // The day plan: reminders, alarms and widgets follow every task change.
        tasks.didSave = { [weak self] in self?.syncPlan() }
        liveActivities.nextBlock = { [weak self] in self?.nextPlanBlock() }
        widgets.planBlocks = { [weak self] in self?.widgetPlanBlocks() ?? [] }
        // Nothing should cover what tests and screenshots look at.
        pell.isEnabled = !launchOptions.isUITesting && !launchOptions.gallery
        // Bring the unsaved session back on screen rather than ignore the tap.
        timer.onBlockedStart = { [weak self] in self?.recordErrorDeferred = false }
        timer.reconcile()
        // A session together that was running when Lumora last quit: back into the room.
        let focusing = timer.state.phase.isFocusActive
        Task { [together] in await together.resume(timerRunning: focusing) }
        // Whatever happened while Lumora wasn't running, the shield and the
        // Control Center toggle now match the timer.
        settleOutsideState()
        // Catch up with history recorded before the Odyssey existed (or while away).
        odyssey.sync()
        audio.warmUp()

        watch.currentState = { [weak self] in self?.watchState() ?? [:] }
        watch.perform = { [weak self] action, minutes in self?.performWatchAction(action, minutes: minutes) }
        // A recorded session refreshes the widgets first; then the watch sees today's new minutes.
        let refreshWidgets = odyssey.didChange
        odyssey.didChange = { [weak self] in
            refreshWidgets?()
            self?.watch.publish()
        }
        logAppOpened()
        // The first foregrounding doesn't always arrive as a scene-phase change:
        // bring the plan's reminders, alarms and widgets up to date now.
        if !LaunchOptions.isRunningUnitTests {
            syncPlan()
            syncHabits()
        }
        if !launchOptions.isUITesting {
            watch.activate()
            Task { [account] in await account.refresh() }
        }
    }

    // MARK: Apple Watch

    /// What the watch draws. Keys mirror LumoraWatch/WatchKeys.swift.
    private func watchState() -> [String: Any] {
        let now = clock.now
        let prefs = preferences
        var state: [String: Any] = ["phase": "idle", "defaultMinutes": prefs.defaultFocusMinutes]
        if let snapshot = WidgetSnapshot.load() {
            state["todayMinutes"] = snapshot.minutesToday(now: now, calendar: clock.calendar)
            state["goalMinutes"] = snapshot.goalMinutes
            state["stars"] = snapshot.totalStars
        }
        let timerState = timer.state
        if let segment = timerState.segment {
            // Real seconds, so the watch's ring and clock match the phone at any speed.
            state["duration"] = Double(segment.plannedSeconds) / segment.timeScale
            state["remaining"] = segment.remaining(at: now) / segment.timeScale
            if let deadline = segment.deadline { state["endsAt"] = deadline.timeIntervalSince1970 }
            if let focus = segment.focus {
                state["category"] = focus.category.displayName
                state["intention"] = focus.intention
            }
            switch timerState.phase {
            case .focusing: state["phase"] = "focusing"
            case .paused: state["phase"] = "paused"
            case .onBreak: state["phase"] = "break"
            default: break
            }
        }
        return state
    }

    private func performWatchAction(_ action: WatchSyncService.Action, minutes: Int?) {
        let runner = FocusIntentRunner(timer: timer, dataStore: dataStore, presets: .standard)
        switch action {
        case .start:
            focusSource = "watch"
            _ = try? runner.start(minutes: minutes, category: nil)
        case .pause: _ = runner.pause()
        case .resume: _ = runner.resume()
        case .end: _ = runner.end()
        }
    }

    // MARK: Derived

    var preferences: UserPreferences { _ = syncToken; return dataStore.preferences() }

    var colorScheme: ColorScheme? {
        switch preferences.appearance {
        case .night: .dark
        case .dawn: .light
        case .auto: nil
        }
    }

    var today: DayKey { _ = dayToken; return DayKey(clock.now, calendar: clock.calendar) }

    /// Day N of the user's universe.
    var universeDay: Int {
        _ = dayToken
        guard let created = dataStore.progress()?.createdAt else { return 1 }
        let cal = clock.calendar
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: created), to: cal.startOfDay(for: clock.now)).day ?? 0
        return max(1, days + 1)
    }

    // MARK: Lifecycle

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            timer.reconcile()
            if recordErrorDeferred {
                timer.retryPendingRecord()
                // Saved now, or still failing: either way, show the flow again.
                recordErrorDeferred = false
            }
            liveActivities.endOrphans(keeping: timer.state.segment != nil)
            refreshDay()
            syncReminders()
            syncPlan()
            syncHabits()
            updateTelemetryProperties()
        case .background:
            dataStore.save()
            widgets.publish(goalMinutes: preferences.dailyGoalMinutes)
        default:
            break
        }
    }

    /// Midnight, time-zone and significant time changes.
    func refreshDay() {
        dayToken &+= 1
        timer.reconcile()
        widgets.publish(goalMinutes: preferences.dailyGoalMinutes)
    }

    /// Called before an App Intent acts on the timer. The process may have
    /// been launched in the background just for the intent (no scene phase
    /// change), so reattach to the Live Activity a previous process started —
    /// otherwise pausing from it couldn't update it — then catch up with time.
    func prepareForIntent() {
        focusSource = "shortcut"
        liveActivities.endOrphans(keeping: timer.state.segment != nil)
        timer.reconcile()
    }

    /// History arrived from another device: fold duplicate rows into one and
    /// redraw the sky if new sessions came with it.
    func applySyncedChanges() {
        let merged = dataStore.mergeDuplicates()
        var redrawn = false
        if preferences.hasCompletedOnboarding {
            let universe = dataStore.ensureUniverse(createdAt: clock.now, calendar: clock.calendar)
            redrawn = rewards.rebuildUniverseIfNeeded(createdAt: universe.createdAt)
        }
        if merged || redrawn {
            syncToken &+= 1
            odyssey.sync()
            widgets.publish(goalMinutes: preferences.dailyGoalMinutes)
        }
        // Blocks planned on another device remind here too.
        syncPlan()
        syncHabits()
    }

    func syncReminders() {
        let p = preferences
        let now = clock.now, calendar = clock.calendar
        let invitation = (enabled: p.dailyReminderEnabled && p.hasCompletedOnboarding, hour: p.dailyReminderHour,
                          minute: p.dailyReminderMinute, focusedToday: hasFocusedToday)
        Task { [notifications] in
            await notifications.updateDailyReminder(enabled: invitation.enabled, hour: invitation.hour, minute: invitation.minute,
                                                    focusedToday: invitation.focusedToday, now: now, calendar: calendar)
        }
        // The next few weeks' rare events; refreshed whenever the app comes forward.
        var events: [CosmicEvent] = []
        for week in 0..<4 {
            let event = CosmicCalendar.event(inWeekOf: now.addingTimeInterval(Double(week) * 7 * 86_400), calendar: calendar)
            if !events.contains(event) { events.append(event) }
        }
        let enabled = p.rareEventNotifications && p.hasCompletedOnboarding
        Task { [notifications] in
            await notifications.updateEventReminders(events, enabled: enabled, now: now, calendar: calendar)
        }
    }

    /// A session is running, or one was recorded today.
    var hasFocusedToday: Bool {
        if timer.state.phase.isFocusActive { return true }
        let today = DayKey(clock.now, calendar: clock.calendar).rawValue
        var descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.dayKeyRaw == today })
        descriptor.fetchLimit = 1
        return ((try? dataStore.context.fetchCount(descriptor)) ?? 0) > 0
    }

    // MARK: Intents

    func completeOnboarding(name: String) {
        let p = preferences
        p.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        p.hasCompletedOnboarding = true
        onboardedThisLaunch = true
        dataStore.ensureUniverse(createdAt: clock.now, calendar: clock.calendar)
        dataStore.save()
        widgets.publish(goalMinutes: p.dailyGoalMinutes)
        syncReminders()
    }

    /// Signed in with Apple: Apple shares a name only the first time; use it
    /// unless the universe already has one.
    func signedInWithApple(givenName: String?) {
        Telemetry.log(.appleSignInCompleted)
        if let givenName, preferences.displayName.isEmpty {
            preferences.displayName = givenName
            dataStore.save()
        }
    }

    func savePreferences() {
        dataStore.save()
        widgets.publish(goalMinutes: preferences.dailyGoalMinutes)
    }

    /// Opens the setup screen with a planned task already chosen.
    func beginFocus(taskID: UUID?) {
        setupTaskID = taskID
        if taskID != nil { focusSource = "task" }
        timer.prepare()
    }

    /// Follows a link: widgets, notifications, shared web links. Links only
    /// navigate. A running session stays in front, and a focus link opens the
    /// setup screen without starting anything.
    func open(_ link: DeepLink) {
        guard preferences.hasCompletedOnboarding else {
            pendingLink = link
            return
        }
        if case let .join(code) = link {
            guard !timer.state.phase.isFocusActive else { return }
            together.pendingJoinCode = code
            return
        }
        guard timer.state.phase == .idle, timer.state.pendingResult == nil, !showBreakComplete else { return }
        let hadSheet = isShowingSettings || isShowingTasks || isShowingPlanner || isShowingDayOrbit || isShowingHabits
            || isShowingCollection
        // Every link but the habits link leaves the Habits sheet.
        if link != .habits { isShowingHabits = false }
        // Every link leaves the plan screens; only the plan link reopens one.
        if link != .plan {
            isShowingPlanner = false
            isShowingDayOrbit = false
        }
        // Only the Collection's own link keeps it open.
        if link != .screen(.collection) { isShowingCollection = false }
        switch link {
        case let .screen(screen):
            isShowingSettings = false
            isShowingTasks = false
            selectedTab = AppTab(screen)
            // The Collection lives over Insights now.
            guard screen == .collection, !isShowingCollection else { return }
            guard hadSheet else { isShowingCollection = true; return }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.isShowingCollection = true
            }
        case .yearInReview:
            isShowingSettings = false
            isShowingTasks = false
            pendingYearInReview = true
            selectedTab = .insights
        case .settings:
            isShowingTasks = false
            guard hadSheet, !isShowingSettings else { isShowingSettings = true; return }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.isShowingSettings = true
            }
        case .plan:
            isShowingSettings = false
            isShowingTasks = false
            isShowingPlanner = false
            selectedTab = .plan
            guard !isShowingDayOrbit else { return }
            guard hadSheet else { isShowingDayOrbit = true; return }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.isShowingDayOrbit = true
            }
        case .plus:
            isShowingSettings = false
            isShowingTasks = false
            guard !plus.isActive else { return }
            guard hadSheet else { return showPaywall(source: "link") }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.showPaywall(source: "link")
            }
        case .habits:
            isShowingSettings = false
            isShowingTasks = false
            selectedTab = .plan
            guard !isShowingHabits else { return }
            guard hadSheet else { isShowingHabits = true; return }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.isShowingHabits = true
            }
        case .tasks:
            isShowingSettings = false
            selectedTab = .plan
            guard hadSheet, !isShowingTasks else { isShowingTasks = true; return }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.isShowingTasks = true
            }
        case let .focus(minutes, category):
            if focusSource == "app" { focusSource = "link" }
            isShowingSettings = false
            isShowingTasks = false
            setupPrefill = (minutes, category)
            guard hadSheet else { return timer.prepare() }
            // The focus flow is a full-screen cover; it can only appear once the sheet is gone.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.timer.state.phase == .idle else { return }
                self.timer.prepare()
            }
        case .join:
            break
        }
    }

    func showPaywall(_ feature: PlusFeature? = nil, source: String) {
        paywallFeature = feature
        paywallSource = source
        isShowingPaywall = true
    }

    /// The free-trial offer (then Orbi+ for life) that follows onboarding,
    /// or a universe coming back from iCloud on a new install, once. It waits while a first focus runs, and survives a relaunch until shown.
    var isShowingIntroOffer: Bool {
        get { introOfferPending && preferences.hasCompletedOnboarding }
        set { if !newValue { introOfferPending = false } }
    }
    private static let introOfferKey = "lumora.plus.introOfferPending"
    private var introOfferPending = UserDefaults.standard.bool(forKey: AppModel.introOfferKey) {
        didSet { UserDefaults.standard.set(introOfferPending, forKey: Self.introOfferKey) }
    }

    func queueIntroOffer() {
        guard !plus.isActive, !launchOptions.isUITesting, !launchOptions.gallery else { return }
        introOfferPending = true
    }

    /// Two days before a free trial turns into a paid plan.
    func scheduleTrialReminder(trialDays: Int, price: String) async {
        let day = PlusIntroOfferView.reminderDay(trialDays: trialDays)
        guard let date = clock.calendar.date(byAdding: .day, value: day, to: clock.now) else { return }
        if await notifications.authorizationStatus() == .notDetermined {
            await notifications.requestAuthorization(source: "trial_reminder")
        }
        notifications.scheduleTrialReminder(at: date, daysLeft: trialDays - day, price: price)
    }

    // MARK: Analytics

    private func logAppOpened() {
        guard preferences.hasCompletedOnboarding else { return }
        let created = preferences.universeCreatedAt ?? clock.now
        let days = clock.calendar.dateComponents([.day], from: created, to: clock.now).day ?? 0
        Telemetry.log(.appOpened(daysSinceInstall: max(0, days), universeDay: universeDay))
        updateTelemetryProperties()
    }

    /// Coarse traits for segmenting reports; refreshed at launch, on return and when Orbi+ changes.
    func updateTelemetryProperties() {
        let p = preferences
        let plusStatus = plus.isActive ? (plus.isLifetime ? "plus_lifetime" : "plus") : "free"
        Telemetry.set(.plusStatus, plusStatus)
        Telemetry.set(.appearance, p.appearance.rawValue)
        Telemetry.set(.ambience, p.ambient.playable.rawValue)
        Telemetry.set(.dailyGoal, TelemetryBucket.goal(p.dailyGoalMinutes))
        let star = CelestialKind.star.rawValue
        let stars = (try? dataStore.context.fetchCount(FetchDescriptor<CelestialObject>(predicate: #Predicate { $0.kindRaw == star }))) ?? 0
        Telemetry.set(.universeSize, TelemetryBucket.sessions(stars))
        Telemetry.set(.odysseyRank, String(odyssey.snapshot.rank.level))
        Telemetry.set(.iCloudSync, cloud.isActive ? "on" : "off")
        Telemetry.set(.shield, FeatureFlags.distractionShield && p.distractionShieldEnabled ? "on" : "off")
        Telemetry.set(.skyTheme, SkyTheme.current(raw: UserDefaults.standard.string(forKey: SkyPreferences.theme) ?? "",
                                                  plusActive: plus.isActive).rawValue)
        Telemetry.set(.appleSignIn, account.isSignedIn ? "yes" : "no")
    }

    /// What one recorded session brought: its star, new objects, goals and Odyssey news.
    private func logTelemetry(for reward: SessionReward) {
        if reward.star != nil {
            Telemetry.log(.starEarned(category: reward.category.rawValue, minutes: reward.focusedMinutes,
                                      starNumber: reward.totalQualifyingSessions, todayStars: reward.todayStars.count))
        } else {
            Telemetry.log(.sessionWithoutStar(focusedMinutes: reward.focusedMinutes))
        }
        if reward.constellationFormed != nil {
            let kind = CelestialKind.constellation.rawValue
            let count = (try? dataStore.context.fetchCount(FetchDescriptor<CelestialObject>(predicate: #Predicate { $0.kindRaw == kind }))) ?? 0
            Telemetry.log(.constellationFormed(count: count))
        }
        if let planet = reward.planetBorn { Telemetry.log(.planetBorn(ordinal: planet.ordinal)) }
        if reward.moonCaptured != nil { Telemetry.log(.moonCaptured) }
        for achievement in reward.newAchievements {
            Telemetry.log(.achievementUnlocked(id: achievement.id, milestone: achievement.isMilestone))
        }
        if reward.goalMinutes > 0, reward.todayMinutesBefore < reward.goalMinutes, reward.todayMinutes >= reward.goalMinutes {
            Telemetry.log(.dailyGoalReached(goalMinutes: reward.goalMinutes, todayMinutes: reward.todayMinutes))
        }
        if let task = reward.task {
            Telemetry.log(.taskProgressed(done: task.progress.sessionsDone, planned: task.progress.estimate,
                                          completed: task.isCompleted))
        }
        let summary = odyssey.summary(for: reward.sessionID)
        if summary.stardust > 0 { Telemetry.log(.stardustEarned(amount: summary.stardust)) }
        for world in summary.emerged {
            Telemetry.log(.worldEmerged(ordinal: world.ordinal, rarity: world.blueprint.rarity.rawValue))
        }
        if let galaxy = summary.galaxyIgnited { Telemetry.log(.galaxyIgnited(index: galaxy.index)) }
        if let arrival = summary.arrival { Telemetry.log(.expeditionArrived(ordinal: arrival.world.ordinal)) }
        if let horizon = summary.horizon, horizon.status == .achieved {
            Telemetry.log(.horizonReached(kind: horizon.kind.rawValue, chain: odyssey.snapshot.horizonChain))
        }
        if let rank = summary.rankUp { Telemetry.log(.rankUp(level: rank.level)) }
        if let event = summary.event { Telemetry.log(.cosmicEventWitnessed(kind: event.kind.rawValue)) }
    }

    /// Follows a link that arrived before onboarding finished.
    func openPendingLink() {
        guard let link = pendingLink else { return }
        pendingLink = nil
        open(link)
    }

    func showInUniverse(_ objectID: UUID?) {
        universeFocus = objectID
        selectedTab = .universe
    }

    /// "Erase all data" — the only destructive path. Returns to onboarding.
    func eraseAllData() {
        Telemetry.log(.dataErased)
        timer.reset()
        audio.stopAmbient()
        notifications.cancelTimerNotifications()
        let now = clock.now, calendar = clock.calendar
        Task { [notifications] in
            await notifications.updateDailyReminder(enabled: false, hour: 0, minute: 0, focusedToday: false,
                                                    now: now, calendar: calendar)
        }
        liveActivities.endOrphans(keeping: false)
        do {
            try dataStore.eraseAll()
        } catch {
            lastError = error.localizedDescription
            logger.error("Erase failed: \(error.localizedDescription)")
        }
        selectedTab = .today
        isShowingSettings = false
        isShowingTasks = false
        isShowingCollection = false
        isShowingPlanner = false
        isShowingDayOrbit = false
        isShowingHabits = false
        habitsKeptByFocus = [:]
        widgets.publish(goalMinutes: preferences.dailyGoalMinutes)
        // No plan is left: its reminders and alarms go too.
        syncPlan()
        syncHabits()
        // The timer was reset without events, so nothing else lifts these.
        settleOutsideState()
        watch.publish()
        pell.reset()
    }

    // MARK: Distraction shield

    enum ShieldSwitch { case on, off, needsPicks, denied }

    /// Turns the shield on (asking for Screen Time access the first time)
    /// or off. Shared by Settings and the focus setup screen.
    func setShieldEnabled(_ on: Bool) async -> ShieldSwitch {
        guard let shield = shield as? ScreenTimeShield else { return .denied }
        guard on else {
            preferences.distractionShieldEnabled = false
            savePreferences()
            shield.endShielding()
            return .off
        }
        if !shield.isAuthorized { try? await shield.requestAuthorization() }
        guard shield.isAuthorized else { return .denied }
        preferences.distractionShieldEnabled = true
        savePreferences()
        if shield.pickedCount == 0 { return .needsPicks }
        applyShieldNow()
        return .on
    }

    /// The picks or the switch changed mid-session: shield right away.
    func applyShieldNow() {
        guard preferences.distractionShieldEnabled, timer.state.phase == .focusing,
              let deadline = timer.state.segment?.deadline else { return }
        shield.beginShielding(until: deadline)
    }

    /// Brings what lives outside the app (the Screen Time shield, Control
    /// Center's toggle) in line with the timer.
    private func settleOutsideState() {
        let state = timer.state
        if state.phase != .focusing { shield.endShielding() }
        FocusControlState.publish(active: state.phase.isFocusActive, endsAt: state.segment?.deadline,
                                  pausedAt: state.segment?.pausedAt)
    }
}
