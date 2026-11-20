import Foundation

/// What kind of build is running.
enum BuildInfo {
    /// Debug builds, and any build a developer installed straight onto a
    /// device (it carries a development or ad-hoc provisioning profile).
    /// Never true for App Store or TestFlight builds, which carry none.
    static let isDeveloperInstall: Bool = {
        #if DEBUG
        return true
        #else
        return Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil
        #endif
    }()
}
