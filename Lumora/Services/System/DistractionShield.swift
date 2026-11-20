import Foundation

/// Feature flags for capabilities that need extra entitlements or review.
enum FeatureFlags {
    /// Screen Time based distraction shielding (Family Controls, Managed
    /// Settings, Device Activity). Needs the
    /// `com.apple.developer.family-controls` entitlement on the app and its
    /// shield extensions; development builds get it from Xcode, App Store
    /// builds only once Apple approves the distribution request.
    static let distractionShield = true
}

/// Optional distraction management during focus. Implementations must
/// obtain explicit user consent (`AuthorizationCenter.requestAuthorization`)
/// and only shield apps the user picked with `FamilyActivityPicker`; Lumora
/// never inspects or blocks other apps without that consent.
@MainActor
protocol DistractionShielding: AnyObject {
    var isAvailable: Bool { get }
    var isAuthorized: Bool { get }
    func requestAuthorization() async throws
    /// Shields the user's picks until `end`, when they lift on their own.
    func beginShielding(until end: Date)
    func endShielding()
}

/// Default implementation used while the entitlement is not granted.
@MainActor
final class UnavailableDistractionShield: DistractionShielding {
    var isAvailable: Bool { false }
    var isAuthorized: Bool { false }
    func requestAuthorization() async throws {}
    func beginShielding(until end: Date) {}
    func endShielding() {}
}
