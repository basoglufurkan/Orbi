import CoreMotion
import Observation
import SwiftUI

/// Normalized device tilt, each axis in -1...1 (0 = resting pose).
struct ParallaxTilt: Equatable, Sendable {
    var x: Double
    var y: Double
    static let zero = ParallaxTilt(x: 0, y: 0)
}

/// Pure filtering math for gyro parallax, kept free of Core Motion so it can
/// be unit tested. Raw gravity is low-passed to remove sensor noise, measured
/// against a slowly re-centering baseline (so any comfortable holding angle
/// becomes "rest"), normalized, clamped, and followed with the Drift spring.
enum ParallaxMath {
    /// Points of travel at parallax factor 1.0 for a full tilt.
    static let maxOffset: CGFloat = 16
    /// Gravity delta (in g) that counts as a full tilt — about 20°.
    static let fullTilt = 0.35
    /// Per-sample smoothing of raw gravity at 30 Hz.
    static let noiseAlpha = 0.25
    /// Per-sample baseline re-centering at 30 Hz (time constant ≈ 5 s).
    static let baselineAlpha = 0.0067
    /// Drift spring (Motion & handoff): response 0.90, damping 1.00.
    static let springResponse = 0.90
    static let springDamping = 1.0

    static func lowPass(_ current: Double, toward sample: Double, alpha: Double) -> Double {
        current + (sample - current) * min(1, max(0, alpha))
    }

    static func clamp(_ value: Double, limit: Double = 1) -> Double {
        min(limit, max(-limit, value))
    }

    /// Normalized tilt for a smoothed gravity reading relative to the baseline.
    static func normalized(gravity: Double, baseline: Double) -> Double {
        clamp((gravity - baseline) / fullTilt)
    }

    /// One semi-implicit Euler step of a damped spring toward `target`.
    static func springStep(position: Double, velocity: Double, target: Double, dt: Double,
                           response: Double = springResponse,
                           damping: Double = springDamping) -> (position: Double, velocity: Double) {
        let omega = 2 * Double.pi / response
        let accel = omega * omega * (target - position) - 2 * damping * omega * velocity
        let v = velocity + accel * dt
        return (position + v * dt, v)
    }

    /// Screen offset for a layer at `depth` (0.2 far … 1.0 near), capped at ±maxOffset.
    /// The scene moves against the tilt, like looking through a window.
    static func offset(for tilt: ParallaxTilt, depth: CGFloat) -> CGPoint {
        CGPoint(x: -clamp(tilt.x) * maxOffset * depth, y: clamp(tilt.y) * maxOffset * depth)
    }
}

/// Drives the gyro parallax depth effect (spec: "Gyro + touch, 3 layers").
///
/// Samples device-motion gravity at 30 Hz, but only while at least one
/// consuming view is on screen *and* the policy allows it (scene active,
/// full motion — Reduce Motion, Minimal, Calm and Low Power all keep depth
/// static). Purely visual: nothing in the timer reads it.
///
/// `tilt` is deliberately not observed: views read it once per frame from
/// their own `TimelineView`, so 30 Hz updates never invalidate view bodies.
/// Only `isRunning` is observed, letting views switch between a static frame
/// and a ticking one.
@MainActor
@Observable
final class MotionParallaxService {
    private(set) var isRunning = false
    @ObservationIgnored private(set) var tilt = ParallaxTilt.zero

    /// Set by the root view from scene phase and the resolved motion level.
    var isAllowed = false {
        didSet { if isAllowed != oldValue { updateRunning() } }
    }

    @ObservationIgnored private var consumers = 0
    @ObservationIgnored private let fakeTilt: Bool
    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var filter = Filter()

    static let sampleInterval = 1.0 / 30

    init(fakeTilt: Bool = false) {
        self.fakeTilt = fakeTilt
    }

    /// Current offset for a layer at `depth`; zero when not running.
    func offset(depth: CGFloat) -> CGPoint {
        isRunning ? ParallaxMath.offset(for: tilt, depth: depth) : .zero
    }

    func retain() {
        consumers += 1
        updateRunning()
    }

    func release() {
        consumers = max(0, consumers - 1)
        updateRunning()
    }

    private var hasSource: Bool { fakeTilt || manager.isDeviceMotionAvailable }

    private func updateRunning() {
        let shouldRun = isAllowed && consumers > 0 && hasSource
        guard shouldRun != isRunning else { return }
        shouldRun ? start() : stop()
    }

    private func start() {
        filter = Filter()
        if !fakeTilt {
            manager.deviceMotionUpdateInterval = Self.sampleInterval
            manager.startDeviceMotionUpdates()
        }
        isRunning = true
        loop = Task { [weak self] in
            let start = Date.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.sampleInterval))
                guard let self else { return }
                if let g = self.sample(elapsed: Date.now.timeIntervalSince(start)) {
                    self.tilt = self.filter.step(gravityX: g.x, gravityY: g.y, dt: Self.sampleInterval)
                }
            }
        }
    }

    private func stop() {
        loop?.cancel()
        loop = nil
        if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
        tilt = .zero
        isRunning = false
    }

    private func sample(elapsed: TimeInterval) -> (x: Double, y: Double)? {
        #if DEBUG
        if fakeTilt {
            // Slow synthetic sway around an upright pose, for the simulator.
            return (0.32 * sin(elapsed * 2 * .pi / 7), -0.75 + 0.3 * sin(elapsed * 2 * .pi / 11))
        }
        #endif
        guard let g = manager.deviceMotion?.gravity else { return nil }
        return (g.x, g.y)
    }

    /// Low-pass → re-centering baseline → normalize/clamp → Drift spring.
    struct Filter {
        private var smoothed: (x: Double, y: Double)?
        private var baseline = (x: 0.0, y: 0.0)
        private var position = (x: 0.0, y: 0.0)
        private var velocity = (x: 0.0, y: 0.0)

        mutating func step(gravityX: Double, gravityY: Double, dt: Double) -> ParallaxTilt {
            guard let s = smoothed else {
                // First reading becomes the rest pose, so starting never jumps.
                smoothed = (gravityX, gravityY)
                baseline = (gravityX, gravityY)
                return .zero
            }
            let sx = ParallaxMath.lowPass(s.x, toward: gravityX, alpha: ParallaxMath.noiseAlpha)
            let sy = ParallaxMath.lowPass(s.y, toward: gravityY, alpha: ParallaxMath.noiseAlpha)
            smoothed = (sx, sy)
            baseline.x = ParallaxMath.lowPass(baseline.x, toward: sx, alpha: ParallaxMath.baselineAlpha)
            baseline.y = ParallaxMath.lowPass(baseline.y, toward: sy, alpha: ParallaxMath.baselineAlpha)
            let tx = ParallaxMath.normalized(gravity: sx, baseline: baseline.x)
            let ty = ParallaxMath.normalized(gravity: sy, baseline: baseline.y)
            let nx = ParallaxMath.springStep(position: position.x, velocity: velocity.x, target: tx, dt: dt)
            let ny = ParallaxMath.springStep(position: position.y, velocity: velocity.y, target: ty, dt: dt)
            position = (nx.position, ny.position)
            velocity = (nx.velocity, ny.velocity)
            return ParallaxTilt(x: ParallaxMath.clamp(position.x), y: ParallaxMath.clamp(position.y))
        }
    }
}

private struct MotionParallaxKey: EnvironmentKey {
    static let defaultValue: MotionParallaxService? = nil
}

extension EnvironmentValues {
    /// Gyro parallax source; nil (no parallax) in previews and off-screen renders.
    var parallax: MotionParallaxService? {
        get { self[MotionParallaxKey.self] }
        set { self[MotionParallaxKey.self] = newValue }
    }
}

/// Keeps the parallax sensor running while this view is on screen.
private struct ParallaxConsumer: ViewModifier {
    @Environment(\.parallax) private var parallax

    func body(content: Content) -> some View {
        content
            .onAppear { parallax?.retain() }
            .onDisappear { parallax?.release() }
    }
}

extension View {
    func parallaxConsumer() -> some View { modifier(ParallaxConsumer()) }
}

/// Shifts its content with the device tilt at the given depth. Static (no
/// timeline at all) whenever parallax isn't running.
struct ParallaxShift<Content: View>: View {
    var depth: CGFloat
    @ViewBuilder var content: Content
    @Environment(\.parallax) private var parallax

    var body: some View {
        Group {
            if let parallax, parallax.isRunning {
                TimelineView(.animation(minimumInterval: MotionParallaxService.sampleInterval)) { _ in
                    let shift = parallax.offset(depth: depth)
                    content.offset(x: shift.x, y: shift.y)
                }
            } else {
                content
            }
        }
        .parallaxConsumer()
    }
}
