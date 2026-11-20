import Foundation
import Testing
@testable import Lumora

/// Google Analytics drops events that break its naming rules, silently.
@MainActor
struct TelemetryTests {
    static let info = TelemetryEvent.PurchaseInfo(plan: "yearly", productID: PlusStore.Product.yearly, price: 599.99,
                                                  currency: "TRY", trialDays: 7, source: "settings")

    /// One of every event.
    static let all: [TelemetryEvent] = [
        .onboardingStarted, .onboardingStep(step: "account"), .onboardingCompleted(nameGiven: true, appleSignIn: false),
        .appOpened(daysSinceInstall: 3, universeDay: 4), .screenView(screen: "today"),
        .deepLinkOpened(target: "insights/year", web: true), .notificationOpened(kind: "daily_invitation"),
        .focusSetupOpened(source: "home"),
        .focusStarted(minutes: 25, category: "work", ambience: "rain", hasIntention: true, fromTask: false,
                      shield: true, together: false, source: "app"),
        .focusPaused(elapsedMinutes: 10, pauseCount: 1), .focusResumed(pauseCount: 1),
        .focusCompleted(minutes: 25, category: "work", pauses: 0),
        .focusEndedEarly(plannedMinutes: 25, focusedMinutes: 12, category: "study", pauses: 2, percent: 48),
        .focusAutoEnded(plannedMinutes: 45, focusedMinutes: 30), .ambienceChanged(sound: "rain", during: "focus"),
        .breakStarted(minutes: 5, long: false), .breakFinished(skipped: true),
        .starEarned(category: "work", minutes: 25, starNumber: 12, todayStars: 3), .sessionWithoutStar(focusedMinutes: 2),
        .constellationFormed(count: 4), .planetBorn(ordinal: 2), .moonCaptured,
        .achievementUnlocked(id: "first-light", milestone: true), .dailyGoalReached(goalMinutes: 120, todayMinutes: 125),
        .taskProgressed(done: 2, planned: 3, completed: false),
        .celestialOpened(kind: "star"), .universeShared(kind: "universe"), .skyThemeChanged(theme: "ember"),
        .skyOptionChanged(option: "sky.today", on: false), .yearReviewOpened(sessions: 80), .yearReviewShared,
        .stardustEarned(amount: 40), .worldEmerged(ordinal: 3, rarity: "rare"), .galaxyIgnited(index: 1),
        .coursePlotted(ordinal: 3, cost: 120), .expeditionRecalled, .expeditionArrived(ordinal: 3),
        .shipPartBought(part: "paint.eclipse", price: 260, plus: true), .shipPartEquipped(part: "hull.swift"),
        .horizonStarted(kind: "weeklyMinutes", target: 300), .horizonReached(kind: "weeklyMinutes", chain: 2),
        .rankUp(level: 3), .cosmicEventWitnessed(kind: "meteorShower"),
        .taskCreated(hasDueDate: true, sessions: 3), .taskCompleted(viaFocus: true), .taskArchived,
        .planBlockSaved(isNew: true, minutes: 90, reminderMinutes: 10, atStart: true, alarm: false),
        .planShifted(minutes: 15, blocks: 3), .planFocusStarted(minutes: 25, during: true, source: "orbit"),
        .planOrbitOpened(blocks: 5, lit: 2),
        .habitCreated(cadence: "weekly", focusMinutes: 20, reminder: true, template: "read"),
        .habitCheckedIn(source: "focus", streak: 12, backfill: false), .habitArchived(total: 30),
        .habitsOpened(habits: 4, keptToday: 2, source: "home"),
        .togetherRoomCreated(minutes: 25), .togetherJoined(viaLink: true), .togetherStarted(role: "host"),
        .togetherInviteShared, .togetherFailed(reason: "noRoom"),
        .insightsPeriodChanged(period: "month"), .insightsHistoryBrowsed(period: "week", back: 2), .csvExported(sessions: 40),
        .settingChanged(setting: "daily_goal", value: "90"), .notificationPermission(granted: true, source: "settings"),
        .iCloudSyncChanged(on: true), .appleSignInCompleted, .dataExported, .dataErased, .analyticsOptOut,
        .lockedFeatureTapped(feature: "ambience", screen: "focus_setup"),
        .paywallViewed(source: "locked_feature", feature: "ambience", plans: 3, availability: "ready"),
        .paywallPlanSelected(plan: "monthly"), .paywallDismissed(source: "settings", seconds: 14, purchased: false),
        .beginCheckout(info), .purchase(info, transactionID: "2000000123"), .trialStarted(info),
        .purchaseCompleted(info, trial: true), .purchaseCancelled(plan: "yearly"), .purchasePending(plan: "monthly"),
        .purchaseFailed(plan: "lifetime", error: "rc_2"), .restoreStarted, .restoreCompleted(found: true),
        .restoreFailed(error: "rc_10"), .plusStatusChanged(from: "free", to: "plus"), .manageSubscriptionOpened,
        .offeringsFailed(error: "rc_23"),
    ]

    private static func valid(_ name: String) -> Bool {
        name.count <= 40 && name.range(of: "^[a-z][a-z0-9_]*$", options: .regularExpression) != nil
            && !["firebase_", "google_", "ga_"].contains(where: name.hasPrefix)
    }

    @Test func everyEventFollowsGoogleAnalyticsRules() {
        for event in Self.all {
            #expect(Self.valid(event.name), "bad name \(event.name)")
            #expect(event.parameters.count <= 25, "\(event.name) has too many parameters")
            for (key, value) in event.parameters {
                #expect(Self.valid(key), "\(event.name): bad parameter \(key)")
                if case let .text(text) = value { #expect(text.count <= 100, "\(event.name).\(key) too long") }
            }
        }
        // Each name means one thing.
        #expect(Set(Self.all.map(\.name)).count == Self.all.count)
    }

    @Test func purchasesUseGoogleAnalyticsCommerce() {
        let bought = TelemetryEvent.purchase(Self.info, transactionID: "2000000123").parameters
        #expect(bought["value"] == .double(599.99))
        #expect(bought["currency"] == .text("TRY"))
        #expect(bought["transaction_id"] == .text("2000000123"))
        #expect(bought["item_id"] == .text(PlusStore.Product.yearly))
        // A trial start isn't revenue yet.
        let trial = TelemetryEvent.trialStarted(Self.info).parameters
        #expect(trial["value"] == .double(0))
        #expect(trial["price"] == .double(599.99))
        #expect(trial["trial_days"] == .int(7))
    }

    @Test func userPropertiesFitTheirLimits() {
        for property in TelemetryProperty.allCases {
            #expect(property.rawValue.count <= 24 && Self.valid(property.rawValue), "bad property \(property.rawValue)")
        }
        #expect(TelemetryBucket.goal(120) == "61-120")
        #expect(TelemetryBucket.sessions(0) == "0")
        #expect(TelemetryBucket.sessions(57) == "50-199")
    }

    @Test func linksAreNamedWithoutTheirCode() {
        #expect(DeepLink.join(code: "2QGSZ9").analyticsName == "join")
        #expect(DeepLink.yearInReview.analyticsName == "insights/year")
    }
}
