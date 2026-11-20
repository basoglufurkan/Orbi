import Foundation

/// The App Group shared by the app and the widget extension.
///
/// Only the minimum data widgets need crosses this boundary: a small,
/// precomputed `WidgetSnapshot`. The SwiftData store stays private to the app.
enum AppGroup {
    static let identifier = "group.com.mobapptech.lumora"

    /// Shared defaults. Falls back to `.standard` when the App Group entitlement
    /// is unavailable (e.g. unsigned builds) so the app never crashes.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
