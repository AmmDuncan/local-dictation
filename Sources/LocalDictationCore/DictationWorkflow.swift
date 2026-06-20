import Foundation

public protocol AudioRecording: Sendable {
    func startRecording() async throws
    func stopRecording() async throws -> URL
}

public enum DictationWorkflowState: Equatable, Sendable, CustomStringConvertible {
    case idle
    case recording
    case transcribing
    case pasting(String)
    case failed(String)

    public var description: String {
        switch self {
        case .idle:
            "Idle"
        case .recording:
            "Recording"
        case .transcribing:
            "Transcribing"
        case let .pasting(text):
            "Pasting \(text)"
        case let .failed(message):
            "Failed: \(message)"
        }
    }
}

public final class DictationWorkflow: @unchecked Sendable {
    /// Below this the recording is empty/truncated (header-only ≈ 44 bytes); a
    /// valid ~0.1s clip is already several KB. Guards against the server's 400 on
    /// degenerate audio.
    private static let minimumAudioBytes = 1024

    private let lock = NSLock()
    private var _state: DictationWorkflowState = .idle
    private var _lastTranscript: String?

    public var state: DictationWorkflowState {
        lock.lock(); defer { lock.unlock() }
        return _state
    }

    public var lastTranscript: String? {
        lock.lock(); defer { lock.unlock() }
        return _lastTranscript
    }

    private func setState(_ newValue: DictationWorkflowState) {
        lock.lock(); _state = newValue; lock.unlock()
    }

    private func setLastTranscript(_ newValue: String?) {
        lock.lock(); _lastTranscript = newValue; lock.unlock()
    }

    private let recorder: AudioRecording
    private let transcriber: TranscriptionEngine
    private let inserter: TextInserting
    private let cleanupOptions: TranscriptCleaner.Options?
    private let polisher: TextPolishing?

    public init(
        recorder: AudioRecording,
        transcriber: TranscriptionEngine,
        inserter: TextInserting,
        cleanupOptions: TranscriptCleaner.Options? = nil,
        polisher: TextPolishing? = nil
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.inserter = inserter
        self.cleanupOptions = cleanupOptions
        self.polisher = polisher
    }

    public func beginRecording() async throws {
        guard state != .recording else {
            return
        }

        setState(.recording)
        setLastTranscript(nil)

        do {
            try await recorder.startRecording()
        } catch {
            setState(.failed(error.localizedDescription))
            throw error
        }
    }

    public func finishRecording() async throws {
        guard state == .recording else {
            return
        }

        do {
            let audioFile = try await recorder.stopRecording()
            defer { try? FileManager.default.removeItem(at: audioFile) }

            // A too-short / accidental tap yields an empty or truncated wav that
            // the transcription server rejects (HTTP 400). Treat anything below a
            // few milliseconds of audio as no speech instead of erroring out.
            let bytes = (try? FileManager.default.attributesOfItem(atPath: audioFile.path)[.size]) as? Int ?? 0
            guard bytes >= Self.minimumAudioBytes else {
                setState(.failed("No speech was detected."))
                return
            }

            setState(.transcribing)

            let transcript = try await transcriber.transcribe(audioFile: audioFile)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Only type real speech. Non-speech (silence, whistle, noise) that
            // whisper renders as annotations or bare punctuation produces nothing
            // insertable → treat as no speech rather than typing junk.
            var insertText = WhisperTranscriptParser.strippedForInsertion(transcript)
            if let cleanupOptions {
                insertText = TranscriptCleaner.clean(insertText, options: cleanupOptions)
            }
            guard !insertText.isEmpty else {
                setState(.failed("No speech was detected."))
                return
            }
            // Optional LLM polish runs last and is self-guarding: it returns the
            // input unchanged on any failure, so it can never break insertion.
            if let polisher {
                insertText = await polisher.polish(insertText)
            }

            setLastTranscript(transcript)
            setState(.pasting(transcript))
            try await inserter.insert(insertText)
            setState(.idle)
        } catch {
            setState(.failed(error.localizedDescription))
            throw error
        }
    }
}
