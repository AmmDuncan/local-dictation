@preconcurrency import AVFoundation
import AudioToolbox
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
    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!
    private var converter: AVAudioConverter?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var _isCapturing = false
    private var _currentLevel: Double = 0

    /// Most recent normalized mic level (0…1), updated on the audio thread.
    var currentLevel: Double {
        lock.lock(); defer { lock.unlock() }
        return _currentLevel
    }

    private var isCapturing: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isCapturing
    }

    private func setCapturing(_ value: Bool) {
        lock.lock(); _isCapturing = value; lock.unlock()
    }

    func startRecording() async throws {
        guard await PermissionStatus.requestMicrophoneAccess() else {
            throw AudioRecordingError.permissionDenied
        }

        clearSamples()

        let input = engine.inputNode
        let deviceUID = AppSettingsSnapshot.current.inputDeviceUID
        if let deviceID = AudioDevices.deviceID(forUID: deviceUID), let unit = input.audioUnit {
            var value = deviceID
            AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                &value, UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioRecordingError.couldNotStart
        }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.appendConverted(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AudioRecordingError.couldNotStart
        }
        setCapturing(true)
    }

    func stopRecording() async throws -> URL {
        guard isCapturing else {
            throw AudioRecordingError.notRecording
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        setCapturing(false)

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
