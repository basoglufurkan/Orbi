import SwiftData
import AuthenticationServices
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

/// Settings & personalization. Every change is saved immediately to the
/// SwiftData preferences row.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    /// Remembered intentions; planned tasks are managed on the Tasks screen.
    @Query(filter: #Predicate<FocusTask> { !$0.isArchived && !$0.isPlanned }, sort: \FocusTask.lastUsedAt, order: .reverse)
    private var tasks: [FocusTask]
    @Query private var progressRows: [UniverseProgress]

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var confirmErase = false
    @State private var confirmSignOut = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var exportDocument: JSONExportDocument?
    @State private var showExporter = false
    @State private var exportError: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showPlus = false
    /// Preferences as they were when Settings opened; what changed is logged on close.
    @State private var initialSettings: [String: String] = [:]
    @State private var sharesUsageData = !Telemetry.isOptedOut
    @State private var paywall: PlusFeature?

    var body: some View {
        @Bindable var prefs = app.preferences
        NavigationStack {
            ZStack {
                LMColor.bgBase.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: LMSpace.l) {
                        profileCard(prefs: prefs)
                        plusCard
                        accountSection
                        focusSection(prefs: prefs)
                        goalSection(prefs: prefs)
                        appearanceSection(prefs: prefs)
                        soundSection(prefs: prefs)
                        notificationSection(prefs: prefs)
                        intentionsSection
                        shieldSection(prefs: prefs)
                        cloudSection
                        dataSection
                        #if DEBUG
                        DebugSettingsSection()
                        #endif
                        Group {
                            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                            if app.cloud.isActive {
                                Text("Orbi \(version) · Your universe lives in your private iCloud.")
                            } else {
                                Text("Orbi \(version) · Your universe lives on this device.")
                            }
                        }
                        .font(LMFont.footnote)
                        .foregroundStyle(LMColor.textTertiary)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(LMSpace.l)
                }
            }
            .navigationTitle(String(localized: "Settings"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) {
                        app.savePreferences()
                        dismiss()
                    }
                    .accessibilityIdentifier("settings.done")
                }
            }
        }
        .tint(LMColor.focus)
        .sheet(isPresented: $showPlus) {
            PlusPaywallView().presentationCornerRadius(32)
        }
        .plusPaywall($paywall, screen: "settings")
        .task { notificationStatus = await app.notifications.authorizationStatus() }
        .onDisappear { app.savePreferences() }
        .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .json,
                      defaultFilename: "Orbi-\(DayKey(app.clock.now).rawValue)") { result in
            if case let .failure(error) = result { exportError = error.localizedDescription }
        }
        .alert(String(localized: "Erase everything?"), isPresented: $confirmErase) {
            Button(String(localized: "Erase all data"), role: .destructive) {
                dismiss()
                app.eraseAllData()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            if app.cloud.isActive {
                Text("Every star, planet, artifact and session will be permanently deleted from this device and from your iCloud, so from your other devices too. This can't be undone.")
            } else {
                Text("Every star, planet, artifact and session will be permanently deleted from this device. This can't be undone.")
            }
        }
        .alert(String(localized: "Export failed"), isPresented: .constant(exportError != nil)) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .telemetryScreen("settings")
        .onAppear { initialSettings = settingsSnapshot }
        .onDisappear {
            for (key, value) in settingsSnapshot.sorted(by: { $0.key < $1.key }) where initialSettings[key] != value {
                Telemetry.log(.settingChanged(setting: key, value: value))
            }
            if initialSettings["icloud_sync"] != settingsSnapshot["icloud_sync"] {
                Telemetry.log(.iCloudSyncChanged(on: app.cloud.wantsSync))
            }
            app.updateTelemetryProperties()
        }
    }

    // MARK: Sections

    private func profileCard(prefs: UserPreferences) -> some View {
        let p = progressRows.first
        return HStack(spacing: LMSpace.m) {
            Canvas { ctx, size in
                CelestialPainter.planet(&ctx, at: CGPoint(x: size.width / 2, y: size.height / 2), radius: 30,
                                        palette: .named("rose"), showRing: false)
            }
            .padding(-40)
            .frame(width: 72, height: 72)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                TextField(String(localized: "Your name"), text: Binding(get: { prefs.displayName }, set: { prefs.displayName = $0 }))
                    .font(LMFont.title)
                    .foregroundStyle(LMColor.textPrimary)
                    .submitLabel(.done)
                let stars = p?.starCount ?? 0, planets = p?.planetCount ?? 0
                Text(verbatim: [String(localized: "Day \(app.universeDay)"),
                                stars == 1 ? String(localized: "1 star") : String(localized: "\(stars) stars"),
                                planets == 1 ? String(localized: "1 planet") : String(localized: "\(planets) planets")]
                    .joined(separator: " · "))
                    .font(LMFont.callout.weight(.regular))
                    .foregroundStyle(LMColor.textSecondary)
            }
        }
        .padding(LMSpace.m)
        .glassCard(border: LMColor.focus.opacity(0.3))
    }

    /// The settings worth knowing about, as text, for change logging.
    private var settingsSnapshot: [String: String] {
        let p = app.preferences
        return [
            "default_minutes": String(p.defaultFocusMinutes),
            "short_break": String(p.shortBreakMinutes),
            "long_break": String(p.longBreakMinutes),
            "long_break_every": String(p.longBreakInterval),
            "auto_start_breaks": String(p.autoStartBreaks),
            "daily_goal": String(p.dailyGoalMinutes),
            "appearance": p.appearance.rawValue,
            "motion": p.motionRaw,
            "sounds": String(p.soundEnabled),
            "haptics": String(p.hapticsEnabled),
            "ambience": p.ambient.rawValue,
            "final_minute_tick": String(p.finalMinuteTick),
            "focus_notifications": String(p.focusNotifications),
            "break_notifications": String(p.breakNotifications),
            "daily_invitation": String(p.dailyReminderEnabled),
            "daily_invitation_hour": String(p.dailyReminderHour),
            "rare_event_notifications": String(p.rareEventNotifications),
            "focus_shield": String(p.distractionShieldEnabled),
            "icloud_sync": String(app.cloud.wantsSync),
        ]
    }

    // MARK: Orbi+

    private var plusCard: some View {
        Button {
            app.haptics.selection()
            showPlus = true
        } label: {
            HStack(spacing: LMSpace.m) {
                PlusGlyph().frame(width: 52, height: 52)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Orbi+").font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
                    Text(app.plus.isActive ? String(localized: "On. Thank you for supporting Orbi.")
                                           : String(localized: "Sky themes, every soundscape, rare ship finishes and your whole history."))
                        .font(LMFont.footnote)
                        .foregroundStyle(LMColor.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(LMColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(LMSpace.m)
            .glassCard(border: LMColor.rewardFill.opacity(0.35))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityIdentifier("settings.plus")
    }

    private var accountSection: some View {
        SettingsSection(title: String(localized: "Account")) {
            if app.account.isSignedIn {
                HStack(spacing: LMSpace.s) {
                    Image(systemName: "apple.logo").font(.title3).foregroundStyle(LMColor.textPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in with Apple").settingsLabel()
                        Text("Your name stays with your Apple ID. Orbi keeps no account on a server.")
                            .font(LMFont.footnote).foregroundStyle(LMColor.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, LMSpace.s)
                .settingsRow()
                SettingsDivider()
                Button(String(localized: "Sign out")) { confirmSignOut = true }
                    .font(LMFont.body)
                    .foregroundStyle(LMColor.textSecondary)
                    .settingsRow()
                    .accessibilityIdentifier("settings.signOut")
            } else {
                VStack(alignment: .leading, spacing: LMSpace.s) {
                    Text("You're using Orbi without an account. Sign in with Apple to keep your name with your Apple ID; your universe syncs through iCloud either way.")
                        .font(LMFont.footnote).foregroundStyle(LMColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    SignInWithAppleButton(.signIn) { request in
                        AppleAccount.configure(request)
                    } onCompletion: { result in
                        if case let .success(given) = app.account.complete(result) {
                            app.signedInWithApple(givenName: given)
                        }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 48)
                    .clipShape(Capsule())
                    .accessibilityIdentifier("settings.apple")
                }
                .padding(LMSpace.m)
            }
        }
        .alert(String(localized: "Sign out of Apple?"), isPresented: $confirmSignOut) {
            Button(String(localized: "Sign out"), role: .destructive) { app.account.signOut() }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("Your universe stays exactly as it is, on this device and in iCloud.")
        }
    }

    private func focusSection(prefs: UserPreferences) -> some View {
        SettingsSection(title: String(localized: "Focus & breaks")) {
            MinutesPickerRow(title: String(localized: "Default focus"), value: Binding(get: { prefs.defaultFocusMinutes }, set: { prefs.defaultFocusMinutes = $0 }),
                             options: [15, 20, 25, 30, 45, 50, 60, 90])
            SettingsDivider()
            MinutesPickerRow(title: String(localized: "Short break"), value: Binding(get: { prefs.shortBreakMinutes }, set: { prefs.shortBreakMinutes = $0 }),
                             options: [3, 5, 10])
            SettingsDivider()
            MinutesPickerRow(title: String(localized: "Long break"), value: Binding(get: { prefs.longBreakMinutes }, set: { prefs.longBreakMinutes = $0 }),
                             options: [10, 15, 20, 30])
            SettingsDivider()
            SettingsPickerRow(title: String(localized: "Long break after")) {
                Picker(String(localized: "Long break after"), selection: Binding(get: { prefs.longBreakInterval }, set: { prefs.longBreakInterval = $0 })) {
                    ForEach(2...6, id: \.self) { Text("\($0) sessions").tag($0) }
                }
            }
            SettingsDivider()
            Toggle(isOn: Binding(get: { prefs.autoStartBreaks }, set: { prefs.autoStartBreaks = $0 })) {
                Text("Start breaks automatically").settingsLabel()
            }
            .settingsRow()
        }
    }

    private func goalSection(prefs: UserPreferences) -> some View {
        SettingsSection(title: String(localized: "Daily goal")) {
            VStack(spacing: LMSpace.s) {
                if typeSize.isAccessibilitySize {
                    goalValue(prefs: prefs)
                    HStack {
                        stepButton("minus", label: "Decrease goal") { prefs.dailyGoalMinutes = max(15, prefs.dailyGoalMinutes - 15) }
                        Spacer()
                        stepButton("plus", label: "Increase goal") { prefs.dailyGoalMinutes = min(600, prefs.dailyGoalMinutes + 15) }
                    }
                } else {
                    HStack {
                        stepButton("minus", label: "Decrease goal") { prefs.dailyGoalMinutes = max(15, prefs.dailyGoalMinutes - 15) }
                        Spacer()
                        goalValue(prefs: prefs)
                        Spacer()
                        stepButton("plus", label: "Increase goal") { prefs.dailyGoalMinutes = min(600, prefs.dailyGoalMinutes + 15) }
                    }
                }
                Text("One rest day a week never pauses your rhythm. Goals are invitations, never debts.")
                    .font(LMFont.callout.weight(.regular))
                    .foregroundStyle(LMColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(LMSpace.m)
        }
    }

    private func goalValue(prefs: UserPreferences) -> some View {
        VStack(spacing: 2) {
            Text(LMFormat.minutes(prefs.dailyGoalMinutes))
                .font(.system(.largeTitle, weight: .light))
                .foregroundStyle(LMColor.textPrimary)
                .contentTransition(.numericText())
            Text("About \(max(1, Int((Double(prefs.dailyGoalMinutes) / Double(max(5, prefs.defaultFocusMinutes))).rounded()))) stars a day")
                .font(LMFont.footnote)
                .foregroundStyle(LMColor.textTertiary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func stepButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button {
            app.haptics.selection()
            withAnimation(LMSpring.snap) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(LMColor.textPrimary)
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LMColor.textPrimary.opacity(0.07)))
        }
        .accessibilityLabel(Text(label))
    }

    private func appearanceSection(prefs: UserPreferences) -> some View {
        SettingsSection(title: String(localized: "Appearance")) {
            VStack(alignment: .leading, spacing: LMSpace.s) {
                CosmicSegmented(options: AppearancePreference.allCases.map { ($0, $0.title) },
                                selection: Binding(get: { prefs.appearance }, set: { prefs.appearance = $0 }))
                Text("Motion").settingsLabel().padding(.top, LMSpace.xs)
                CosmicSegmented(options: MotionPreference.allCases.map { ($0, $0.title) },
                                selection: Binding(get: { prefs.motion }, set: { prefs.motion = $0 }))
                Text("System Reduce Motion always wins. Calm uses fewer particles; Minimal removes loops and camera moves.")
                    .font(LMFont.footnote)
                    .foregroundStyle(LMColor.textTertiary)
            }
            .padding(LMSpace.m)
        }
    }

    private func soundSection(prefs: UserPreferences) -> some View {
        SettingsSection(title: String(localized: "Sound & haptics")) {
            Toggle(isOn: Binding(get: { prefs.soundEnabled }, set: { prefs.soundEnabled = $0 })) {
                Text("Celebration sounds").settingsLabel()
            }
            .settingsRow()
            SettingsDivider()
            Toggle(isOn: Binding(get: { prefs.hapticsEnabled }, set: { prefs.hapticsEnabled = $0 })) {
                Text("Haptics").settingsLabel()
            }
            .settingsRow()
            SettingsDivider()
            Toggle(isOn: Binding(get: { prefs.finalMinuteTick }, set: { prefs.finalMinuteTick = $0 })) {
                Text("Soft tick in the final minute").settingsLabel()
            }
            .settingsRow()
            SettingsDivider()
            SettingsPickerRow(title: String(localized: "Default ambience")) {
                Picker(String(localized: "Default ambience"), selection: Binding(get: { prefs.ambient.playable }, set: { sound in
                    // A locked sound opens Orbi+ instead of being chosen.
                    guard !sound.isPlus || app.plus.isActive else { return paywall = .ambience }
                    prefs.ambient = sound
                })) {
                    ForEach(AmbientSound.allCases) { sound in
                        Text(sound.isPlus && !app.plus.isActive ? "\(sound.title) · Orbi+" : sound.title).tag(sound)
                    }
                }
            }
            SettingsDivider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Ambient volume").settingsLabel()
                Slider(value: Binding(get: { prefs.ambientVolume }, set: { prefs.ambientVolume = $0 }), in: 0...1)
                    .accessibilityLabel(Text("Ambient volume"))
            }
            .settingsRow()
        }
    }

    private func notificationSection(prefs: UserPreferences) -> some View {
        SettingsSection(title: String(localized: "Notifications")) {
            if notificationStatus == .denied {
                AdaptiveStack {
                    Text("Notifications are off for Orbi. Live Activities still show your session.")
                        .font(LMFont.callout.weight(.regular)).foregroundStyle(LMColor.textSecondary)
                    Spacer()
                    Button(String(localized: "Open Settings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .font(LMFont.callout.weight(.semibold))
                }
                .settingsRow()
                SettingsDivider()
            } else if notificationStatus == .notDetermined {
                Button {
                    Task {
                        await app.notifications.requestAuthorization(source: "settings")
                        prefs.hasSeenNotificationPrompt = true
                        notificationStatus = await app.notifications.authorizationStatus()
                    }
                } label: {
                    Text("Allow gentle notifications").settingsLabel().foregroundStyle(LMColor.calm)
                }
                .settingsRow()
                SettingsDivider()
            }
            Toggle(isOn: Binding(get: { prefs.focusNotifications }, set: { prefs.focusNotifications = $0 })) {
                Text("When a star is born").settingsLabel()
            }
            .settingsRow()
            SettingsDivider()
            Toggle(isOn: Binding(get: { prefs.breakNotifications }, set: { prefs.breakNotifications = $0 })) {
                Text("When a break ends").settingsLabel()
            }
            .settingsRow()
            SettingsDivider()
            Toggle(isOn: Binding(get: { prefs.rareEventNotifications },
                                 set: { prefs.rareEventNotifications = $0; app.syncReminders() })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rare events").settingsLabel()
                    Text("A note at 9:00 on the day something rare crosses your sky.")
                        .font(LMFont.footnote).foregroundStyle(LMColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, LMSpace.xs)
            .settingsRow()
            .accessibilityIdentifier("settings.rareEvents")
            SettingsDivider()
            Toggle(isOn: Binding(get: { prefs.dailyReminderEnabled },
                                 set: { prefs.dailyReminderEnabled = $0; app.syncReminders() })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily invitation").settingsLabel()
                    Text("Only on days you haven't focused yet. Tap it to set up a focus.")
                        .font(LMFont.footnote).foregroundStyle(LMColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, LMSpace.xs)
            .settingsRow()
            .accessibilityIdentifier("settings.dailyInvitation")
            if prefs.dailyReminderEnabled {
                SettingsDivider()
                DatePicker(String(localized: "Time"), selection: Binding(
                    get: { app.clock.calendar.date(from: DateComponents(hour: prefs.dailyReminderHour, minute: prefs.dailyReminderMinute)) ?? .now },
                    set: { date in
                        let c = app.clock.calendar.dateComponents([.hour, .minute], from: date)
                        prefs.dailyReminderHour = c.hour ?? 9
                        prefs.dailyReminderMinute = c.minute ?? 0
                        app.syncReminders()
                    }), displayedComponents: .hourAndMinute)
                    .font(LMFont.body)
                    .foregroundStyle(LMColor.textPrimary)
                    .settingsRow()
            }
        }
    }

    private var intentionsSection: some View {
        SettingsSection(title: String(localized: "Categories & intentions")) {
            AdaptiveStack(spacing: LMSpace.s) {
                ForEach(FocusCategory.allCases) { c in
                    AdaptiveStackItem {
                        CategoryGlyph(category: c, size: 20)
                        Text(c.displayName).font(LMFont.footnote).foregroundStyle(LMColor.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LMSpace.m)
            if !tasks.isEmpty {
                SettingsDivider()
                ForEach(tasks.prefix(12)) { task in
                    HStack {
                        CategoryGlyph(category: task.category, size: 14)
                        Text(task.title).settingsLabel().lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                        Spacer()
                        Button {
                            task.isArchived = true
                            app.dataStore.save()
                        } label: {
                            Image(systemName: "xmark.circle").foregroundStyle(LMColor.textTertiary).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(Text("Forget intention \(task.title)"))
                    }
                    .padding(.leading, LMSpace.m)
                }
            }
        }
    }

    private func shieldSection(prefs: UserPreferences) -> some View {
        SettingsSection(title: String(localized: "Distraction shield")) {
            if FeatureFlags.distractionShield, let shield = app.shield as? ScreenTimeShield {
                ShieldSettingsRows(shield: shield, prefs: prefs)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Coming soon").settingsLabel()
                    Text("Optional Screen Time shielding needs Apple's Family Controls approval. Orbi never sees or blocks other apps without your explicit consent.")
                        .font(LMFont.footnote)
                        .foregroundStyle(LMColor.textTertiary)
                }
                .settingsRow()
            }
        }
    }

    private var cloudSection: some View {
        @Bindable var cloud = app.cloud
        return SettingsSection(title: String(localized: "iCloud")) {
            Toggle(isOn: $cloud.wantsSync) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync with iCloud").settingsLabel()
                    Text(cloudStatus)
                        .font(LMFont.footnote)
                        .foregroundStyle(LMColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, LMSpace.s)
            .settingsRow()
            .accessibilityIdentifier("settings.icloud")
        }
        .task { await app.cloud.refreshAccount() }
    }

    private var cloudStatus: String {
        let cloud = app.cloud
        if cloud.settingChangedSinceLaunch {
            return cloud.wantsSync
                ? String(localized: "Turns on the next time you open Orbi.")
                : String(localized: "Turns off the next time you open Orbi. What's already in iCloud stays there.")
        }
        guard cloud.isActive else { return String(localized: "Your universe stays on this device only.") }
        return switch cloud.account {
        case .available, .checking:
            String(localized: "Your sessions, worlds and settings follow you to your other devices, in your private iCloud. The sky is redrawn from them on each device.")
        case .noAccount:
            String(localized: "Sign in to iCloud in the Settings app to sync your universe.")
        case .restricted, .unavailable:
            String(localized: "iCloud isn't available right now. Your universe is safe on this device.")
        }
    }

    private var dataSection: some View {
        SettingsSection(title: String(localized: "Your data")) {
            Button {
                do {
                    exportDocument = JSONExportDocument(data: try app.dataStore.exportJSON(now: app.clock.now))
                    showExporter = true
                    Telemetry.log(.dataExported)
                } catch {
                    exportError = error.localizedDescription
                }
            } label: {
                HStack {
                    Text("Export my universe (JSON)").settingsLabel()
                    Spacer()
                    Image(systemName: "square.and.arrow.up").foregroundStyle(LMColor.textTertiary)
                }
            }
            .settingsRow()
            SettingsDivider()
            Toggle(isOn: Binding(get: { sharesUsageData }, set: { on in
                sharesUsageData = on
                Telemetry.setOptedOut(!on)
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share usage data").settingsLabel()
                    Text("Anonymous: which features are used and how sessions go. Never your intentions, tasks or name, and no ad tracking.")
                        .font(LMFont.footnote)
                        .foregroundStyle(LMColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .settingsRow()
            .accessibilityIdentifier("settings.usageData")
            SettingsDivider()
            Button(role: .destructive) {
                confirmErase = true
            } label: {
                Text("Erase all data").font(LMFont.body).foregroundStyle(Color(hex: 0xFF7A8A))
            }
            .settingsRow()
            .accessibilityIdentifier("settings.erase")
            SettingsDivider()
            Link(destination: URL(string: "https://www.mobapptech.com/lumora-privacy-policy/")!) {
                HStack {
                    Text("Privacy policy").settingsLabel()
                    Spacer()
                    Image(systemName: "arrow.up.right").foregroundStyle(LMColor.textTertiary)
                }
            }
            .settingsRow()
        }
    }
}

// MARK: - Building blocks

struct SettingsSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: LMSpace.xs) {
            EyebrowText(title)
                .padding(.leading, LMSpace.xs)
            VStack(spacing: 0) { content }
                .glassCard(radius: LMRadius.card)
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(LMColor.hairline).frame(height: 1).padding(.leading, LMSpace.m)
    }
}

struct MinutesPickerRow: View {
    var title: String
    @Binding var value: Int
    var options: [Int]

    var body: some View {
        SettingsPickerRow(title: title) {
            Picker(title, selection: $value) {
                ForEach(Array(Set(options + [value])).sorted(), id: \.self) { Text("\($0) min").tag($0) }
            }
        }
    }
}

/// Label + menu picker. Side by side normally; stacked at accessibility
/// sizes so neither the label nor the value is squeezed.
struct SettingsPickerRow<PickerContent: View>: View {
    var title: String
    @ViewBuilder var picker: PickerContent
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        AdaptiveStack(spacing: stacked ? 0 : nil) {
            Text(title).settingsLabel()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            if !stacked { Spacer() }
            picker
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize(horizontal: stacked, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, stacked ? LMSpace.s : 0)
        .settingsRow()
    }
}

private extension Text {
    func settingsLabel() -> some View {
        self.font(LMFont.body).foregroundStyle(LMColor.textPrimary)
    }
}

private extension View {
    func settingsRow() -> some View {
        self.padding(.horizontal, LMSpace.m).frame(minHeight: 56)
    }
}

/// File wrapper for "Export my universe".
struct JSONExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#if DEBUG
/// Debug-only tools. Acceleration is clamped to 1× by the engine in release
/// builds, so none of this can affect production timing.
struct DebugSettingsSection: View {
    @Environment(AppModel.self) private var app
    @AppStorage(DebugSettings.timeScaleKey) private var timeScale: Double = 1
    @State private var showsFinished = false

    var body: some View {
        SettingsSection(title: "Debug") {
            Picker("Session speed", selection: $timeScale) {
                Text("Real time").tag(1.0)
                Text("60× (25 min ≈ 25 s)").tag(60.0)
                Text("300× (25 min = 5 s)").tag(300.0)
            }
            .pickerStyle(.menu)
            .padding(.horizontal, LMSpace.m)
            .frame(minHeight: 56)
            SettingsDivider()
            Button("Add 12 demo sessions") {
                DemoDataSeeder.seed(sessions: 12, into: app)
            }
            .padding(.horizontal, LMSpace.m)
            .frame(minHeight: 56)
            SettingsDivider()
            Button {
                showsFinished = true
            } label: {
                Text(verbatim: "Preview the finished universe")
            }
            .padding(.horizontal, LMSpace.m)
            .frame(minHeight: 56)
            .accessibilityIdentifier("debug.finishedUniverse")
        }
        .fullScreenCover(isPresented: $showsFinished) { FinishedUniversePreview() }
    }
}

enum DebugSettings {
    static let timeScaleKey = "debug.timeScale"
    static var timeScale: Double { max(1, UserDefaults.standard.double(forKey: timeScaleKey)) }
}
#endif
