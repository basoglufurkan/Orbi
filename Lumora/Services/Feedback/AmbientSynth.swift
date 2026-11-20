import Foundation
import os

/// Real-time generator for ambient soundscapes, rendered inside an
/// `AVAudioSourceNode`. Parameters are exchanged through a lock the render
/// thread only *tries* to take, so the audio thread never blocks.
final class AmbientSynth: @unchecked Sendable {
    struct Parameters: Sendable {
        var sound: AmbientSound = .silence
        var volume: Float = 0.6
    }

    private let shared = OSAllocatedUnfairLock(initialState: Parameters())

    // Render-thread state (only touched inside `render`).
    private var current: AmbientSound = .silence
    private var gain: Float = 0
    private var rng = SeededRandom(seed: 0xA4B1_E47)
    private var brown: Double = 0
    private var lowpass: Double = 0
    private var highpassPrev: Double = 0
    private var highpassOut: Double = 0
    private var phase: Double = 0
    private var phase2: Double = 0
    private var lfo: Double = 0
    private var dropEnv: Double = 0
    private var dropFreq: Double = 2000
    private var dropPhase: Double = 0
    private var bandpass: Double = 0
    private var bandpass2: Double = 0
    private var crackleEnv: Double = 0
    private var cachedParams = Parameters()

    let sampleRate: Double

    init(sampleRate: Double) { self.sampleRate = sampleRate }

    func set(sound: AmbientSound, volume: Float) {
        shared.withLock { $0 = Parameters(sound: sound, volume: max(0, min(1, volume))) }
    }

    var isSilent: Bool { shared.withLock { $0.sound == .silence } }

    /// Fills `frames` stereo-interleaved-agnostic samples into `left`/`right`.
    func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?) {
        if let p = shared.withLockIfAvailable({ $0 }) { cachedParams = p }
        let target = cachedParams
        // 2 s crossfade: fade out the old sound, swap, fade the new one in.
        let fadeStep = Float(1.0 / (sampleRate * 1.0))

        for i in 0..<frames {
            let wanted: Float = target.sound == current ? target.volume : 0
            if gain < wanted { gain = min(wanted, gain + fadeStep) } else if gain > wanted { gain = max(wanted, gain - fadeStep) }
            if gain == 0, target.sound != current { current = target.sound }

            let sample = gain > 0 ? Float(nextSample(current)) * gain : 0
            left[i] = sample
            right?[i] = sample
        }
    }

    private func white() -> Double { rng.unit() * 2 - 1 }

    private func nextSample(_ sound: AmbientSound) -> Double {
        switch sound {
        case .silence:
            return 0
        case .brownNoise:
            brown = (brown + white() * 0.02) * 0.998
            return brown * 3.2
        case .deepSpace:
            // 45 Hz bed + octave, slow breathing, a little air.
            phase += 45 / sampleRate
            phase2 += 90.5 / sampleRate
            lfo += 0.07 / sampleRate
            if phase > 1 { phase -= 1 }
            if phase2 > 1 { phase2 -= 1 }
            if lfo > 1 { lfo -= 1 }
            brown = (brown + white() * 0.02) * 0.998
            lowpass += (brown - lowpass) * 0.02
            let breath = 0.75 + 0.25 * sin(2 * .pi * lfo)
            return (sin(2 * .pi * phase) * 0.5 + sin(2 * .pi * phase2) * 0.18) * breath * 0.6 + lowpass * 1.4
        case .tides:
            lfo += 0.09 / sampleRate
            if lfo > 1 { lfo -= 1 }
            brown = (brown + white() * 0.02) * 0.998
            lowpass += (brown * 3 - lowpass) * 0.08
            let swell = pow(0.5 + 0.5 * sin(2 * .pi * lfo), 2)
            return lowpass * (0.25 + 0.75 * swell)
        case .rain:
            // High-passed noise "hiss" plus sparse glassy droplets.
            let w = white()
            highpassOut = 0.97 * (highpassOut + w - highpassPrev)
            highpassPrev = w
            if dropEnv < 0.001, rng.unit() < 9 / sampleRate {
                dropEnv = 0.25 + rng.unit() * 0.35
                dropFreq = 1800 + rng.unit() * 2600
                dropPhase = 0
            }
            dropPhase += dropFreq / sampleRate
            if dropPhase > 1 { dropPhase -= 1 }
            let drop = sin(2 * .pi * dropPhase) * dropEnv
            dropEnv *= 0.9985
            return highpassOut * 0.16 + drop * 0.22
        case .solarWind:
            // Band-passed noise whose centre drifts slowly, like gusts in a void.
            lfo += 0.05 / sampleRate
            if lfo > 1 { lfo -= 1 }
            let sweep = 0.5 + 0.5 * sin(2 * .pi * lfo)
            let cutoff = 0.004 + 0.03 * sweep * sweep
            let w = white()
            bandpass += (w - bandpass) * cutoff
            bandpass2 += (bandpass - bandpass2) * cutoff
            return (bandpass - bandpass2) * (2.2 + 3 * (1 - sweep)) + bandpass2 * 1.4
        case .campfire:
            // A warm low rumble with sparse, sharp crackles.
            brown = (brown + white() * 0.02) * 0.998
            lowpass += (brown - lowpass) * 0.05
            if crackleEnv < 0.001, rng.unit() < 14 / sampleRate {
                crackleEnv = 0.3 + rng.unit() * 0.7
            }
            let crackle = white() * crackleEnv
            crackleEnv *= 0.992
            return lowpass * 1.8 + crackle * 0.35
        }
    }
}
