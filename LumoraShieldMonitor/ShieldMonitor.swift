import DeviceActivity
import Foundation
import ManagedSettings

/// The shield's safety net. Lumora lifts the shield itself when a session
/// ends, but it may be suspended or gone by then; the session's Device
/// Activity interval ends at the same moment, and this lifts it instead.
/// Names are shared with ScreenTimeShield in the app; keep them in step.
final class ShieldMonitor: DeviceActivityMonitor {
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == DeviceActivityName("lumora.focus") else { return }
        ManagedSettingsStore(named: ManagedSettingsStore.Name("lumora.focus")).clearAllSettings()
        UserDefaults(suiteName: "group.com.mobapptech.lumora")?.removeObject(forKey: "lumora.shield.endsAt")
    }
}
