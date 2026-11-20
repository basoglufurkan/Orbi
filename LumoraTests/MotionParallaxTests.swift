import CoreGraphics
import Testing
@testable import Lumora

@Suite("Gyro parallax math")
@MainActor
struct MotionParallaxTests {
    @Test func lowPassMovesPartwayAndClampsAlpha() {
        #expect(ParallaxMath.lowPass(0, toward: 1, alpha: 0.25) == 0.25)
        #expect(ParallaxMath.lowPass(0.5, toward: 0.5, alpha: 0.25) == 0.5)
        #expect(ParallaxMath.lowPass(0, toward: 1, alpha: 3) == 1)
        #expect(ParallaxMath.lowPass(0, toward: 1, alpha: -1) == 0)
    }

    @Test func normalizedTiltIsClamped() {
        #expect(ParallaxMath.normalized(gravity: 0, baseline: 0) == 0)
        #expect(abs(ParallaxMath.normalized(gravity: ParallaxMath.fullTilt / 2, baseline: 0) - 0.5) < 1e-9)
        #expect(ParallaxMath.normalized(gravity: 0.9, baseline: 0) == 1)
        #expect(ParallaxMath.normalized(gravity: -1, baseline: 0.2) == -1)
    }

    @Test func offsetScalesWithDepthAndNeverExceedsCap() {
        let full = ParallaxTilt(x: 1, y: -1)
        let near = ParallaxMath.offset(for: full, depth: 1)
        let far = ParallaxMath.offset(for: full, depth: 0.2)
        #expect(abs(near.x) == ParallaxMath.maxOffset)
        #expect(abs(near.y) == ParallaxMath.maxOffset)
        #expect(abs(far.x - near.x * 0.2) < 1e-9)
        // Out-of-range tilt is clamped to the cap.
        let wild = ParallaxMath.offset(for: ParallaxTilt(x: 5, y: -7), depth: 1)
        #expect(wild == near)
        #expect(ParallaxMath.offset(for: .zero, depth: 1) == .zero)
        #expect((12...20).contains(ParallaxMath.maxOffset))
    }

    @Test func driftSpringSettlesWithoutOvershoot() {
        var state = (position: 0.0, velocity: 0.0)
        var peak = 0.0
        for _ in 0..<90 { // 3 s at 30 Hz
            state = ParallaxMath.springStep(position: state.position, velocity: state.velocity, target: 1, dt: 1.0 / 30)
            peak = max(peak, state.position)
        }
        #expect(abs(state.position - 1) < 0.01)
        #expect(peak <= 1.001)
    }

    @Test func filterStartsAtRestFollowsTiltAndRecenters() {
        var filter = MotionParallaxService.Filter()
        let dt = 1.0 / 30
        // First reading is the rest pose, whatever the holding angle.
        #expect(filter.step(gravityX: 0.1, gravityY: -0.8, dt: dt) == .zero)
        // A sustained tilt to the right is followed within a second or so.
        var tilt = ParallaxTilt.zero
        for _ in 0..<45 { tilt = filter.step(gravityX: 0.1 + 0.2, gravityY: -0.8, dt: dt) }
        #expect(tilt.x > 0.3)
        #expect(abs(tilt.y) < 0.01)
        // Holding the new pose, the baseline drifts until it reads as rest.
        for _ in 0..<(30 * 40) { tilt = filter.step(gravityX: 0.3, gravityY: -0.8, dt: dt) }
        #expect(abs(tilt.x) < 0.05)
        // Extreme readings stay within -1...1.
        for _ in 0..<60 { tilt = filter.step(gravityX: -5, gravityY: 5, dt: dt) }
        #expect((-1...1).contains(tilt.x) && (-1...1).contains(tilt.y))
    }

    @Test func serviceStaysStillWhenNotAllowed() {
        let service = MotionParallaxService(fakeTilt: true)
        service.retain()
        #expect(!service.isRunning)
        #expect(service.offset(depth: 1) == .zero)
        service.isAllowed = true
        #expect(service.isRunning)
        service.isAllowed = false // e.g. Reduce Motion turned on
        #expect(!service.isRunning)
        #expect(service.offset(depth: 1) == .zero)
        service.isAllowed = true
        service.release()
        #expect(!service.isRunning)
    }
}
