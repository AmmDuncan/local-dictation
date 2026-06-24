@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import LocalDictationCore

enum AudioRecordingError: Error, CustomStringConvertible {
    case permissionDenied
    case couldNotStart
    case notRecording

    var description: String {
        switch self {
        case .permissionDenied:
            "Microphone permission was denied."
        case .couldNotStart:
            "Audio recording could not start."
        case .notRecording:
            "No active recording was found."
        }
    }
}

/// Hands a single audio buffer to `AVAudioConverter`'s pull-based input block
/// exactly once, then reports no more data.
private final class SingleBufferSource: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}

/// Captures microphone audio into an in-memory 16 kHz mono buffer so it can be
/// snapshotted for live preview mid-recording, then written to a WAV on stop.
final class AudioFileRecorder: NSObject, AudioRecording, @unchecked Sendable {
    // Recreated per recording (see startRecording) so it always binds to the
    // CURRENT default input. A long-lived engine goes stale across audio-route
    // changes (plugging in headphones) and its tap then captures silence.
    private var engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!
    /// Keep capturing this long after a stop request so the last in-flight tap
    /// buffer — usually the trailing syllable of the final word — flushes before
    /// teardown. Small enough to stay within the push-to-talk latency budget.
    private static let trailingCaptureMillis = 250
    /// Cap on how long `startRecording` waits for the mic to begin delivering
    /// audio before proceeding anyway, so a silent/broken input never hangs the
    /// start. Cold first-of-day warmup is normally well under this.
    private static let firstAudioTimeoutMillis = 1500
    private var converter: AVAudioConverter?
    /// The system default input device we temporarily overrode for the current
    /// recording (to bind a preferred non-default mic), restored on stop. nil
    /// when we left the OS default untouched.
    private var savedDefaultInputID: AudioDeviceID?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var _isCapturing = false
    private var _currentLevel: Double = 0
    private var _lastSpeechAt: Date?
    /// Normalized mic level (0…1, RMS→dBFS) above which a buffer counts as speech
    /// rather than ambient/breath — sits clearly above a quiet room (~0.2) and
    /// below normal speech (~0.5+). The live preview gates on recent speech so a
    /// silent hold doesn't cycle through whisper's phantom transcriptions.
    private static let speechLevelThreshold = 0.3
    /// Set true (under `lock`) once the tap delivers its first buffer after a
    /// start. Lets `startRecording` hold "ready" until the mic is actually live.
    private var _sawFirstAudio = false
    private var firstAudioWaiter: CheckedContinuation<Void, Never>?

    /// Most recent normalized mic level (0…1), updated on the audio thread.
    var currentLevel: Double {
        lock.lock(); defer { lock.unlock() }
        return _currentLevel
    }

    /// True if speech-level audio arrived within `window` seconds. The preview
    /// loop gates on this so a silent hold freezes the last preview instead of
    /// cycling through whisper's hallucinated phrases on near-silence.
    func hadSpeechRecently(within window: TimeInterval = 1.0) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let last = _lastSpeechAt else { return false }
        return Date().timeIntervalSince(last) <= window
    }

    private var isCapturing: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isCapturing
    }

    private func setCapturing(_ value: Bool) {
        lock.lock(); _isCapturing = value; lock.unlock()
    }

    deinit {
        // Safety net: a recording torn down without a normal stop (cancel races,
        // app quit) must not leave the user's input device switched.
        restorePreferredInputDefault()
    }

    /// When an explicitly chosen input device isn't the current OS default, make
    /// it the system default for this recording. The engine reliably captures
    /// only its own default input, so this is how we bind a non-default mic;
    /// restored by `restorePreferredInputDefault` on stop. No-op for "System
    /// Default" (we follow the OS default) or when it's already the default.
    private func applyPreferredInputDefault(forUID uid: String) {
        guard let target = AudioDevices.resolveInputDeviceID(forUID: uid),
              let current = AudioDevices.defaultInputDeviceID(),
              target != current else {
            savedDefaultInputID = nil
            return
        }
        savedDefaultInputID = AudioDevices.setDefaultInputDeviceID(target) ? current : nil
    }

    /// Restore the system default input changed by `applyPreferredInputDefault`.
    /// Idempotent — safe to call from every teardown path.
    private func restorePreferredInputDefault() {
        guard let saved = savedDefaultInputID else { return }
        savedDefaultInputID = nil
        AudioDevices.setDefaultInputDeviceID(saved)
    }

    func startRecording() async throws {
        // Permission is requested once, up front, in AppModel.beginHold. Here we
        // only verify it (non-prompting) so a second system dialog never appears.
        guard PermissionStatus.isMicrophoneAuthorized else {
            throw AudioRecordingError.permissionDenied
        }

        clearSamples()
        resetFirstAudioState()

        // Bind an explicitly chosen input device by making it the system default
        // for this recording (restored on stop). The engine reliably captures
        // only its own *default* input, so forcing a device via the audio unit's
        // CurrentDevice override silently delivers no audio. "System Default"
        // changes nothing — we record from the live OS default as-is.
        let deviceUID = AppSettingsSnapshot.current.inputDeviceUID
        applyPreferredInputDefault(forUID: deviceUID)

        // Fresh engine each time so it binds to the (now-preferred) default input
        // and follows route changes (e.g. headphones plugged in since last use).
        engine = AVAudioEngine()
        let input = engine.inputNode

        // Right after a device switch (an explicit non-default pick) the node's
        // format can read momentarily invalid (0 Hz) while the route engages.
        // Re-read briefly before giving up so the recording still starts cleanly.
        var inputFormat = input.inputFormat(forBus: 0)
        var settleTries = 0
        while inputFormat.sampleRate <= 0 || inputFormat.channelCount == 0, settleTries < 15 {
            try await Task.sleep(nanoseconds: 20_000_000)  // up to ~300ms
            inputFormat = input.inputFormat(forBus: 0)
            settleTries += 1
        }
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            restorePreferredInputDefault()
            throw AudioRecordingError.couldNotStart
        }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.appendConverted(buffer)
            self?.noteFirstAudio()
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            restorePreferredInputDefault()
            throw AudioRecordingError.couldNotStart
        }
        setCapturing(true)
        // Don't report "started" until the mic is actually delivering audio. On a
        // cold first-of-day start the input hardware + CoreAudio chain take a beat
        // to warm up, and audio spoken in that gap is lost — so the caller only
        // shows "Listening" (the cue to speak) once this returns.
        await awaitFirstAudio()
    }

    /// Clear the first-audio gate before a new recording. Synchronous so the lock
    /// is never held across a suspension point (Swift 6 forbids that).
    private func resetFirstAudioState() {
        lock.lock(); _sawFirstAudio = false; firstAudioWaiter = nil; lock.unlock()
    }

    /// Signal — once — that the mic is now delivering audio, resuming a pending
    /// `awaitFirstAudio`. Called from the audio thread on every buffer; a cheap
    /// no-op after the first.
    private func noteFirstAudio() {
        lock.lock()
        if _sawFirstAudio { lock.unlock(); return }
        _sawFirstAudio = true
        let waiter = firstAudioWaiter
        firstAudioWaiter = nil
        lock.unlock()
        waiter?.resume()
    }

    /// Suspend until the mic delivers its first buffer or `firstAudioTimeoutMillis`
    /// elapses — whichever comes first — so a cold-start warmup gap can't clip the
    /// first words and a dead mic can't hang the start.
    private func awaitFirstAudio() async {
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Self.firstAudioTimeoutMillis))
            self?.resumeFirstAudioWaiter()
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if _sawFirstAudio {
                lock.unlock()
                continuation.resume()
            } else {
                firstAudioWaiter = continuation
                lock.unlock()
            }
        }
        timeout.cancel()
    }

    /// Timeout fallback: resume a pending `awaitFirstAudio` without marking real
    /// audio as seen. Whoever takes the continuation first (this or noteFirstAudio)
    /// nils it, so the other becomes a no-op — never a double resume.
    private func resumeFirstAudioWaiter() {
        lock.lock()
        let waiter = firstAudioWaiter
        firstAudioWaiter = nil
        lock.unlock()
        waiter?.resume()
    }

    func stopRecording() async throws -> URL {
        guard isCapturing else {
            throw AudioRecordingError.notRecording
        }

        // Users release the hotkey the instant they finish the last word, so the
        // final tap buffer (the trailing syllable) is often still in flight. Keep
        // the tap live a beat longer before teardown so it lands in `samples`
        // instead of being clipped by the immediate stop.
        try? await Task.sleep(for: .milliseconds(Self.trailingCaptureMillis))

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        setCapturing(false)
        restorePreferredInputDefault()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-dictation-\(UUID().uuidString).wav")
        try writeWav(to: url, samples: snapshotSamples(maxSeconds: nil))
        return url
    }

    /// Writes the audio captured so far (bounded to the most recent `maxSeconds`)
    /// to a temporary WAV for a preview transcription pass. Returns nil if there
    /// is not yet enough audio to be worth transcribing.
    func snapshotForPreview(maxSeconds: Double = 30) -> URL? {
        let snapshot = snapshotSamples(maxSeconds: maxSeconds)
        guard snapshot.count >= 1_600 else {
            return nil
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-dictation-preview-\(UUID().uuidString).wav")
        do {
            try writeWav(to: url, samples: snapshot)
            return url
        } catch {
            return nil
        }
    }

    private func appendConverted(_ buffer: AVAudioPCMBuffer) {
        guard let converter else {
            return
        }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return
        }

        let source = SingleBufferSource(buffer)
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if let next = source.take() {
                inputStatus.pointee = .haveData
                return next
            }
            inputStatus.pointee = .noDataNow
            return nil
        }

        guard status != .error, let channel = output.floatChannelData else {
            return
        }

        let frames = Int(output.frameLength)
        let level = Self.normalizedLevel(channel[0], frames: frames)
        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: channel[0], count: frames))
        _currentLevel = level
        if level > Self.speechLevelThreshold { _lastSpeechAt = Date() }
        lock.unlock()
    }

    /// RMS → dBFS → 0…1, for the live waveform shown in the dictation overlay.
    private static func normalizedLevel(_ samples: UnsafePointer<Float>, frames: Int) -> Double {
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frames {
            sum += samples[i] * samples[i]
        }
        let rms = sqrt(sum / Float(frames))
        let db = 20 * log10(max(rms, 0.000_001))
        return Double(max(0, min(1, (db + 60) / 60)))
    }

    private func clearSamples() {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        _lastSpeechAt = nil
        lock.unlock()
    }

    private func snapshotSamples(maxSeconds: Double?) -> [Float] {
        lock.lock()
        defer { lock.unlock() }

        guard let maxSeconds else {
            return samples
        }

        let maxCount = Int(maxSeconds * targetFormat.sampleRate)
        return samples.count > maxCount ? Array(samples.suffix(maxCount)) : samples
    }

    private func writeWav(to url: URL, samples: [Float]) throws {
        // Peak-normalize before writing so a quiet mic still gives Whisper usable
        // headroom (see AudioNormalizer). Applied here, the one choke point, so the
        // final pass and the live preview snapshot agree.
        let samples = AudioNormalizer.peakNormalized(samples)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        let chunkFrames = 16_000
        var index = 0
        while index < samples.count {
            let count = min(chunkFrames, samples.count - index)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(count)) else {
                break
            }
            buffer.frameLength = AVAudioFrameCount(count)
            guard let destination = buffer.floatChannelData?[0] else { break }
            samples.withUnsafeBufferPointer { source in
                guard let base = source.baseAddress else { return }
                destination.update(from: base.advanced(by: index), count: count)
            }
            try file.write(from: buffer)
            index += count
        }
    }
}
