import AppIntents
import SwiftUI
import WidgetKit

/// Control Center, Lock Screen and Action Button: a Focus toggle. On starts
/// a session with your usual length and category; off ends it.
@available(iOS 18.0, *)
struct FocusControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: FocusControlState.controlKind, provider: Provider()) { isOn in
            ControlWidgetToggle("Focus", isOn: isOn, action: SetFocusRunningIntent()) { isOn in
                Label(isOn ? "Focusing" : "Start focus", systemImage: isOn ? "sparkles" : "sparkle")
            }
            .tint(Color(hex: Palette.cosmicViolet))
        }
        .displayName("Orbi Focus")
        .description("Start a focus session, or end the one that's running.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }

        func currentValue() async throws -> Bool { FocusControlState.isRunning() }
    }
}
