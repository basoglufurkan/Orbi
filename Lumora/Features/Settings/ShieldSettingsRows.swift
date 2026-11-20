import FamilyControls
import SwiftUI

/// Settings rows for the distraction shield: the switch, Apple's app picker,
/// and a plain account of what Lumora can and can't see.
struct ShieldSettingsRows: View {
    @Bindable var shield: ScreenTimeShield
    @Bindable var prefs: UserPreferences

    @Environment(AppModel.self) private var app
    @State private var picking = false
    @State private var denied = false

    var body: some View {
        Toggle(isOn: Binding(get: { prefs.distractionShieldEnabled }, set: { setEnabled($0) })) {
            Text("Shield chosen apps during focus").font(LMFont.body).foregroundStyle(LMColor.textPrimary)
        }
        .padding(.horizontal, LMSpace.m).frame(minHeight: 56)
        .accessibilityIdentifier("settings.shield")

        if prefs.distractionShieldEnabled, shield.isAuthorized {
            SettingsDivider()
            Button { picking = true } label: {
                HStack {
                    Text("Apps to shield").font(LMFont.body).foregroundStyle(LMColor.textPrimary)
                    Spacer()
                    Text(shield.pickedCount == 0 ? String(localized: "None yet") : String(localized: "\(shield.pickedCount) picked"))
                        .font(LMFont.body).foregroundStyle(LMColor.textSecondary)
                    Image(systemName: "chevron.right").font(LMFont.footnote).foregroundStyle(LMColor.textTertiary)
                }
                .padding(.horizontal, LMSpace.m).frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        SettingsDivider()
        Text(denied
             ? String(localized: "Screen Time access wasn't allowed. You can allow it for Orbi in Settings › Screen Time.")
             : String(localized: "The apps you pick go quiet only while you focus, and come back the moment the session ends or pauses. Apple keeps the list; Orbi never sees which apps they are."))
            .font(LMFont.footnote)
            .foregroundStyle(denied ? LMColor.reward : LMColor.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LMSpace.m)
            .familyActivityPicker(isPresented: $picking, selection: $shield.selection)
            .onChange(of: shield.selection) { app.applyShieldNow() }
            .onAppear { shield.refreshAuthorization() }
    }

    private func setEnabled(_ on: Bool) {
        denied = false
        Task {
            switch await app.setShieldEnabled(on) {
            case .denied: denied = true
            case .needsPicks: picking = true
            case .on, .off: break
            }
        }
    }
}
