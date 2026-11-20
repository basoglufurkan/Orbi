import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Lumora's shield: Pell asleep on deep space, saying when the app comes
/// back. The end time comes from ScreenTimeShield through the App Group;
/// keep the key in step.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        shield(name: application.localizedDisplayName)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        shield(name: application.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        shield(name: webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        shield(name: webDomain.domain)
    }

    private func shield(name: String?) -> ShieldConfiguration {
        let gold = UIColor(red: 1, green: 0xD5 / 255, blue: 0x8A / 255, alpha: 1)
        let space = UIColor(red: 0x09 / 255, green: 0x0B / 255, blue: 0x1F / 255, alpha: 1)
        let lavender = UIColor(red: 0xC9 / 255, green: 0xC6 / 255, blue: 0xF2 / 255, alpha: 1)
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: space.withAlphaComponent(0.92),
            icon: UIImage(named: "ShieldPell"),
            title: ShieldConfiguration.Label(text: String(localized: "You're focusing"), color: .white),
            subtitle: ShieldConfiguration.Label(text: subtitle(name: name), color: lavender),
            primaryButtonLabel: ShieldConfiguration.Label(text: String(localized: "Back to focus"), color: space),
            primaryButtonBackgroundColor: gold)
    }

    private func subtitle(name: String?) -> String {
        let endsAt = UserDefaults(suiteName: "group.com.mobapptech.lumora")?.double(forKey: "lumora.shield.endsAt") ?? 0
        let name = name ?? String(localized: "This app")
        guard endsAt > Date.now.timeIntervalSince1970 else {
            return String(localized: "Pell is keeping \(name) quiet until your session ends. Your star is still forming.")
        }
        let time = Date(timeIntervalSince1970: endsAt).formatted(date: .omitted, time: .shortened)
        return String(localized: "Pell is keeping \(name) quiet until \(time). Your star is still forming.")
    }
}
