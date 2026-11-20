import CoreHaptics
import UIKit
import os

/// Haptic vocabulary (Motion & handoff · Haptics). Every call is a no-op when
/// the user disables haptics, and Core Haptics failures degrade silently to
/// UIKit generators — haptics are never load-bearing.
@MainActor
final class HapticsService {
    var isEnabled: () -> Bool = { true }

    private var engine: CHHapticEngine?
    private var celebrationPlayer: CHHapticAdvancedPatternPlayer?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let logger = Logger(subsystem: "com.mobapptech.lumora", category: "Haptics")

    // MARK: Simple moments

    func selection() {
        guard isEnabled() else { return }
        selectionGenerator.selectionChanged()
    }

    /// "Start Creating" — a gentle push off.
    func sessionStart() {
        guard isEnabled() else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
    }

    /// Final-minute whisper (opt-in).
    func finalMinuteTick() {
        guard isEnabled() else { return }
        playTransients([(0, 0.3, 0.2)]) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.3)
        }
    }

    func success() {
        guard isEnabled() else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func lightTap() {
        guard isEnabled() else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
    }

    // MARK: Celebration

    /// One pattern covering the whole completion sequence, started on the
    /// same instant as the visual clock so beats stay in sync.
    func playCelebration(milestone: Bool, reduced: Bool) {
        guard isEnabled() else { return }
        guard supportsHaptics, let engine = ensureEngine() else {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.5)
            return
        }
        do {
            let pattern = try Self.celebrationPattern(milestone: milestone, reduced: reduced)
            let player = try engine.makeAdvancedPlayer(with: pattern)
            celebrationPlayer = player
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            logger.error("Celebration haptic failed: \(error.localizedDescription)")
        }
    }

    func stopCelebration() {
        try? celebrationPlayer?.stop(atTime: CHHapticTimeImmediate)
        celebrationPlayer = nil
    }

    static func celebrationPattern(milestone: Bool, reduced: Bool) throws -> CHHapticPattern {
        var events: [CHHapticEvent] = []
        var curves: [CHHapticParameterCurve] = []

        func transient(_ t: Double, _ intensity: Float, _ sharpness: Float) {
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: t))
        }

        if reduced {
            // Reduce Motion keeps the reward: arrival + placement.
            transient(0, 0.5, 0.8)
            transient(0.8, 0.6, 0.4)
            transient(0.92, 0.5, 0.3)
            return try CHHapticPattern(events: events, parameterCurves: [])
        }

        // 01 Zero — rigid arrival.
        transient(0, 0.5, 0.8)
        // 03 Contract — continuous breath in, 0.2 → 0.6.
        events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25),
        ], relativeTime: 0.40, duration: 0.5))
        curves.append(CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
            .init(relativeTime: 0, value: 0.33), .init(relativeTime: 0.5, value: 1.0),
        ], relativeTime: 0.40))
        // 04 Light wave — release.
        transient(0.90, 1.0, 0.4)
        // 06 Gather — 8 sparkles, gaps accelerating 60 → 20 ms.
        var t = 2.30
        for i in 0..<8 {
            transient(t, 0.35 + Float(i) * 0.05, 0.7)
            t += 0.060 - Double(i) * (0.040 / 7)
        }
        // 08 Placement — success.
        transient(3.80, 0.6, 0.35)
        transient(3.93, 0.75, 0.3)

        if milestone {
            // Planet condensing: 2.4 s rumble + 5 sparkles.
            events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.45),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1),
            ], relativeTime: 4.4, duration: 2.4))
            for i in 0..<5 { transient(6.9 + Double(i) * 0.22, 0.55, 0.8) }
        }
        return try CHHapticPattern(events: events, parameterCurves: curves)
    }

    // MARK: Engine

    private func ensureEngine() -> CHHapticEngine? {
        if let engine { return engine }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = true
            engine.resetHandler = { @Sendable [weak self] in
                Task { @MainActor in try? self?.engine?.start() }
            }
            engine.stoppedHandler = { @Sendable [weak self] _ in
                Task { @MainActor in self?.celebrationPlayer = nil }
            }
            try engine.start()
            self.engine = engine
            return engine
        } catch {
            logger.error("Haptic engine unavailable: \(error.localizedDescription)")
            return nil
        }
    }

    private func playTransients(_ items: [(Double, Float, Float)], fallback: () -> Void) {
        guard supportsHaptics, let engine = ensureEngine() else { fallback(); return }
        do {
            let events = items.map { t, i, s in
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: s),
                ], relativeTime: t)
            }
            let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback()
        }
    }
}
