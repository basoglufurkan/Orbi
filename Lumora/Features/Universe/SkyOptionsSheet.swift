import SwiftUI

/// "Your sky" options, in a bottom sheet over the Universe: what the sky
/// draws besides the stars themselves. Each switch applies at once, here
/// and on Today's sky.
struct SkyOptionsSheet: View {
    /// Odyssey worlds not landed on yet; the switch rests when there are none.
    var unchartedCount: Int

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SkyPreferences.connectsConstellations) private var connectsConstellations = true
    @AppStorage(SkyPreferences.marksToday) private var marksToday = true
    @AppStorage(SkyPreferences.showsUnchartedWorlds) private var showsUncharted = false
    @AppStorage(SkyPreferences.theme) private var themeRaw = SkyTheme.classic.rawValue
    @State private var paywall: PlusFeature?

    var body: some View {
        NavigationStack {
            ScrollView {
                themePicker
                    .padding(.horizontal, LMSpace.l)
                    .padding(.top, LMSpace.s)
                    .readableColumn()
                VStack(spacing: 0) {
                    row(icon: "point.3.connected.trianglepath.dotted", tint: LMColor.textPrimary,
                        title: String(localized: "Connect constellations"),
                        detail: String(localized: "Lines between the stars of each constellation."),
                        isOn: $connectsConstellations, id: "sky.constellations")
                    SettingsDivider()
                    row(icon: "calendar.day.timeline.left", tint: LMColor.calm,
                        title: String(localized: "Show today"),
                        detail: String(localized: "Today's stars, joined by a dashed line and framed."),
                        isOn: $marksToday, id: "sky.today")
                    SettingsDivider()
                    row(icon: "globe.europe.africa", tint: LMColor.reward,
                        title: String(localized: "Uncharted worlds"),
                        detail: unchartedCount == 0
                            ? String(localized: "Worlds you haven't landed on yet appear here, veiled. None right now.")
                            : String(localized: "Worlds you haven't landed on yet, veiled."),
                        isOn: $showsUncharted, id: "universe.showUncharted")
                        .disabled(unchartedCount == 0)
                }
                .glassCard(radius: LMRadius.card)
                .padding(.horizontal, LMSpace.l)
                .padding(.top, LMSpace.s)
                .readableColumn()
            }
            .scrollBounceBehavior(.basedOnSize)
            .plusPaywall($paywall, screen: "sky_options")
            .navigationTitle(String(localized: "Your sky"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .telemetryScreen("sky_options")
    }

    private var themePicker: some View {
        let current = SkyTheme.current(raw: themeRaw, plusActive: app.plus.isActive)
        return VStack(alignment: .leading, spacing: LMSpace.s) {
            HStack(spacing: LMSpace.xs) {
                EyebrowText(String(localized: "Sky theme"))
                if !app.plus.isActive { PlusBadge() }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LMSpace.m) {
                    ForEach(SkyTheme.allCases) { theme in
                        themeSwatch(theme, isSelected: theme == current)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
        .padding(LMSpace.m)
        .glassCard(radius: LMRadius.card)
    }

    private func themeSwatch(_ theme: SkyTheme, isSelected: Bool) -> some View {
        let locked = theme.isPlus && !app.plus.isActive
        return Button {
            app.haptics.selection()
            guard !locked else { return paywall = .skyThemes }
            withAnimation(LMSpring.settle) { themeRaw = theme.rawValue }
            Telemetry.log(.skyThemeChanged(theme: theme.rawValue))
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(LMColor.bgBase)
                    Circle().fill(RadialGradient(colors: [Color(hex: theme.washes.primary).opacity(0.9), .clear],
                                                 center: UnitPoint(x: 0.4, y: 0.4), startRadius: 0, endRadius: 30))
                    Circle().fill(RadialGradient(colors: [Color(hex: theme.washes.secondary).opacity(0.7), .clear],
                                                 center: UnitPoint(x: 0.85, y: 0.8), startRadius: 0, endRadius: 22))
                    if locked {
                        Image(systemName: "lock.fill").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.85))
                    }
                }
                .frame(width: 56, height: 56)
                .overlay(Circle().strokeBorder(isSelected ? LMColor.textPrimary : LMColor.hairline, lineWidth: isSelected ? 2 : 1))
                Text(theme.title).font(LMFont.footnote).foregroundStyle(isSelected ? LMColor.textPrimary : LMColor.textSecondary)
            }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("sky.theme.\(theme.rawValue)")
    }

    private func row(icon: String, tint: Color, title: String, detail: String, isOn: Binding<Bool>, id: String) -> some View {
        Toggle(isOn: isOn.animation(LMSpring.settle)) {
            HStack(spacing: LMSpace.s) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(LMFont.body).foregroundStyle(LMColor.textPrimary)
                    Text(detail).font(LMFont.footnote).foregroundStyle(LMColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(LMColor.calm)
        .onChange(of: isOn.wrappedValue) { _, on in
            app.haptics.selection()
            Telemetry.log(.skyOptionChanged(option: id, on: on))
        }
        .padding(.horizontal, LMSpace.m)
        .padding(.vertical, LMSpace.s)
        .frame(minHeight: 64)
        .accessibilityIdentifier(id)
    }
}
