import FirebaseAnalytics
import FirebaseCore
import Foundation
import os

/// Product analytics through Firebase (Google Analytics for Firebase).
///
/// What is sent: what people do in Lumora (events) and a few coarse traits
/// (user properties). What is never sent: intentions, task titles, names,
/// room codes, or anything typed. Lumora links the no-ad-ID build of the SDK
/// (`FirebaseAnalyticsCore`), so there's no IDFA and no cross-app tracking.
///
/// Nothing happens until `GoogleService-Info.plist` is in the app bundle;
/// unit tests, UI tests and in-memory runs never send. People can turn it off
/// in Settings › Data › Share usage data.
@MainActor
enum Telemetry {
    static let optOutKey = "lumora.analytics.optedOut"

    /// Whether events reach Firebase right now.
    private(set) static var isActive = false
    /// DEBUG and tests: every event logged, newest last (also when not sending).
    private(set) static var recent: [(name: String, parameters: [String: Any])] = []
    private static let logger = Logger(subsystem: "com.mobapptech.lumora", category: "Telemetry")

    /// Call once at launch.
    static func start(enabled: Bool) {
        guard enabled, !isActive, FirebaseApp.app() == nil else { return }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            logger.notice("GoogleService-Info.plist isn't in the bundle; analytics stays off.")
            return
        }
        FirebaseApp.configure()
        isActive = true
        Analytics.setAnalyticsCollectionEnabled(!isOptedOut)
    }

    static var isOptedOut: Bool { UserDefaults.standard.bool(forKey: optOutKey) }

    static func setOptedOut(_ optedOut: Bool) {
        // Logged before switching off, so the choice itself is counted once.
        if optedOut { log(.analyticsOptOut) }
        UserDefaults.standard.set(optedOut, forKey: optOutKey)
        if isActive { Analytics.setAnalyticsCollectionEnabled(!optedOut) }
    }

    static func log(_ event: TelemetryEvent) {
        let parameters = event.parameters.compactMapValues(\.firebaseValue)
        #if DEBUG
        recent.append((event.name, parameters))
        if recent.count > 200 { recent.removeFirst(recent.count - 200) }
        logger.debug("event \(event.name, privacy: .public) \(String(describing: parameters), privacy: .public)")
        #endif
        guard isActive, !isOptedOut else { return }
        Analytics.logEvent(event.name, parameters: parameters.isEmpty ? nil : parameters)
    }

    static func set(_ property: TelemetryProperty, _ value: String?) {
        guard isActive else { return }
        Analytics.setUserProperty(value.map { String($0.prefix(36)) }, forName: property.rawValue)
    }

    /// Firebase's ID for this install, for RevenueCat's Firebase integration.
    static var appInstanceID: String? { isActive ? Analytics.appInstanceID() : nil }
}

/// User properties: coarse traits for segmenting reports. Values ≤ 36 characters.
enum TelemetryProperty: String, CaseIterable {
    /// free, plus_monthly, plus_yearly, plus_lifetime
    case plusStatus = "plus_status"
    /// night, dawn, auto
    case appearance
    /// The default ambient sound.
    case ambience
    /// 0-30, 31-60, 61-120, 121-240, 240+
    case dailyGoal = "daily_goal"
    /// 0, 1-9, 10-49, 50-199, 200+ qualifying sessions
    case universeSize = "universe_size"
    /// Navigator rank level in the Odyssey.
    case odysseyRank = "odyssey_rank"
    /// on, off
    case iCloudSync = "icloud_sync"
    /// on, off
    case shield = "focus_shield"
    case skyTheme = "sky_theme"
    /// yes, no
    case appleSignIn = "apple_sign_in"
}

/// A value Firebase accepts: text (≤ 100 characters), whole numbers, or decimals.
enum TelemetryValue: Equatable {
    case text(String), int(Int), double(Double), bool(Bool)

    var firebaseValue: Any? {
        switch self {
        case let .text(s): String(s.prefix(100))
        case let .int(i): i
        case let .double(d): d
        // Firebase has no booleans; 1 and 0 keep them summable in reports.
        case let .bool(b): b ? 1 : 0
        }
    }
}

extension TelemetryValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral {
    init(stringLiteral value: String) { self = .text(value) }
    init(integerLiteral value: Int) { self = .int(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
}

/// Buckets keep numbers coarse in user properties.
enum TelemetryBucket {
    static func goal(_ minutes: Int) -> String {
        switch minutes {
        case ...30: "0-30"
        case ...60: "31-60"
        case ...120: "61-120"
        case ...240: "121-240"
        default: "240+"
        }
    }

    static func sessions(_ count: Int) -> String {
        switch count {
        case 0: "0"
        case ...9: "1-9"
        case ...49: "10-49"
        case ...199: "50-199"
        default: "200+"
        }
    }
}

import SwiftUI

extension View {
    /// Logs a `screen_view` each time this screen appears.
    func telemetryScreen(_ name: String) -> some View {
        onAppear { Telemetry.log(.screenView(screen: name)) }
    }
}
