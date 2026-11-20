import Foundation

/// Whether Orbi+ is active, mirrored into the app group so every part of
/// the app (and anything drawn outside the main view tree) reads the same
/// answer without waiting for the store. `PlusStore` is the only writer.
enum PlusAccess {
    /// The RevenueCat entitlement that unlocks Orbi+.
    static let entitlement = "plus"
    static let key = "lumora.plus.active"
    nonisolated(unsafe) static let defaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard

    static var isActive: Bool { defaults.bool(forKey: key) }
}
