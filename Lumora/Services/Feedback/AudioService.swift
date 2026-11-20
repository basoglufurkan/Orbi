import AVFoundation
import os

/// UI cues and ambient soundscapes.
///
/// Audio session policy: never interrupt other audio. Cues alone use
/// `.ambient` (follows the silent switch, mixes with music). Ambience uses
/// `.playback` + `.mixWithOthers` so it keeps playing while the phone is
/// locked during a session, obeying only media volume. No sound ever plays
/// during focus except the chosen ambience.
@MainActor
final class AudioService {
    var cuesEnabled: () -> Bool = { true }

    private let engine = AVAudioEngine()
    private let cuePlayer = AVAudioPlayerNode()
    private var ambientNode: AVAudioSourceNode?
    private let format: AVAudioFormat
    private let synth: AmbientSynth
    private var cueCache: [SoundCue: AVAudioPCMBuffer] = [:]
    private var ambientActive = false
    private var configured = false
    private let logger = Logger(subsystem: "com.mobapptech.lumora", category: "Audio")
    private var interruptionObserver: NSObjectProtocol?

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: SoundSynth.sampleRate, channels: 2)!
        synth = AmbientSynth(sampleRate: SoundSynth.sampleRate)
    }

    // MARK: Cues

    func play(_ cue: SoundCue) {
        guard cuesEnabled() else { return }
        guard let buffer = buffer(for: cue), startEngine(forAmbient: false) else { return }
        cuePlayer.stop()
        cuePlayer.scheduleBuffer(buffer, at: nil, options: [])
        cuePlayer.play()
        scheduleIdleStop(after: Double(buffer.frameLength) / format.sampleRate + 0.5)
    }

    func stopCues() {
        cuePlayer.stop()
    }

    /// Pre-renders the heavier cue buffers on a background task so the first
    /// celebration never waits on synthesis.
    func warmUp() {
        let cues: [SoundCue] = [.celebration, .gentleCelebration, .milestone, .breakBowl, .start]
        Task.detached(priority: .utility) { [weak self] in
            for cue in cues {
                let samples = SoundSynth.render(cue)
                await self?.store(samples, for: cue)
            }
        }
    }

    private func store(_ samples: [Float], for cue: SoundCue) {
        guard cueCache[cue] == nil else { return }
        cueCache[cue] = makeBuffer(samples)
    }

    // MARK: Ambience

    func setAmbient(_ sound: AmbientSound, volume: Double) {
        synth.set(sound: sound, volume: Float(volume))
        if sound == .silence {
            ambientActive = false
            scheduleIdleStop(after: 2.5)
            return
        }
        ambientActive = true
        _ = startEngine(forAmbient: true)
    }

    func stopAmbient() {
        setAmbient(.silence, volume: 0)
    }

    // MARK: Engine

    private func configureGraph() {
        guard !configured else { return }
        configured = true
        engine.attach(cuePlayer)
        engine.connect(cuePlayer, to: engine.mainMixerNode, format: format)

        let node = Self.makeSourceNode(format: format, synth: synth)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        ambientNode = node

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                guard let self, typeValue == AVAudioSession.InterruptionType.ended.rawValue, self.ambientActive else { return }
                _ = self.startEngine(forAmbient: true)
            }
        }
    }

    /// Built outside the main actor: the render block runs on the real-time
    /// audio thread and must not inherit main-actor isolation.
    private nonisolated static func makeSourceNode(format: AVAudioFormat, synth: AmbientSynth) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let left = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let right = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
            synth.render(frames: Int(frameCount), left: left, right: right)
            return noErr
        }
    }

    private func startEngine(forAmbient: Bool) -> Bool {
        configureGraph()
        let session = AVAudioSession.sharedInstance()
        do {
            if forAmbient || ambientActive {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            } else {
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            }
            try session.setActive(true)
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            return true
        } catch {
            logger.error("Audio engine unavailable: \(error.localizedDescription)")
            return false
        }
    }

    private func scheduleIdleStop(after seconds: Double) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !self.ambientActive, !self.cuePlayer.isPlaying, self.engine.isRunning else { return }
            self.engine.pause()
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    private func buffer(for cue: SoundCue) -> AVAudioPCMBuffer? {
        if let cached = cueCache[cue] { return cached }
        let buffer = makeBuffer(SoundSynth.render(cue))
        cueCache[cue] = buffer
        return buffer
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            for ch in 0..<Int(format.channelCount) {
                channels[ch].update(from: src.baseAddress!, count: samples.count)
            }
        }
        return buffer
    }
}
