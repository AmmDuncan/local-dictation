@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import Observation

private final class LevelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double = 0

    func set(_ newValue: Double) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// Live microphone level (0…1) for the settings audio section. Runs its own
/// engine only while visible; smooths with a fast attack / slow release so the
/// meter reads naturally.
@MainActor
@Observable
final class AudioLevelMeter {
    private(set) var level: Double = 0
    private(set) var isRunning = false

    // Fresh engine per start: `kAudioOutputUnitProperty_CurrentDevice` only binds
    // on an uninitialized HAL unit, so a reused engine would silently ignore the
    // device switch and stay on whatever it first bound (the recorder does the
    // same for this reason).
    private var engine = AVAudioEngine()
    private let box = LevelBox()

    func start(deviceUID: String) {
        guard !isRunning else { return }
        // Touching inputNode without microphone permission traps on macOS.
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }

        engine = AVAudioEngine()
        let input = engine.inputNode
        if let deviceID = AudioDevices.resolveInputDeviceID(forUID: deviceUID), let unit = input.audioUnit {
            var value = deviceID
            AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                &value, UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }

        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }

        // @Sendable forces the tap block non-isolated. Without it the closure
        // inherits this class's @MainActor isolation and AVFAudio calling it on
        // the realtime audio thread trips a fatal main-thread assertion.
        let box = box
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
            box.set(Self.normalizedLevel(from: buffer))
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return
        }
        isRunning = true
        runDisplayLoop()
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        level = 0
        box.set(0)
    }

    /// Restart on the given device (e.g. after the user picks a new input).
    func restart(deviceUID: String) {
        stop()
        start(deviceUID: deviceUID)
    }

    private func runDisplayLoop() {
        Task { @MainActor in
            while isRunning {
                let target = box.get()
                let smoothing = target > level ? 0.6 : 0.2
                level += (target - level) * smoothing
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    // nonisolated: runs on the realtime audio thread (the tap), not the main actor.
    private nonisolated static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }

        var sum: Float = 0
        let samples = channel[0]
        for i in 0..<frames {
            sum += samples[i] * samples[i]
        }
        let rms = sqrt(sum / Float(frames))
        let db = 20 * log10(max(rms, 0.000_001))
        return Double(max(0, min(1, (db + 60) / 60)))  // -60 dBFS … 0 dBFS → 0 … 1
    }
}
