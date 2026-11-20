import FamilyControls
import SwiftUI

/// "Quiet apps" on the focus setup screen: switch the distraction shield on
/// or off for this and later sessions, and add or remove apps right before
/// starting, with Apple's own picker.
struct SetupShieldSection: View {
    @Bindable var shield: ScreenTimeShield

    @Environment(AppModel.self) private var app
    @State private var picking = false
    @State private var denied = false

    var body: some View {
        let on = app.preferences.distractionShieldEnabled && shield.isAuthorized
        VStack(alignment: .leading, spacing: LMSpace.s) {
            EyebrowText(String(localized: "Quiet apps"))
            VStack(spacing: 0) {
                Toggle(isOn: Binding(get: { on }, set: { setEnabled($0) })) {
                    HStack(spacing: LMSpace.s) {
                        Image(systemName: on ? "moon.zzz.fill" : "moon.zzz")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(on ? LMColor.reward : LMColor.textTertiary)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Quiet my apps while I focus")
                                .font(LMFont.headline.weight(.medium))
                                .foregroundStyle(LMColor.textPrimary)
                            Text(status(on: on))
                                .font(LMFont.footnote)
                                .foregroundStyle(denied ? LMColor.warm : LMColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .tint(LMColor.reward)
                .padding(.horizontal, LMSpace.m)
                .frame(minHeight: 64)
                .accessibilityIdentifier("setup.shield")

                if on {
                    Rectangle().fill(LMColor.hairline).frame(height: 1).padding(.leading, LMSpace.m)
                    Button {
                        app.haptics.selection()
                        picking = true
                    } label: {
                        HStack {
                            Text(shield.pickedCount == 0 ? String(localized: "Choose apps") : String(localized: "Add or remove apps"))
                                .font(LMFont.body)
                                .foregroundStyle(LMColor.textPrimary)
                            Spacer()
                            Text(shield.pickedCount == 0 ? String(localized: "None yet") : String(localized: "\(shield.pickedCount) picked"))
                                .font(LMFont.callout)
                                .foregroundStyle(LMColor.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(LMColor.textTertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, LMSpace.m)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("setup.shieldApps")
                }
            }
            .glassCard(radius: 20)
        }
        .familyActivityPicker(isPresented: $picking, selection: $shield.selection)
        .onAppear { shield.refreshAuthorization() }
    }

    private func status(on: Bool) -> String {
        if denied { return String(localized: "Screen Time access is off for Orbi. You can allow it in Settings › Screen Time.") }
        guard on else { return String(localized: "Off. Nothing is blocked.") }
        switch shield.pickedCount {
        case 0: return String(localized: "Pick the apps that pull you away.")
        case 1: return String(localized: "1 pick stays quiet until your star is born.")
        default: return String(localized: "\(shield.pickedCount) picks stay quiet until your star is born.")
        }
    }

    private func setEnabled(_ on: Bool) {
        denied = false
        app.haptics.selection()
        Task {
            switch await app.setShieldEnabled(on) {
            case .denied: denied = true
            case .needsPicks: picking = true
            case .on, .off: break
            }
        }
    }
}
