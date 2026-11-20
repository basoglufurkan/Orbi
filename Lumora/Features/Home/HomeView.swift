import SwiftData
import SwiftUI

/// Today: the living universe, front and centre, with today's light and one
/// clear action beneath it. The day's plan, habits and tasks live on Plan,
/// so nothing here stands between you and your sky.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var camera = UniverseCamera.home
    @State private var flight: CameraFlight?
    @State private var inspected: CelestialSnapshot?
    /// Measured heights of the header and of the cards under the sky; the
    /// sky is framed into the band between them.
    @State private var headerHeight: CGFloat = 0
    @State private var dockHeight: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Room for the floating orbit bar under the button.
    private static let barClearance: CGFloat = 84

    var body: some View {
        StatsReader { stats, _ in
            UniverseSceneReader { scene in
                GeometryReader { geo in
                    let full = CGSize(width: geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing,
                                      height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom)
                    let band = skyBand(geo: geo, full: full)
                    ZStack(alignment: .top) {
                        CosmicBackgroundView(mood: .home, light: scene.ambientLight, showsStars: true, starOpacity: 0.6)

                        // Full-screen canvas: the universe fills everything above
                        // the cards and fades out just before them, so no light
                        // or label peeks out between them.
                        UniverseCanvasView(scene: scene, camera: $camera, flight: $flight, interactive: false,
                                           selectedID: inspected?.id) { inspected = $0 } onWorld: { world in
                            app.odysseyFocusWorld = world.ordinal
                            app.selectedTab = .odyssey
                        }
                            .mask(skyMask(band: band, height: full.height))
                            .ignoresSafeArea()
                            .onAppear { frame(scene, canvas: full, band: band) }
                            .onChange(of: scene.homeFocusPoints()) { _, _ in frame(scene, canvas: full, band: band) }
                            .onChange(of: band) { _, band in frame(scene, canvas: full, band: band) }

                        // The fixed layout leaves the sky tappable; it scrolls
                        // only when it can't fit (small iPhones, large text).
                        ViewThatFits(in: .vertical) {
                            column(stats: stats)
                            ScrollView { column(stats: stats) }
                                .scrollIndicators(.hidden)
                                .statusBarScrim()
                        }
                    }
                }
            }
        }
        .sheet(item: $inspected) { object in
            CelestialDetailView(object: object)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private func column(stats: ProgressStats) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(stats: stats)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            Spacer(minLength: LMSpace.xl)
            if !typeSize.isAccessibilitySize {
                // Floats over the bottom of the sky, just above the cards.
                Text("Tap any light to see what made it")
                    .font(LMFont.callout)
                    .foregroundStyle(LMColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, LMSpace.s)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 0) {
                if OdysseyStatusRow.hasContent(app) {
                    OdysseyStatusRow()
                } else {
                    RecentAccomplishmentsRow()
                }
                TodayCard(stats: stats)
                    .padding(.bottom, LMSpace.m)
                CosmicButton(title: "Begin Focus", systemImage: "sparkle") {
                    app.timer.prepare()
                }
                .accessibilityIdentifier("home.beginFocus")
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { dockHeight = $0 }
            Color.clear.frame(height: Self.barClearance)
        }
        .padding(.horizontal, LMSpace.l)
        .readableColumn()
        .task(id: stats.todayMinutes) { pellNotes(stats: stats) }
    }

    /// The sky's band in full-screen points: below the header, above the
    /// cards. When the column scrolls (small iPhones, large text) there is
    /// no such room, and the sky keeps a fixed band at the top instead.
    private func skyBand(geo: GeometryProxy, full: CGSize) -> SkyBand {
        let top = geo.safeAreaInsets.top + headerHeight
        let bottom = geo.safeAreaInsets.top + geo.size.height - Self.barClearance - dockHeight
        // A column that fits always keeps at least its spacer between the two.
        guard headerHeight > 0, dockHeight > 0, bottom - top >= LMSpace.xl else {
            return SkyBand(top: geo.safeAreaInsets.top + 170, bottom: full.height * 0.64)
        }
        return SkyBand(top: top, bottom: bottom)
    }

    /// Opaque over the sky's band, fading to nothing just before the cards.
    private func skyMask(band: SkyBand, height: CGFloat) -> LinearGradient {
        guard height > 0, band.bottom > band.top else {
            return LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.6),
                                          .init(color: .clear, location: 0.74)], startPoint: .top, endPoint: .bottom)
        }
        let fadeEnd = min(1, (band.bottom + 4) / height)
        let fadeStart = max(0, min(fadeEnd - 0.01, (band.bottom - 56) / height))
        return LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: fadeStart),
                                      .init(color: .clear, location: fadeEnd)], startPoint: .top, endPoint: .bottom)
    }

    /// Pell's word on Today: hello the first time, then a welcome back after
    /// a few quiet days, or a cheer when today's goal is reached.
    private func pellNotes(stats: ProgressStats) {
        let name = app.preferences.displayName
        let today = app.today
        app.pell.offer(.hello(name: name))
        let goal = app.preferences.dailyGoalMinutes
        if goal > 0, stats.todayMinutes >= goal {
            app.pell.offer(.goalReached(name: name, day: today))
        } else if stats.todayMinutes == 0, let last = stats.focusDays.max(),
                  let lastDate = last.startDate(calendar: app.clock.calendar),
                  let days = app.clock.calendar.dateComponents([.day], from: lastDate, to: app.clock.now).day, days >= 3 {
            app.pell.offer(.welcomeBack(name: name, day: today))
        }
    }

    /// Fits the hero world and recent stars into the sky's band, in
    /// full-screen canvas coordinates. Waits for the header and cards to be
    /// measured, so the sky is framed once rather than twice.
    private func frame(_ scene: UniverseScene, canvas: CGSize, band: SkyBand) {
        guard headerHeight > 0, dockHeight > 0, canvas.width > 0, band.bottom > band.top else { return }
        let size = CGSize(width: canvas.width, height: max(160, band.bottom - band.top))
        var cam = UniverseCamera.fitting(scene.homeFocusPoints(), in: size, padding: 56, zoomRange: 0.5...1.6)
        let shift = (band.top + size.height / 2) - canvas.height / 2
        cam.center.y -= shift / cam.zoom
        camera = cam
    }

    private func header(stats: ProgressStats) -> some View {
        HStack(alignment: .top, spacing: LMSpace.s) {
            VStack(alignment: .leading, spacing: LMSpace.xs) {
                EyebrowText(eyebrow, color: LMColor.calm)
                Text(headline(stats: stats))
                    .font(LMFont.voice(.largeTitle))
                    .foregroundStyle(LMColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            RoundControlButton(systemImage: "slider.horizontal.3", label: "Settings", size: 52) {
                app.isShowingSettings = true
            }
            .accessibilityIdentifier("home.settings")
        }
        .padding(.top, LMSpace.m)
    }

    private var eyebrow: String {
        let hour = app.clock.calendar.component(.hour, from: app.clock.now)
        let greeting: String = switch hour {
        case 5..<12: String(localized: "Good morning")
        case 12..<17: String(localized: "Good afternoon")
        case 17..<22: String(localized: "Good evening")
        default: String(localized: "Good night")
        }
        let name = app.preferences.displayName
        let day = String(localized: "Day \(app.universeDay)")
        return name.isEmpty ? "\(day) · \(greeting)" : "\(day) · \(greeting), \(name)"
    }

    private func headline(stats: ProgressStats) -> String {
        if let last = stats.focusDays.max(), let lastDate = last.startDate(calendar: app.clock.calendar),
           let days = app.clock.calendar.dateComponents([.day], from: lastDate, to: app.clock.now).day, days >= 14 {
            return String(localized: "Welcome back.\nEvery star waited.")
        }
        if stats.todayQualifyingSessions > 0 {
            return String(localized: "Your sky is\ngrowing today.")
        }
        return String(localized: "Ready to create\nsomething today?")
    }
}

/// Where the sky shows on Today, in full-screen points.
private struct SkyBand: Equatable {
    var top: CGFloat
    var bottom: CGFloat
}

/// "70 of 120 min today · 2 more sessions connect today's stars · 12 days"
struct TodayCard: View {
    var stats: ProgressStats
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let goal = app.preferences.dailyGoalMinutes
        let progress = goal > 0 ? Double(stats.todayMinutes) / Double(goal) : 0
        let stacked = typeSize.isAccessibilitySize
        AdaptiveStack(spacing: stacked ? LMSpace.s : LMSpace.m) {
            ZStack {
                OrbitalProgressView(progress: min(1, progress), lineWidth: 4, trackWidth: 4, headSize: 0, showsHead: false)
                Image(systemName: "sparkle").font(.system(size: 16, weight: .semibold)).foregroundStyle(LMColor.textPrimary)
            }
            .frame(width: 58, height: 58)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                // The rhythm rides beside the minutes, so the line under them
                // keeps the card's whole width instead of wrapping word by word.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: LMSpace.xs) {
                        minutes(goal: goal)
                        Spacer(minLength: LMSpace.xs)
                        RhythmPill(rhythm: stats.currentRhythm)
                    }
                    VStack(alignment: .leading, spacing: LMSpace.xs) {
                        minutes(goal: goal)
                        RhythmPill(rhythm: stats.currentRhythm)
                    }
                }
                Text(subline)
                    .font(LMFont.callout.weight(.regular))
                    .foregroundStyle(LMColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LMSpace.m)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.todayCard")
    }

    private func minutes(goal: Int) -> some View {
        Text("\(stats.todayMinutes) of \(goal) min today")
            .font(LMFont.headline)
            .foregroundStyle(LMColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var subline: String {
        let perConstellation = app.rules.starsPerConstellation
        let today = stats.todayQualifyingSessions
        if today == 0 { return String(localized: "Your first star today is waiting") }
        let remaining = perConstellation - today % perConstellation
        if today % perConstellation == 0 { return String(localized: "Today's stars are connected") }
        return remaining == 1
            ? String(localized: "1 more session connects today's stars")
            : String(localized: "\(remaining) more sessions connect today's stars")
    }
}

struct RhythmPill: View {
    var rhythm: RhythmStatus

    var body: some View {
        if rhythm.days > 0 {
            StatusPill(text: rhythm.days == 1 ? String(localized: "1 day") : String(localized: "\(rhythm.days) days"),
                       systemImage: "sparkle")
                .accessibilityLabel(Text("\(rhythm.days)-day rhythm"))
        } else if rhythm.isPaused {
            StatusPill(text: String(localized: "Rhythm resting"), systemImage: "moon", tint: LMColor.calm)
        }
    }
}

/// Up to three most recent artifacts, opening the Collection.
struct RecentAccomplishmentsRow: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \AchievementUnlock.unlockedAt, order: .reverse) private var unlocks: [AchievementUnlock]

    var body: some View {
        let recent = Array(unlocks.prefix(3))
        if !recent.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LMSpace.xs) {
                    ForEach(recent, id: \.achievementID) { unlock in
                        if let def = unlock.definition {
                            Button {
                                app.haptics.selection()
                                app.isShowingCollection = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "diamond.fill").font(.caption2).foregroundStyle(LMColor.reward)
                                    Text(def.title).font(LMFont.footnote).foregroundStyle(LMColor.textPrimary)
                                    Text(LMFormat.shortDate(unlock.unlockedAt)).font(LMFont.footnote).foregroundStyle(LMColor.textTertiary)
                                }
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .glassCard(radius: 22)
                            }
                            .buttonStyle(PressScaleStyle())
                            .accessibilityLabel(Text("Artifact \(def.title), earned \(LMFormat.shortDate(unlock.unlockedAt))"))
                        }
                    }
                }
            }
            .scrollClipDisabled()
            .padding(.bottom, LMSpace.s)
        }
    }
}
