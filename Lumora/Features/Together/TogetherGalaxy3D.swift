import RealityKit
import SwiftUI
import UIKit

/// The 3D room: a turning spiral galaxy, and in front of it one floating
/// workstation per person (a platform, a desk with a glowing laptop, and an
/// astronaut at it). Everything is built from RealityKit's primitive shapes,
/// so there are no model files. Stations grow in when someone joins and
/// shrink away when they leave.
@available(iOS 18.0, *)
struct TogetherGalaxy3D: View {
    var people: [TogetherGalaxyView.Person]
    var category: FocusCategory
    var animates: Bool

    @State private var scene = TogetherGalaxyScene()

    var body: some View {
        GeometryReader { proxy in
            let aspect = Float(proxy.size.width / max(1, proxy.size.height))
            RealityView { content in
                content.camera = .virtual
                scene.build(in: content, category: category)
                scene.frame(aspect: aspect)
                scene.sync(people, animates: animates)
            } update: { _ in
                scene.frame(aspect: aspect)
                scene.sync(people, animates: animates)
            }
        }
        .onDisappear { scene.stop() }
    }
}

@available(iOS 18.0, *)
@MainActor
final class TogetherGalaxyScene {
    private let root = Entity()
    private let galaxy = Entity()
    private let camera = PerspectiveCamera()
    private var aspect: Float = 0
    private var stations: [Int: Entity] = [:]
    private var people: [TogetherGalaxyView.Person] = []
    private var updates: EventSubscription?
    private var time: Double = 0
    private var animates = true

    // MARK: Building

    func build(in content: RealityViewCameraContent, category: FocusCategory) {
        guard updates == nil else { return }
        content.add(root)

        camera.camera.fieldOfViewInDegrees = Self.fieldOfView
        root.addChild(camera)
        aspect = 1
        aim(halfWidth: 1, animated: false)

        let sun = DirectionalLight()
        sun.light.intensity = 3200
        sun.light.color = UIColor(white: 0.96, alpha: 1)
        sun.look(at: .zero, from: [0.8, 2.4, 2.2], relativeTo: nil)
        root.addChild(sun)

        let core = PointLight()
        core.light.color = UIColor(Color(hex: Palette.warmGold))
        core.light.intensity = 9000
        core.light.attenuationRadius = 4
        core.position = [0, 0.5, -1.2]
        root.addChild(core)

        buildGalaxy(category: category)
        root.addChild(galaxy)

        updates = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            let dt = event.deltaTime
            MainActor.assumeIsolated { self?.tick(dt) }
        }
    }

    private static let fieldOfView: Float = 40

    func frame(aspect: Float) {
        guard abs(aspect - self.aspect) > 0.01 else { return }
        self.aspect = aspect
        layOut(animated: false)
    }

    /// Brings the camera in until the widest row of desks just fits.
    private func aim(halfWidth: Double, animated: Bool) {
        let tanHalf = tan(Self.fieldOfView / 2 * .pi / 180)
        // Never so close that the front row's names leave the bottom of the view.
        let distance = max(2.9, Float(halfWidth) / (tanHalf * max(0.3, aspect)))
        let probe = Entity()
        probe.look(at: [0, -0.12, 0.1], from: [0, distance * 0.36, distance * 0.93], relativeTo: nil)
        let eye = probe.transform
        if animated {
            camera.move(to: eye, relativeTo: root, duration: 0.9, timingFunction: .easeInOut)
        } else {
            camera.transform = eye
        }
    }

    private func buildGalaxy(category: FocusCategory) {
        galaxy.position = [0, 0.42, -1.7]
        // Tipped back, like a disc seen from slightly above.
        galaxy.orientation = simd_quatf(angle: 0.42, axis: [1, 0, 0])

        let palette: [UInt32] = [Palette.softWhite, Palette.cosmicViolet, Palette.nebulaPink, Palette.warmGold,
                                 category.hex]
        var rng = SeededRandom(seed: 11)
        var buckets = Array(repeating: [SIMD3<Float>](), count: palette.count)
        var sizes = Array(repeating: [Float](), count: palette.count)
        for i in 0..<1400 {
            let arm = Double(i % 3) * 2 * .pi / 3
            let d = pow(rng.unit(), 0.65)
            let angle = arm + d * 4.6 + rng.range(-0.32, 0.32)
            let r = 0.1 + d * 1.45
            let y = rng.range(-0.04, 0.04) * (1.2 - d)
            let bucket = i % palette.count
            buckets[bucket].append([Float(cos(angle) * r), Float(y), Float(sin(angle) * r)])
            sizes[bucket].append(Float(rng.range(0.004, 0.009) * (d < 0.2 ? 1.5 : 1)))
        }
        for (i, hex) in palette.enumerated() {
            guard let mesh = Self.starMesh(buckets[i], sizes: sizes[i]) else { continue }
            var material = UnlitMaterial(color: UIColor(Color(hex: hex)))
            material.faceCulling = .none
            galaxy.addChild(ModelEntity(mesh: mesh, materials: [material]))
        }

        // A bright core in soft layers of light.
        let core = ModelEntity(mesh: .generateSphere(radius: 0.07), materials: [UnlitMaterial(color: UIColor(Color(hex: 0xFFF3D6)))])
        galaxy.addChild(core)
        for (radius, opacity) in [(0.13, 0.3), (0.24, 0.1)] as [(Float, Float)] {
            var halo = UnlitMaterial(color: UIColor(Color(hex: Palette.warmGold)))
            halo.blending = .transparent(opacity: .init(floatLiteral: opacity))
            halo.faceCulling = .none
            let glow = ModelEntity(mesh: .generateSphere(radius: radius), materials: [halo])
            glow.scale = [1, 0.45, 1]
            galaxy.addChild(glow)
        }
    }

    /// Many tiny octahedra in one mesh: cheap, and they read as points from any side.
    private static func starMesh(_ centers: [SIMD3<Float>], sizes: [Float]) -> MeshResource? {
        guard !centers.isEmpty else { return nil }
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(centers.count * 6)
        indices.reserveCapacity(centers.count * 24)
        let faces: [(UInt32, UInt32, UInt32)] = [(0, 2, 4), (2, 1, 4), (1, 3, 4), (3, 0, 4),
                                                 (2, 0, 5), (1, 2, 5), (3, 1, 5), (0, 3, 5)]
        for (c, s) in zip(centers, sizes) {
            let base = UInt32(positions.count)
            positions += [c + [s, 0, 0], c - [s, 0, 0], c + [0, 0, s], c - [0, 0, s], c + [0, s, 0], c - [0, s, 0]]
            for (a, b, d) in faces { indices += [base + a, base + b, base + d] }
        }
        var descriptor = MeshDescriptor(name: "stars")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    // MARK: People

    func sync(_ people: [TogetherGalaxyView.Person], animates: Bool) {
        self.animates = animates
        guard people != self.people || stations.count != people.count else { return }
        self.people = people
        let ids = Set(people.map(\.id))
        // Leavers shrink away, then go.
        for (id, station) in stations where !ids.contains(id) {
            stations[id] = nil
            var gone = station.transform
            gone.scale = [0.01, 0.01, 0.01]
            gone.translation.y += 0.35
            station.move(to: gone, relativeTo: station.parent, duration: 0.7, timingFunction: .easeIn)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.75))
                station.removeFromParent()
            }
        }
        layOut(animated: true)
    }

    private func layOut(animated: Bool) {
        let seats = TogetherGalaxyLayout.seats(count: people.count,
                                               perRow: TogetherGalaxyLayout.perRow(aspect: Double(aspect)))
        aim(halfWidth: TogetherGalaxyLayout.halfWidth(seats), animated: animated)
        for (person, seat) in zip(people, seats) {
            let target = Transform(scale: .init(repeating: seat.row == 1 ? 0.92 : 1),
                                   rotation: simd_quatf(angle: Float(-seat.x) * 0.22, axis: [0, 1, 0]),
                                   translation: Self.position(of: seat))
            if let station = stations[person.id] {
                if animated {
                    station.move(to: target, relativeTo: root, duration: 0.8, timingFunction: .easeInOut)
                } else {
                    station.transform = target
                }
            } else {
                let station = Self.station(for: person)
                var start = target
                start.scale = [0.01, 0.01, 0.01]
                start.translation.y -= 0.3
                station.transform = start
                root.addChild(station)
                station.move(to: target, relativeTo: root, duration: 0.9, timingFunction: .easeOut)
                stations[person.id] = station
            }
        }
    }

    private static func position(of seat: TogetherGalaxyLayout.Seat) -> SIMD3<Float> {
        let x = Float(seat.x)
        return seat.row == 0 ? [x, -0.36, 0.55] : [x, 0.06, -0.6]
    }

    func stop() {
        updates?.cancel()
        updates = nil
    }

    private func tick(_ dt: TimeInterval) {
        guard animates else { return }
        time += dt
        // Turns about its own axis, so the tilt stays put.
        galaxy.orientation = galaxy.orientation * simd_quatf(angle: Float(dt) * 0.05, axis: [0, 1, 0])
        // Each astronaut floats a little, out of step with the others.
        for (id, station) in stations {
            guard let body = station.findEntity(named: "astronaut") else { continue }
            body.position.y = Float(sin(time * 0.9 + Double(id) * 1.7)) * 0.012
            if let helmet = body.findEntity(named: "helmet") {
                helmet.orientation = simd_quatf(angle: Float(sin(time * 0.6 + Double(id))) * 0.08, axis: [0, 0, 1])
            }
        }
    }

    // MARK: A workstation

    private static func station(for person: TogetherGalaxyView.Person) -> Entity {
        let station = Entity()
        station.name = "station-\(person.id)"
        let accent = UIColor(Color(hex: person.hex))
        let white = SimpleMaterial(color: UIColor(white: 0.95, alpha: 1), roughness: 0.45, isMetallic: false)
        let suitTrim = SimpleMaterial(color: accent, roughness: 0.4, isMetallic: false)
        let glass = SimpleMaterial(color: UIColor(Color(hex: Palette.midnightIndigo)), roughness: 0.18, isMetallic: true)
        let glow = UnlitMaterial(color: accent)

        func add(_ mesh: MeshResource, _ material: any RealityKit.Material, at p: SIMD3<Float>,
                 to parent: Entity, name: String? = nil, rotation: simd_quatf? = nil, scale: SIMD3<Float>? = nil) {
            let e = ModelEntity(mesh: mesh, materials: [material])
            e.position = p
            if let rotation { e.orientation = rotation }
            if let scale { e.scale = scale }
            if let name { e.name = name }
            parent.addChild(e)
        }

        // Floating platform with a lit rim.
        add(.generateCylinder(height: 0.025, radius: 0.27), glass, at: [0, 0, 0], to: station)
        add(.generateCylinder(height: 0.01, radius: 0.275), glow, at: [0, -0.012, 0], to: station)
        if person.isMe {
            var ring = UnlitMaterial(color: UIColor(Color(hex: Palette.warmGold)))
            ring.blending = .transparent(opacity: .init(floatLiteral: 0.35))
            add(.generateCylinder(height: 0.004, radius: 0.34), ring, at: [0, -0.016, 0], to: station)
        }

        // Desk with a laptop whose back glows in the person's colour.
        add(.generateBox(size: [0.42, 0.018, 0.17], cornerRadius: 0.008), glass, at: [0, 0.2, 0.09], to: station)
        add(.generateBox(size: [0.42, 0.006, 0.17], cornerRadius: 0.003), glow, at: [0, 0.19, 0.09], to: station,
            scale: [1.01, 1, 1.02])
        for x in [-0.18, 0.18] as [Float] {
            add(.generateBox(size: [0.016, 0.19, 0.12]), glass, at: [x, 0.1, 0.09], to: station)
        }
        add(.generateBox(size: [0.15, 0.008, 0.1], cornerRadius: 0.003), glass, at: [0, 0.213, 0.07], to: station)
        add(.generateBox(size: [0.15, 0.1, 0.006], cornerRadius: 0.004), glow, at: [0, 0.265, 0.115], to: station,
            rotation: simd_quatf(angle: -0.22, axis: [1, 0, 0]))
        add(.generateSphere(radius: 0.012), UnlitMaterial(color: .white), at: [0, 0.27, 0.12], to: station)

        // Chair.
        add(.generateBox(size: [0.16, 0.025, 0.13], cornerRadius: 0.01), glass, at: [0, 0.12, -0.07], to: station)
        add(.generateCylinder(height: 0.11, radius: 0.012), glass, at: [0, 0.06, -0.07], to: station)

        // The astronaut, seated, facing the desk (and us).
        let astronaut = Entity()
        astronaut.name = "astronaut"
        station.addChild(astronaut)
        add(.generateBox(size: [0.16, 0.17, 0.12], cornerRadius: 0.05), white, at: [0, 0.22, -0.075], to: astronaut)
        add(.generateBox(size: [0.165, 0.025, 0.125], cornerRadius: 0.01), suitTrim, at: [0, 0.2, -0.075], to: astronaut)
        add(.generateBox(size: [0.13, 0.15, 0.06], cornerRadius: 0.025), white, at: [0, 0.24, -0.16], to: astronaut)
        // Thighs on the chair, shins down.
        for x in [-0.045, 0.045] as [Float] {
            add(.generateBox(size: [0.06, 0.05, 0.13], cornerRadius: 0.025), white, at: [x, 0.15, -0.01], to: astronaut)
            add(.generateBox(size: [0.055, 0.12, 0.055], cornerRadius: 0.025), white, at: [x, 0.08, 0.05], to: astronaut)
        }
        // Arms reaching to the laptop.
        for x in [-0.1, 0.1] as [Float] {
            add(.generateBox(size: [0.045, 0.045, 0.15], cornerRadius: 0.022), white, at: [x, 0.235, 0.0], to: astronaut,
                rotation: simd_quatf(angle: 0.25, axis: [1, 0, 0]))
            add(.generateSphere(radius: 0.026), suitTrim, at: [x * 0.8, 0.22, 0.07], to: astronaut)
        }
        let helmet = Entity()
        helmet.name = "helmet"
        helmet.position = [0, 0.37, -0.07]
        astronaut.addChild(helmet)
        add(.generateSphere(radius: 0.09), white, at: .zero, to: helmet)
        var visor = PhysicallyBasedMaterial()
        visor.baseColor = .init(tint: UIColor(Color(hex: 0x10122A)))
        visor.metallic = 0.9
        visor.roughness = 0.08
        visor.emissiveColor = .init(color: accent)
        visor.emissiveIntensity = 0.35
        add(.generateSphere(radius: 0.07), visor, at: [0, 0.006, 0.032], to: helmet, scale: [1.0, 0.86, 0.8])
        add(.generateCylinder(height: 0.05, radius: 0.004), white, at: [0.05, 0.1, -0.01], to: helmet)
        add(.generateSphere(radius: 0.012), glow, at: [0.05, 0.128, -0.01], to: helmet)

        // Name, under the platform, facing the camera.
        let label = person.isMe ? String(localized: "You") : person.name
        let text = MeshResource.generateText(label, extrusionDepth: 0.002,
                                             font: .systemFont(ofSize: 0.075, weight: .semibold),
                                             containerFrame: .zero, alignment: .center, lineBreakMode: .byTruncatingTail)
        let color = person.isMe ? UIColor(Color(hex: Palette.warmGold)) : UIColor(white: 0.96, alpha: 1)
        let name = ModelEntity(mesh: text, materials: [UnlitMaterial(color: color)])
        let width = text.bounds.extents.x
        name.position = [-width / 2 - text.bounds.min.x, -0.13, 0.26]
        name.orientation = simd_quatf(angle: -0.32, axis: [1, 0, 0])
        station.addChild(name)
        return station
    }
}
