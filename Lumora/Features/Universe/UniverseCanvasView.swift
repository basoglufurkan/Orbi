import SwiftUI

/// Interactive universe: drag to drift, pinch to zoom, tap a light.
///
/// Rendering runs in a `TimelineView` only while something moves (ambient
/// twinkle when allowed, a camera flight, or a gesture); with Reduce Motion
/// or in the background it draws a single static frame. Background stars
/// form three parallax layers (0.2 / 0.5 / 1.0) that follow both the camera
/// and the device tilt; universe objects shift gently with the tilt too.
/// Expensive objects are drawn from `SkySprites` bitmaps, and frames run at
/// the display's full rate (120 Hz on ProMotion) while the sky moves.
struct UniverseCanvasView: View {
    var scene: UniverseScene
    @Binding var camera: UniverseCamera
    @Binding var flight: CameraFlight?
    var interactive = true
    var showsLabels = true
    var selectedID: UUID?
    var extraLight: Double = 0
    var onTap: (CelestialSnapshot) -> Void = { _ in }
    /// An Odyssey world in the sky was tapped.
    var onWorld: (WorldState) -> Void = { _ in }

    @Environment(\.motionLevel) private var motion
    @AppStorage(SkyPreferences.connectsConstellations) private var connectsConstellations = true
    @AppStorage(SkyPreferences.marksToday) private var marksToday = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.parallax) private var parallax
    @Environment(\.displayScale) private var displayScale

    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1
    @State private var viewSize: CGSize = .zero

    /// Depth of universe objects for gyro parallax: subtle, so taps stay true.
    private static let objectDepth: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            let ambient = motion.animatesContinuously && scenePhase == .active
            let moving = flight != nil || dragTranslation != .zero || pinchScale != 1
            let tilting = parallax?.isRunning ?? false
            let sprites = SkySprites.shared
            // Read so a paused sky redraws once new bitmaps are ready.
            let _ = sprites.generation
            TimelineView(.animation(minimumInterval: moving ? nil : (tilting ? 1.0 / 30 : motion.frameInterval(24)), paused: !(ambient || moving))) { timeline in
                let tilt = parallax?.offset(depth: 1) ?? .zero
                Canvas { ctx, size in
                    let cam = liveCamera(at: timeline.date)
                    StarFieldPainter.draw(&ctx, size: size,
                                          offset: CGPoint(x: -cam.center.x * cam.zoom, y: -cam.center.y * cam.zoom),
                                          tilt: tilt,
                                          opacity: colorScheme == .dark ? 0.9 : 0.5,
                                          time: ambient ? timeline.date.timeIntervalSinceReferenceDate : nil,
                                          tint: colorScheme == .dark ? .white : Color(hex: 0x5B4BE0))
                    ctx.translateBy(x: tilt.x * Self.objectDepth, y: tilt.y * Self.objectDepth)
                    UniverseRenderer.draw(&ctx, size: size, scene: scene, camera: cam, options: .init(
                        time: ambient ? timeline.date.timeIntervalSinceReferenceDate : nil,
                        selectedID: selectedID, dark: colorScheme == .dark, showLabels: showsLabels,
                        showConstellations: connectsConstellations, showToday: marksToday,
                        extraLight: extraLight, sprites: sprites, displayScale: displayScale))
                }
                .onChange(of: timeline.date) { _, date in
                    if let f = flight, f.isFinished(at: date) {
                        camera = f.to
                        flight = nil
                    }
                }
            }
            .parallaxConsumer()
            .contentShape(Rectangle())
            .gesture(interactive ? navigationGesture(size: geo.size) : nil)
            .simultaneousGesture(tapGesture(size: geo.size))
            .onAppear { viewSize = geo.size }
            .onChange(of: geo.size) { _, s in viewSize = s }
            .overlay {
                // Its own view, compared by value: a drag frame doesn't rebuild it.
                UniverseAccessibilityLayer(scene: scene, camera: camera, size: geo.size, onTap: onTap, onWorld: onWorld)
                    .equatable()
            }
        }
    }

    /// Camera including in-flight gesture deltas and any running flight.
    private func liveCamera(at date: Date) -> UniverseCamera {
        if let flight { return flight.isFinished(at: date) ? flight.to : flight.camera(at: date) }
        var cam = camera
        cam.zoom = clampZoom(cam.zoom * pinchScale)
        cam.center.x -= dragTranslation.width / cam.zoom
        cam.center.y -= dragTranslation.height / cam.zoom
        return cam
    }

    private func clampZoom(_ z: Double) -> Double {
        min(UniverseCamera.zoomRange.upperBound, max(UniverseCamera.zoomRange.lowerBound, z))
    }

    private func navigationGesture(size: CGSize) -> some Gesture {
        let drag = DragGesture(minimumDistance: 4)
            .updating($dragTranslation) { value, state, _ in state = value.translation }
            .onEnded { value in
                flight = nil
                var end = camera
                end.center.x -= value.translation.width / camera.zoom
                end.center.y -= value.translation.height / camera.zoom
                camera = end
                // Inertia: glide toward the predicted end with the Drift spring feel.
                let extraX = (value.predictedEndTranslation.width - value.translation.width) * 0.6
                let extraY = (value.predictedEndTranslation.height - value.translation.height) * 0.6
                guard motion.animatesContinuously, hypot(extraX, extraY) > 20 else { return }
                var glide = end
                glide.center.x -= extraX / end.zoom
                glide.center.y -= extraY / end.zoom
                flight = CameraFlight(from: end, to: glide, start: .now, duration: 0.9, curve: .emerge)
            }
        let pinch = MagnifyGesture()
            .updating($pinchScale) { value, state, _ in state = value.magnification }
            .onEnded { value in
                flight = nil
                camera.zoom = clampZoom(camera.zoom * value.magnification)
            }
        return SimultaneousGesture(drag, pinch)
    }

    private func tapGesture(size: CGSize) -> some Gesture {
        SpatialTapGesture().onEnded { value in
            let cam = flight?.to ?? camera
            let shift = parallax?.offset(depth: Self.objectDepth) ?? .zero
            let location = CGPoint(x: value.location.x - shift.x, y: value.location.y - shift.y)
            if let world = UniverseRenderer.hitTestVoyage(location, scene: scene, camera: cam, size: size) {
                onWorld(world)
            } else if let hit = UniverseRenderer.hitTest(location, scene: scene, camera: cam, size: size) {
                onTap(hit)
            }
        }
    }
}

/// Every visible celestial object is an accessibility element.
private struct UniverseAccessibilityLayer: View, Equatable {
    var scene: UniverseScene
    var camera: UniverseCamera
    var size: CGSize
    var onTap: (CelestialSnapshot) -> Void
    var onWorld: (WorldState) -> Void

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.camera == b.camera && a.size == b.size && a.scene == b.scene
    }

    var body: some View {
        let cam = camera
        let visible = scene.all.filter { o in
            let p = cam.toScreen(o.position, size: size)
            return o.kind != .nebula && p.x > 0 && p.y > 0 && p.x < size.width && p.y < size.height
        }.suffix(40)
        let worlds = scene.voyages.filter { v in
            let p = cam.toScreen(v.position, size: size)
            return p.x > 0 && p.y > 0 && p.x < size.width && p.y < size.height
        }
        ZStack {
            ForEach(worlds, id: \.world.id) { v in
                Color.clear
                    .frame(width: 44, height: 44)
                    .position(cam.toScreen(v.position, size: size))
                    .accessibilityElement()
                    .accessibilityLabel(Text("\(v.world.blueprint.name), \(v.world.blueprint.archetype.displayName)"))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { onWorld(v.world) }
            }
            ForEach(Array(visible)) { o in
                Color.clear
                    .frame(width: 44, height: 44)
                    .position(cam.toScreen(o.position, size: size))
                    .accessibilityElement()
                    .accessibilityLabel(Text(CelestialDescription.spoken(o)))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { onTap(o) }
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Your universe"))
    }
}

enum CelestialDescription {
    /// "Star 111, Coding, 45 minutes, today 09:40."
    static func spoken(_ o: CelestialSnapshot) -> String {
        let when = o.bornAt.formatted(date: .abbreviated, time: .shortened)
        switch o.kind {
        case .star:
            let category = o.category?.displayName ?? ""
            return String(localized: "Star \(o.ordinal), \(category), \(o.focusedMinutes) minutes, \(when)")
        case .seed: return String(localized: "Your first star, given to you on \(when)")
        case .planet: return String(localized: "Planet \(o.name), world \(o.ordinal), born \(when)")
        case .moon: return String(localized: "Moon \(o.name), born \(when)")
        case .nebula: return String(localized: "Nebula \(o.name), painted by a week of rhythm")
        case .comet: return String(localized: "Comet marking \(o.ordinal) hours of focus")
        case .constellation: return String(localized: "Constellation \(o.name)")
        }
    }
}
