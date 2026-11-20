import Foundation

/// Every analytics event Lumora sends, in one place. Names are GA4-safe
/// (snake_case, ≤ 40 characters); purchases also use the standard GA4
/// e-commerce events (`begin_checkout`, `purchase`) so revenue reports work.
/// The README's "Analytics" section lists them with their parameters.
enum TelemetryEvent {
    // MARK: Onboarding and app
    case onboardingStarted
    case onboardingStep(step: String)
    case onboardingCompleted(nameGiven: Bool, appleSignIn: Bool)
    case appOpened(daysSinceInstall: Int, universeDay: Int)
    case screenView(screen: String)
    case deepLinkOpened(target: String, web: Bool)
    case notificationOpened(kind: String)

    // MARK: Focus
    case focusSetupOpened(source: String)
    case focusStarted(minutes: Int, category: String, ambience: String, hasIntention: Bool, fromTask: Bool,
                      shield: Bool, together: Bool, source: String)
    case focusPaused(elapsedMinutes: Int, pauseCount: Int)
    case focusResumed(pauseCount: Int)
    case focusCompleted(minutes: Int, category: String, pauses: Int)
    case focusEndedEarly(plannedMinutes: Int, focusedMinutes: Int, category: String, pauses: Int, percent: Int)
    case focusAutoEnded(plannedMinutes: Int, focusedMinutes: Int)
    case ambienceChanged(sound: String, during: String)
    case breakStarted(minutes: Int, long: Bool)
    case breakFinished(skipped: Bool)

    // MARK: Rewards
    case starEarned(category: String, minutes: Int, starNumber: Int, todayStars: Int)
    case sessionWithoutStar(focusedMinutes: Int)
    case constellationFormed(count: Int)
    case planetBorn(ordinal: Int)
    case moonCaptured
    case achievementUnlocked(id: String, milestone: Bool)
    case dailyGoalReached(goalMinutes: Int, todayMinutes: Int)
    case taskProgressed(done: Int, planned: Int, completed: Bool)

    // MARK: Universe
    case celestialOpened(kind: String)
    case universeShared(kind: String)
    case skyThemeChanged(theme: String)
    case skyOptionChanged(option: String, on: Bool)
    case yearReviewOpened(sessions: Int)
    case yearReviewShared

    // MARK: Odyssey
    case stardustEarned(amount: Int)
    case worldEmerged(ordinal: Int, rarity: String)
    case galaxyIgnited(index: Int)
    case coursePlotted(ordinal: Int, cost: Int)
    case expeditionRecalled
    case expeditionArrived(ordinal: Int)
    case shipPartBought(part: String, price: Int, plus: Bool)
    case shipPartEquipped(part: String)
    case horizonStarted(kind: String, target: Int)
    case horizonReached(kind: String, chain: Int)
    case rankUp(level: Int)
    case cosmicEventWitnessed(kind: String)

    // MARK: Tasks
    case taskCreated(hasDueDate: Bool, sessions: Int)
    case taskCompleted(viaFocus: Bool)
    case taskArchived

    // MARK: Day plan
    case planBlockSaved(isNew: Bool, minutes: Int, reminderMinutes: Int, atStart: Bool, alarm: Bool)
    case planShifted(minutes: Int, blocks: Int)
    case planFocusStarted(minutes: Int, during: Bool, source: String)
    case planOrbitOpened(blocks: Int, lit: Int)

    // MARK: Habits
    case habitCreated(cadence: String, focusMinutes: Int, reminder: Bool, template: String)
    case habitCheckedIn(source: String, streak: Int, backfill: Bool)
    case habitArchived(total: Int)
    case habitsOpened(habits: Int, keptToday: Int, source: String)

    // MARK: Focus together
    case togetherRoomCreated(minutes: Int)
    case togetherJoined(viaLink: Bool)
    case togetherStarted(role: String)
    case togetherInviteShared
    case togetherFailed(reason: String)

    // MARK: Insights
    case insightsPeriodChanged(period: String)
    case insightsHistoryBrowsed(period: String, back: Int)
    case csvExported(sessions: Int)

    // MARK: Settings and data
    case settingChanged(setting: String, value: String)
    case notificationPermission(granted: Bool, source: String)
    case iCloudSyncChanged(on: Bool)
    case appleSignInCompleted
    case dataExported
    case dataErased
    case analyticsOptOut

    // MARK: Orbi+ and purchases
    case lockedFeatureTapped(feature: String, screen: String)
    case paywallViewed(source: String, feature: String?, plans: Int, availability: String)
    case paywallPlanSelected(plan: String)
    case paywallDismissed(source: String, seconds: Int, purchased: Bool)
    /// GA4 standard: the purchase sheet is about to open.
    case beginCheckout(PurchaseInfo)
    /// GA4 standard: money changed hands (not sent for a free trial start).
    case purchase(PurchaseInfo, transactionID: String?)
    case trialStarted(PurchaseInfo)
    case purchaseCompleted(PurchaseInfo, trial: Bool)
    case purchaseCancelled(plan: String)
    case purchasePending(plan: String)
    case purchaseFailed(plan: String, error: String)
    case restoreStarted
    case restoreCompleted(found: Bool)
    case restoreFailed(error: String)
    case plusStatusChanged(from: String, to: String)
    case manageSubscriptionOpened
    case offeringsFailed(error: String)

    /// What was bought, for purchase events.
    struct PurchaseInfo: Equatable {
        var plan: String
        var productID: String
        var price: Double
        var currency: String
        var trialDays: Int?
        var source: String
    }

    // MARK: Names

    var name: String {
        switch self {
        case .onboardingStarted: "onboarding_started"
        case .onboardingStep: "onboarding_step"
        case .onboardingCompleted: "onboarding_completed"
        case .appOpened: "app_opened"
        case .screenView: "screen_view"
        case .deepLinkOpened: "deep_link_opened"
        case .notificationOpened: "notification_opened"
        case .focusSetupOpened: "focus_setup_opened"
        case .focusStarted: "focus_started"
        case .focusPaused: "focus_paused"
        case .focusResumed: "focus_resumed"
        case .focusCompleted: "focus_completed"
        case .focusEndedEarly: "focus_ended_early"
        case .focusAutoEnded: "focus_auto_ended"
        case .ambienceChanged: "ambience_changed"
        case .breakStarted: "break_started"
        case .breakFinished: "break_finished"
        case .starEarned: "star_earned"
        case .sessionWithoutStar: "session_without_star"
        case .constellationFormed: "constellation_formed"
        case .planetBorn: "planet_born"
        case .moonCaptured: "moon_captured"
        case .achievementUnlocked: "achievement_unlocked"
        case .dailyGoalReached: "daily_goal_reached"
        case .taskProgressed: "task_progressed"
        case .celestialOpened: "celestial_opened"
        case .universeShared: "universe_shared"
        case .skyThemeChanged: "sky_theme_changed"
        case .skyOptionChanged: "sky_option_changed"
        case .yearReviewOpened: "year_review_opened"
        case .yearReviewShared: "year_review_shared"
        case .stardustEarned: "stardust_earned"
        case .worldEmerged: "world_emerged"
        case .galaxyIgnited: "galaxy_ignited"
        case .coursePlotted: "course_plotted"
        case .expeditionRecalled: "expedition_recalled"
        case .expeditionArrived: "expedition_arrived"
        case .shipPartBought: "ship_part_bought"
        case .shipPartEquipped: "ship_part_equipped"
        case .horizonStarted: "horizon_started"
        case .horizonReached: "horizon_reached"
        case .rankUp: "rank_up"
        case .cosmicEventWitnessed: "cosmic_event_witnessed"
        case .taskCreated: "task_created"
        case .taskCompleted: "task_completed"
        case .taskArchived: "task_archived"
        case .planBlockSaved: "plan_block_saved"
        case .planShifted: "plan_shifted"
        case .planFocusStarted: "plan_focus_started"
        case .planOrbitOpened: "plan_orbit_opened"
        case .habitCreated: "habit_created"
        case .habitCheckedIn: "habit_checked_in"
        case .habitArchived: "habit_archived"
        case .habitsOpened: "habits_opened"
        case .togetherRoomCreated: "together_room_created"
        case .togetherJoined: "together_joined"
        case .togetherStarted: "together_started"
        case .togetherInviteShared: "together_invite_shared"
        case .togetherFailed: "together_failed"
        case .insightsPeriodChanged: "insights_period_changed"
        case .insightsHistoryBrowsed: "insights_history_browsed"
        case .csvExported: "csv_exported"
        case .settingChanged: "setting_changed"
        case .notificationPermission: "notification_permission"
        case .iCloudSyncChanged: "icloud_sync_changed"
        case .appleSignInCompleted: "apple_sign_in_completed"
        case .dataExported: "data_exported"
        case .dataErased: "data_erased"
        case .analyticsOptOut: "analytics_opt_out"
        case .lockedFeatureTapped: "locked_feature_tapped"
        case .paywallViewed: "paywall_viewed"
        case .paywallPlanSelected: "paywall_plan_selected"
        case .paywallDismissed: "paywall_dismissed"
        case .beginCheckout: "begin_checkout"
        case .purchase: "purchase"
        case .trialStarted: "plus_trial_started"
        case .purchaseCompleted: "plus_purchase_completed"
        case .purchaseCancelled: "plus_purchase_cancelled"
        case .purchasePending: "plus_purchase_pending"
        case .purchaseFailed: "plus_purchase_failed"
        case .restoreStarted: "plus_restore_started"
        case .restoreCompleted: "plus_restore_completed"
        case .restoreFailed: "plus_restore_failed"
        case .plusStatusChanged: "plus_status_changed"
        case .manageSubscriptionOpened: "manage_subscription_opened"
        case .offeringsFailed: "plus_offerings_failed"
        }
    }

    // MARK: Parameters

    var parameters: [String: TelemetryValue] {
        switch self {
        case .onboardingStarted, .moonCaptured, .yearReviewShared, .expeditionRecalled, .taskArchived,
             .togetherInviteShared, .appleSignInCompleted, .dataExported, .dataErased, .analyticsOptOut,
             .restoreStarted, .manageSubscriptionOpened:
            [:]
        case let .onboardingStep(step): ["step": .text(step)]
        case let .onboardingCompleted(name, apple): ["name_given": .bool(name), "apple_sign_in": .bool(apple)]
        case let .appOpened(days, day): ["days_since_install": .int(days), "universe_day": .int(day)]
        case let .screenView(screen): ["screen_name": .text(screen), "screen_class": .text(screen)]
        case let .deepLinkOpened(target, web): ["target": .text(target), "link_type": .text(web ? "universal" : "scheme")]
        case let .notificationOpened(kind): ["kind": .text(kind)]
        case let .focusSetupOpened(source): ["source": .text(source)]
        case let .focusStarted(minutes, category, ambience, intention, task, shield, together, source):
            ["minutes": .int(minutes), "category": .text(category), "ambience": .text(ambience),
             "has_intention": .bool(intention), "from_task": .bool(task), "shield": .bool(shield),
             "together": .bool(together), "source": .text(source)]
        case let .focusPaused(elapsed, count): ["elapsed_minutes": .int(elapsed), "pause_count": .int(count)]
        case let .focusResumed(count): ["pause_count": .int(count)]
        case let .focusCompleted(minutes, category, pauses):
            ["minutes": .int(minutes), "category": .text(category), "pauses": .int(pauses)]
        case let .focusEndedEarly(planned, focused, category, pauses, percent):
            ["planned_minutes": .int(planned), "focused_minutes": .int(focused), "category": .text(category),
             "pauses": .int(pauses), "percent_done": .int(percent)]
        case let .focusAutoEnded(planned, focused): ["planned_minutes": .int(planned), "focused_minutes": .int(focused)]
        case let .ambienceChanged(sound, during): ["sound": .text(sound), "during": .text(during)]
        case let .breakStarted(minutes, long): ["minutes": .int(minutes), "long_break": .bool(long)]
        case let .breakFinished(skipped): ["skipped": .bool(skipped)]
        case let .starEarned(category, minutes, number, today):
            ["category": .text(category), "minutes": .int(minutes), "star_number": .int(number), "today_stars": .int(today)]
        case let .sessionWithoutStar(focused): ["focused_minutes": .int(focused)]
        case let .constellationFormed(count): ["constellations": .int(count)]
        case let .planetBorn(ordinal): ["planet_number": .int(ordinal)]
        case let .achievementUnlocked(id, milestone): ["achievement_id": .text(id), "milestone": .bool(milestone)]
        case let .dailyGoalReached(goal, today): ["goal_minutes": .int(goal), "today_minutes": .int(today)]
        case let .taskProgressed(done, planned, completed):
            ["sessions_done": .int(done), "sessions_planned": .int(planned), "completed": .bool(completed)]
        case let .celestialOpened(kind): ["kind": .text(kind)]
        case let .universeShared(kind): ["kind": .text(kind)]
        case let .skyThemeChanged(theme): ["theme": .text(theme)]
        case let .skyOptionChanged(option, on): ["option": .text(option), "on": .bool(on)]
        case let .yearReviewOpened(sessions): ["sessions": .int(sessions)]
        case let .stardustEarned(amount): ["amount": .int(amount)]
        case let .worldEmerged(ordinal, rarity): ["world_number": .int(ordinal), "rarity": .text(rarity)]
        case let .galaxyIgnited(index): ["galaxy": .int(index)]
        case let .coursePlotted(ordinal, cost): ["world_number": .int(ordinal), "cost": .int(cost)]
        case let .expeditionArrived(ordinal): ["world_number": .int(ordinal)]
        case let .shipPartBought(part, price, plus): ["part": .text(part), "price": .int(price), "plus": .bool(plus)]
        case let .shipPartEquipped(part): ["part": .text(part)]
        case let .horizonStarted(kind, target): ["kind": .text(kind), "target": .int(target)]
        case let .horizonReached(kind, chain): ["kind": .text(kind), "chain": .int(chain)]
        case let .rankUp(level): ["level": .int(level)]
        case let .cosmicEventWitnessed(kind): ["kind": .text(kind)]
        case let .taskCreated(due, sessions): ["has_due_date": .bool(due), "sessions": .int(sessions)]
        case let .taskCompleted(viaFocus): ["via_focus": .bool(viaFocus)]
        case let .planBlockSaved(isNew, minutes, reminder, atStart, alarm):
            ["new": .bool(isNew), "minutes": .int(minutes), "reminder_minutes": .int(reminder),
             "at_start": .bool(atStart), "alarm": .bool(alarm)]
        case let .planShifted(minutes, blocks): ["minutes": .int(minutes), "blocks": .int(blocks)]
        case let .planFocusStarted(minutes, during, source):
            ["minutes": .int(minutes), "during_block": .bool(during), "source": .text(source)]
        case let .planOrbitOpened(blocks, lit): ["blocks": .int(blocks), "lit": .int(lit)]
        case let .habitCreated(cadence, focus, reminder, template):
            ["cadence": .text(cadence), "focus_minutes": .int(focus), "reminder": .bool(reminder), "template": .text(template)]
        case let .habitCheckedIn(source, streak, backfill):
            ["source": .text(source), "streak": .int(streak), "backfill": .bool(backfill)]
        case let .habitArchived(total): ["days_kept": .int(total)]
        case let .habitsOpened(habits, kept, source): ["habits": .int(habits), "kept_today": .int(kept), "source": .text(source)]
        case let .togetherRoomCreated(minutes): ["minutes": .int(minutes)]
        case let .togetherJoined(viaLink): ["via_link": .bool(viaLink)]
        case let .togetherStarted(role): ["role": .text(role)]
        case let .togetherFailed(reason): ["reason": .text(reason)]
        case let .insightsPeriodChanged(period): ["period": .text(period)]
        case let .insightsHistoryBrowsed(period, back): ["period": .text(period), "periods_back": .int(back)]
        case let .csvExported(sessions): ["sessions": .int(sessions)]
        case let .settingChanged(setting, value): ["setting": .text(setting), "value": .text(value)]
        case let .notificationPermission(granted, source): ["granted": .bool(granted), "source": .text(source)]
        case let .iCloudSyncChanged(on): ["on": .bool(on)]
        case let .lockedFeatureTapped(feature, screen): ["feature": .text(feature), "screen": .text(screen)]
        case let .paywallViewed(source, feature, plans, availability):
            ["source": .text(source), "feature": .text(feature ?? "none"), "plans": .int(plans),
             "availability": .text(availability)]
        case let .paywallPlanSelected(plan): ["plan": .text(plan)]
        case let .paywallDismissed(source, seconds, purchased):
            ["source": .text(source), "seconds": .int(seconds), "purchased": .bool(purchased)]
        case let .beginCheckout(info): Self.commerce(info)
        case let .purchase(info, transaction):
            Self.commerce(info).merging(transaction.map { ["transaction_id": .text($0)] } ?? [:]) { a, _ in a }
        // A trial earns nothing yet: value 0, with the price it will renew at.
        case let .trialStarted(info):
            Self.commerce(info).merging(["value": .double(0), "price": .double(info.price),
                                         "trial_days": .int(info.trialDays ?? 0)]) { _, new in new }
        case let .purchaseCompleted(info, trial): Self.commerce(info).merging(["trial": .bool(trial)]) { a, _ in a }
        case let .purchaseCancelled(plan), let .purchasePending(plan): ["plan": .text(plan)]
        case let .purchaseFailed(plan, error): ["plan": .text(plan), "error": .text(error)]
        case let .restoreCompleted(found): ["found": .bool(found)]
        case let .restoreFailed(error), let .offeringsFailed(error): ["error": .text(error)]
        case let .plusStatusChanged(from, to): ["from": .text(from), "to": .text(to)]
        }
    }

    /// GA4 e-commerce fields: `value` + `currency` make revenue, `item_*` fill item reports.
    private static func commerce(_ info: PurchaseInfo) -> [String: TelemetryValue] {
        ["value": .double(info.price), "currency": .text(info.currency), "plan": .text(info.plan),
         "item_id": .text(info.productID), "item_name": .text("Lumora+ \(info.plan)"), "source": .text(info.source)]
    }
}
