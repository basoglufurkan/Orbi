import SwiftData
import SwiftUI

/// "Your universe": the full, explorable sky. Drag to drift, pinch to zoom,
/// tap a light, jump between regions, and scrub the journey timeline to
/// watch the universe grow.
struct UniverseExplorerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.motionLevel) private var motion
    @Query(sort: \CelestialObject.bornAt) private var objects: [CelestialObject]

    @State private var camera = UniverseCamera(center: .zero, zoom: 0.8)
    @State private var flight: CameraFlight?
    @State private var inspected: CelestialSnapshot?
    @State private var selectedID: UUID?
    @State private var scrub: Double = 1
    @State private var viewSize: CGSize = .zero
    @State private var didInitialFrame = false
    @State private var showsSkyOptions = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        UniverseSceneReader(visibleUntil: cutoffDate) { scene in
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    CosmicBackgroundView(mood: .home, light: scene.ambientLight, showsStars: false)
                    UniverseCanvasView(scene: scene, camera: $camera, flight: $flight, interactive: true,
                                       selectedID: selectedID) { object in
                        app.haptics.selection()
                        selectedID = object.id
                        inspected = object
                    } onWorld: { world in
                        app.haptics.selection()
                        app.odysseyFocusWorld = world.ordinal
                        app.selectedTab = .odyssey
                    }
                    .ignoresSafeArea()
                    .accessibilityIdentifier("universe.canvas")

                    VStack(alignment: .leading, spacing: LMSpace.s) {
                        header(scene: scene)
                        regionChips(scene: scene)
                        Spacer()
                        HStack {
                            Spacer()
                            zoomControls
                        }
                        if !typeSize.isAccessibilitySize {
                            Text("Pinch to zoom · drag to drift · tap a light")
                                .font(LMFont.callout)
                                .foregroundStyle(LMColor.textTertiary)
                                .frame(maxWidth: .infinity)
                                .accessibilityHidden(true)
                        }
                        JourneyCard(scrub: $scrub, firstDate: firstDate, day: app.universeDay)
                        Color.clear.frame(height: 76)
                    }
                    .padding(.horizontal, LMSpace.l)
                    // The chrome floats over the sky it controls; past AX1 it
                    // would cover the whole canvas, so it stops growing there.
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
                .onAppear {
                    viewSize = geo.size
                    focusIfRequested(scene: scene, size: geo.size)
                }
                .onChange(of: app.universeFocus) { _, _ in focusIfRequested(scene: scene, size: geo.size) }
                .onChange(of: scene.all.count) { _, _ in focusIfRequested(scene: scene, size: geo.size) }
            }
        }
        .sheet(item: $inspected, onDismiss: { selectedID = nil }) { object in
            CelestialDetailView(object: object)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Header

    private func header(scene: UniverseScene) -> some View {
        HStack(alignment: .top, spacing: LMSpace.s) {
            headerText(scene: scene)
            Spacer(minLength: 0)
            skyOptionsButton(scene: scene)
            shareButton(scene: scene)
        }
    }

    /// Opens the sky's options (constellation lines, today, uncharted worlds).
    private func skyOptionsButton(scene: UniverseScene) -> some View {
        Button {
            app.haptics.selection()
            showsSkyOptions = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LMColor.textPrimary)
                .frame(width: 44, height: 44)
                .glassCard(radius: 22)
        }
        .buttonStyle(PressScaleStyle())
        .padding(.top, LMSpace.m)
        .accessibilityLabel(Text("Sky options"))
        .accessibilityIdentifier("universe.skyOptions")
        .sheet(isPresented: $showsSkyOptions) {
            SkyOptionsSheet(unchartedCount: scene.unchartedCount)
                .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(540), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
                // The sky stays visible and live behind the sheet as switches change it.
                .presentationBackgroundInteraction(.enabled(upThrough: .height(380)))
        }
    }

    /// Shares a card of the whole sky with your rank.
    private func shareButton(scene: UniverseScene) -> some View {
        let charted = scene.voyages.filter(\.charted).count
        var stat = countsLine(scene)
        if charted > 0 {
            stat += " · " + (charted == 1 ? String(localized: "1 world charted") : String(localized: "\(charted) worlds charted"))
        }
        let card = UniverseShareImage(content: UniverseShareContent(scene: scene, rank: app.odyssey.snapshot.rank,
                                                                    day: app.universeDay, stat: stat))
        return ShareLink(item: card,
                         message: Text(verbatim: String(localized: "Day \(app.universeDay) of my universe in Orbi: \(scene.stars.count) stars, grown one focus session at a time. ✦")
                                       + "\n" + DeepLink.landingPage.absoluteString),
                         preview: SharePreview(Text("Your universe"), image: card)) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LMColor.textPrimary)
                .frame(width: 44, height: 44)
                .glassCard(radius: 22)
        }
        .padding(.top, LMSpace.m)
        .simultaneousGesture(TapGesture().onEnded { Telemetry.log(.universeShared(kind: "universe")) })
        .accessibilityLabel(Text("Share my universe"))
        .accessibilityIdentifier("universe.share")
    }

    private func headerText(scene: UniverseScene) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your universe")
                .font(LMFont.largeTitle)
                .foregroundStyle(LMColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(countsLine(scene))
                .font(LMFont.callout.weight(.regular))
                .foregroundStyle(LMColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("universe.counts")
        }
        .padding(.top, LMSpace.m)
    }

    private func countsLine(_ scene: UniverseScene) -> String {
        let stars = scene.stars.count
        let constellations = scene.constellations.count
        let planets = scene.planets.count
        var parts = [stars == 1 ? String(localized: "1 star") : String(localized: "\(stars) stars")]
        parts.append(constellations == 1 ? String(localized: "1 constellation") : String(localized: "\(constellations) constellations"))
        parts.append(planets == 1 ? String(localized: "1 planet") : String(localized: "\(planets) planets"))
        return parts.joined(separator: " · ")
    }

    private func regionChips(scene: UniverseScene) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LMSpace.xs) {
                if !scene.voyages.isEmpty {
                    // Your Odyssey worlds live among the days that formed them; this finds the latest.
                    Button {
                        app.haptics.selection()
                        if let focus = scene.odysseyFocus { fly(to: UniverseCamera(center: focus, zoom: 0.9)) }
                    } label: {
                        HStack(spacing: 6) {
                            RocketGlyph()
                                .stroke(LMColor.reward, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                                .frame(width: 14, height: 14)
                            Text("Odyssey").font(LMFont.headline.weight(.semibold))
                        }
                        .foregroundStyle(LMColor.textPrimary)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .glassCard(radius: 22)
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityIdentifier("universe.odyssey")
                }
                ForEach(UniverseRegion.allCases) { region in
                    let open = scene.openRegions.contains(region)
                    Button {
                        app.haptics.selection()
                        fly(to: UniverseCamera(center: region.center, zoom: 0.75))
                    } label: {
                        HStack(spacing: 6) {
                            if !open { Image(systemName: "lock.fill").font(.caption2) }
                            Text(region.displayName).font(LMFont.headline.weight(.semibold))
                        }
                        .foregroundStyle(open ? LMColor.textPrimary : LMColor.textTertiary)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .glassCard(radius: 22)
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel(open ? Text(region.displayName) : Text("\(region.displayName), opens at \(region.unlockSessions) sessions"))
                }

            }
        }
        .scrollClipDisabled()
    }

    private var zoomControls: some View {
        VStack(spacing: 0) {
            Button { zoom(by: 1.4) } label: {
                Image(systemName: "plus").frame(width: 52, height: 52)
            }
            .accessibilityLabel(Text("Zoom in"))
            Divider().frame(width: 28).overlay(LMColor.hairline)
            Button { zoom(by: 1 / 1.4) } label: {
                Image(systemName: "minus").frame(width: 52, height: 52)
            }
            .accessibilityLabel(Text("Zoom out"))
            .accessibilityIdentifier("universe.zoomOut")
        }
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(LMColor.textPrimary)
        .glassCard(radius: 26)
    }

    // MARK: Camera

    private func zoom(by factor: Double) {
        app.haptics.selection()
        var target = flight?.to ?? camera
        target.zoom = min(UniverseCamera.zoomRange.upperBound, max(UniverseCamera.zoomRange.lowerBound, target.zoom * factor))
        fly(to: target, duration: 0.45)
    }

    private func fly(to target: UniverseCamera, duration: Double = 0.9) {
        guard motion.animatesContinuously else {
            camera = target
            flight = nil
            return
        }
        let from = flight?.camera(at: .now) ?? camera
        camera = target
        flight = CameraFlight(from: from, to: target, start: .now, duration: duration, curve: .emerge)
    }

    private func focusIfRequested(scene: UniverseScene, size: CGSize) {
        // The scene loads asynchronously from SwiftData; wait for it.
        guard !scene.all.isEmpty, size.width > 0 else { return }
        if let id = app.universeFocus, let object = scene.all.first(where: { $0.id == id }) {
            app.universeFocus = nil
            selectedID = id
            let wide = UniverseCamera(center: object.position, zoom: 0.5)
            let close = UniverseCamera(center: object.position, zoom: object.kind == .planet ? 1.3 : 1.6)
            if motion.animatesContinuously {
                flight = CameraFlight(from: wide, to: close, start: .now, duration: 1.4, curve: .emerge)
                camera = close
            } else {
                camera = close
            }
            didInitialFrame = true
        } else if !didInitialFrame {
            didInitialFrame = true
            // Open on the most recent part of the sky at a readable zoom;
            // the rest is a drag or a region chip away.
            camera = UniverseCamera.fitting(scene.homeFocusPoints(), in: size, padding: 70, zoomRange: 0.55...1.3)
        }
    }

    // MARK: Journey scrub

    private var firstDate: Date {
        objects.first?.bornAt ?? app.dataStore.progress()?.createdAt ?? app.clock.now
    }

    /// nil when scrubbed to "today" (show everything, live).
    private var cutoffDate: Date? {
        guard scrub < 0.999 else { return nil }
        let start = firstDate.timeIntervalSinceReferenceDate
        let end = app.clock.now.timeIntervalSinceReferenceDate
        // Every new cutoff rebuilds the whole sky, so snap to 1/200 of the
        // journey and to the minute: a drag rebuilds at most 200 times, and an
        // unrelated redraw while scrubbed doesn't rebuild at all.
        let step = (scrub * 200).rounded(.down) / 200
        let t = start + (end - start) * step
        return Date(timeIntervalSinceReferenceDate: (t / 60).rounded(.down) * 60)
    }
}

/// "Your journey": scrub from First Light to today.
struct JourneyCard: View {
    @Binding var scrub: Double
    var firstDate: Date
    var day: Int

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: LMSpace.xs) {
            AdaptiveStack(spacing: 2) {
                EyebrowText(String(localized: "Your journey"))
                if !stacked { Spacer() }
                Text(scrub >= 0.999 ? String(localized: "Day \(day) · Today") : scrubLabel)
                    .font(LMFont.headline)
                    .foregroundStyle(LMColor.textPrimary)
                    .contentTransition(.numericText())
            }
            Slider(value: $scrub, in: 0...1)
                .tint(LMColor.focus)
                .accessibilityLabel(Text("Journey timeline"))
                .accessibilityValue(Text(scrub >= 0.999 ? String(localized: "Today") : scrubLabel))
            // The slider's ends; at accessibility sizes the value above says it all.
            if !stacked {
                HStack {
                    Text("\(LMFormat.shortDate(firstDate)) · \(String(localized: "First Light"))")
                    Spacer()
                    Text("Today")
                }
                .font(LMFont.footnote)
                .foregroundStyle(LMColor.textTertiary)
            }
        }
        .padding(.horizontal, LMSpace.m)
        .padding(.vertical, 14)
        .glassCard()
    }

    private var scrubLabel: String {
        let start = firstDate.timeIntervalSinceReferenceDate
        let date = Date(timeIntervalSinceReferenceDate: start + (Date.now.timeIntervalSinceReferenceDate - start) * scrub)
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
