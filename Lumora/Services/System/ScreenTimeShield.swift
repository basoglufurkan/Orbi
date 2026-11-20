import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import os

/// The distraction shield, on Apple's Screen Time APIs. The user grants
/// Screen Time access and picks apps, categories and sites with Apple's
/// picker; Lumora only ever holds the opaque tokens that picker hands back,
/// never the names of the apps.
///
/// During focus those picks are shielded. The shield is lifted by the app
/// when the session ends, pauses or is abandoned, and, should the app be
/// suspended or gone by then, by the LumoraShieldMonitor extension when the
/// Device Activity interval for the session runs out.
@MainActor
@Observable
final class ScreenTimeShield: DistractionShielding {
    /// Shared with the extensions; keep in step with LumoraShieldMonitor
    /// and LumoraShieldConfiguration.
    static let storeName = ManagedSettingsStore.Name("lumora.focus")
    static let activityName = DeviceActivityName("lumora.focus")
    nonisolated static let endsAtKey = "lumora.shield.endsAt"
    private static let selectionKey = "lumora.shield.selection"
    /// Device Activity won't monitor an interval shorter than this.
    private static let minimumInterval: TimeInterval = 15 * 60

    @ObservationIgnored private let logger = Logger(subsystem: "com.mobapptech.lumora", category: "Shield")
    @ObservationIgnored private let store = ManagedSettingsStore(named: ScreenTimeShield.storeName)
    private(set) var authorizationStatus = AuthorizationCenter.shared.authorizationStatus

    var selection: FamilyActivitySelection {
        didSet { Self.save(selection) }
    }

    init() {
        selection = Self.loadSelection()
    }

    var isAvailable: Bool { true }
    var isAuthorized: Bool { authorizationStatus == .approved }

    /// How many apps, categories and sites are picked.
    var pickedCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    func requestAuthorization() async throws {
        defer { authorizationStatus = AuthorizationCenter.shared.authorizationStatus }
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }

    func refreshAuthorization() {
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
    }

    func beginShielding(until end: Date) {
        refreshAuthorization()
        // Nothing (left) to shield, or access was revoked: lift what's there.
        guard isAuthorized, pickedCount > 0 else { endShielding(); return }
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        AppGroup.defaults.set(end.timeIntervalSince1970, forKey: Self.endsAtKey)

        // The safety net: the monitor clears the shield when this interval
        // ends, even if Lumora is suspended. Short sessions start the window
        // in the past so it ends exactly at the session's end.
        let start = min(Date.now, end.addingTimeInterval(-Self.minimumInterval))
        let calendar = Calendar.current
        // With the zone, the window is pinned to absolute moments: a flight or
        // a DST change can't move the end and keep apps shielded.
        let parts: Set<Calendar.Component> = [.timeZone, .year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(intervalStart: calendar.dateComponents(parts, from: start),
                                              intervalEnd: calendar.dateComponents(parts, from: end),
                                              repeats: false)
        let center = DeviceActivityCenter()
        center.stopMonitoring([Self.activityName])
        do {
            try center.startMonitoring(Self.activityName, during: schedule)
        } catch {
            // Without the safety net the app still lifts the shield itself
            // the next time it runs; never leave the user locked out longer.
            logger.error("Shield monitoring failed: \(error.localizedDescription)")
        }
    }

    func endShielding() {
        store.clearAllSettings()
        AppGroup.defaults.removeObject(forKey: Self.endsAtKey)
        DeviceActivityCenter().stopMonitoring([Self.activityName])
    }

    private static func loadSelection() -> FamilyActivitySelection {
        guard let data = UserDefaults.standard.data(forKey: selectionKey),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return FamilyActivitySelection() }
        return selection
    }

    private static func save(_ selection: FamilyActivitySelection) {
        UserDefaults.standard.set(try? JSONEncoder().encode(selection), forKey: selectionKey)
    }
}
