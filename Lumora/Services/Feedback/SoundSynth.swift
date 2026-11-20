import Foundation

/// Offline synthesis of Lumora's "Glass & Breath" cues. Everything is tuned
/// to D major pentatonic so cues harmonise with any ambience. Rendering a cue
/// takes a few milliseconds and the result is cached by `AudioService`.
enum SoundCue: String, CaseIterable, Sendable {
    /// Full 5.6 s completion soundtrack: bloom chord, whoosh, 3-note chime.
    case celebration
    /// Milestone: celebration plus 5-note motif and low pad.
    case milestone
    /// Ended-early variant: a softer chord.
    case gentleCelebration
    /// Reduce Motion: the same chime, compressed into 1.2 s.
    case quickCelebration
    case breakBowl
    case tick
    case start
}

enum SoundSynth {
    static let sampleRate = 44_100.0

    static func render(_ cue: SoundCue) -> [Float] {
        switch cue {
        case .celebration:
            var buf = silence(5.8)
            mix(bloomChord(), into: &buf, at: 0.90)
            mix(whoosh(duration: 0.9), into: &buf, at: 2.80, gain: 0.45)
            mix(chime(), into: &buf, at: 3.80)
            return normalize(buf, peak: 0.55)
        case .gentleCelebration:
            var buf = silence(5.0)
            mix(bloomChord(), into: &buf, at: 0.90, gain: 0.6)
            mix(chime(), into: &buf, at: 3.80, gain: 0.6)
            return normalize(buf, peak: 0.38)
        case .quickCelebration:
            var buf = silence(3.2)
            mix(bloomChord(), into: &buf, at: 0, gain: 0.5)
            mix(chime(), into: &buf, at: 0.4)
            return normalize(buf, peak: 0.45)
        case .milestone:
            var buf = silence(9.5)
            mix(bloomChord(), into: &buf, at: 0.90)
            mix(whoosh(duration: 0.9), into: &buf, at: 2.80, gain: 0.45)
            mix(pad(duration: 5.5), into: &buf, at: 3.6, gain: 0.5)
            let motif: [Double] = [587.33, 659.25, 739.99, 880.00, 1174.66]
            for (i, f) in motif.enumerated() {
                mix(glass(freq: f, duration: 2.2, amplitude: 0.5), into: &buf, at: 4.6 + Double(i) * 0.42)
            }
            return normalize(buf, peak: 0.6)
        case .breakBowl:
            return normalize(bowl(), peak: 0.45)
        case .tick:
            return normalize(glass(freq: 1174.66, duration: 0.25, amplitude: 0.3), peak: 0.18)
        case .start:
            var buf = silence(1.6)
            mix(glass(freq: 587.33, duration: 1.4, amplitude: 0.5), into: &buf, at: 0)
            mix(glass(freq: 880.0, duration: 1.2, amplitude: 0.35), into: &buf, at: 0.09)
            return normalize(buf, peak: 0.32)
        }
    }

    // MARK: Voices

    /// Rising D–F♯–A bloom with a long, airy tail.
    static func bloomChord() -> [Float] {
        var buf = silence(3.4)
        for (i, f) in [293.66, 369.99, 440.0].enumerated() {
            mix(glass(freq: f, duration: 3.0, amplitude: 0.55), into: &buf, at: Double(i) * 0.12)
        }
        mix(glass(freq: 1174.66, duration: 2.0, amplitude: 0.12), into: &buf, at: 0.3)
        return buf
    }

    /// 3-note placement chime; the third note lands with the success haptic.
    static func chime() -> [Float] {
        var buf = silence(1.8)
        for (i, f) in [587.33, 739.99, 880.0].enumerated() {
            mix(glass(freq: f, duration: 1.4, amplitude: 0.42), into: &buf, at: Double(i) * 0.06)
        }
        return buf
    }

    /// Bowed-glass tone: inharmonic partials with soft attack and exponential decay.
    static func glass(freq: Double, duration: Double, amplitude: Double) -> [Float] {
        let n = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: n)
        let partials: [(ratio: Double, amp: Double, decay: Double)] = [(1, 1, 1), (2.01, 0.32, 1.8), (3.02, 0.12, 2.6), (4.2, 0.05, 3.4)]
        let attack = 0.012
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let env = min(1, t / attack) * exp(-t * 2.2 / duration * 2.2)
            var v = 0.0
            for p in partials {
                v += p.amp * sin(2 * .pi * freq * p.ratio * t) * exp(-t * p.decay / duration * 2)
            }
            out[i] = Float(v * env * amplitude)
        }
        return out
    }

    /// Low choir-like pad (detuned saws, filtered).
    static func pad(duration: Double) -> [Float] {
        let n = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: n)
        var lp = 0.0
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let env = min(1, t / 1.2) * min(1, (duration - t) / 1.5)
            var v = 0.0
            for f in [146.83, 147.6, 220.0, 219.2] {
                let phase = (t * f).truncatingRemainder(dividingBy: 1)
                v += (phase * 2 - 1) * 0.25
            }
            lp += (v - lp) * 0.035
            out[i] = Float(lp * env)
        }
        return out
    }

    /// Filtered noise sweep for the camera travel.
    static func whoosh(duration: Double) -> [Float] {
        let n = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: n)
        var rng = SeededRandom(seed: 0x0005_1005)
        var lp = 0.0
        for i in 0..<n {
            let x = Double(i) / Double(n)
            let cutoff = 0.01 + 0.12 * sin(.pi * x)
            let white = rng.unit() * 2 - 1
            lp += (white - lp) * cutoff
            let env = sin(.pi * x)
            out[i] = Float(lp * env * 1.6)
        }
        return out
    }

    /// Singing bowl for the start of a break.
    static func bowl() -> [Float] {
        let duration = 4.5
        let n = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: n)
        let base = 293.66
        let partials: [(Double, Double)] = [(1, 1), (2.71, 0.45), (5.15, 0.2), (8.4, 0.08)]
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let beat = 1 + 0.15 * sin(2 * .pi * 3.2 * t)
            var v = 0.0
            for (r, a) in partials { v += a * sin(2 * .pi * base * r * t) * exp(-t * r * 0.35) }
            out[i] = Float(v * min(1, t / 0.008) * beat * 0.5)
        }
        return out
    }

    // MARK: Buffer helpers

    static func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * sampleRate))
    }

    static func mix(_ source: [Float], into dest: inout [Float], at seconds: Double, gain: Float = 1) {
        let offset = Int(seconds * sampleRate)
        guard offset < dest.count else { return }
        let count = min(source.count, dest.count - offset)
        for i in 0..<count { dest[offset + i] += source[i] * gain }
    }

    static func normalize(_ buf: [Float], peak: Float) -> [Float] {
        let maxAbs = buf.reduce(Float(0)) { max($0, abs($1)) }
        guard maxAbs > 0 else { return buf }
        let g = peak / maxAbs
        return buf.map { $0 * g }
    }
}
