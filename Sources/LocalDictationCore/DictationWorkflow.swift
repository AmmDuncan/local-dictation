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
    case cancelled

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
        case .cancelled:
            "Cancelled"
        }
    }
}

public final class DictationWorkflow: @unchecked Sendable {
    /// Below this the recording is empty/truncated (header-only ≈ 44 bytes); a
    /// valid ~0.1s clip is already several KB. Guards against the server's 400 on
    /// degenerate audio.
    private static let minimumAudioBytes = 1024

    /// The raw transcript, the deterministic pre-polish result (the coordinate space
    /// Segment A edits highlight against), the inserted text, and the attributed
    /// swaps split by the opaque polish boundary: Segment A = pre-polish corrections
    /// (mishearing/command), Segment B = post-polish replacements. Drives the Learn
    /// queue + the review panel. (`strip`/`cleanup` removals aren't tracked in v1 —
    /// they aren't revertable swaps; see the spec's scope note.)
    public typealias TranscriptEdits = (
        raw: String, prePolish: String, final: String, segmentA: [Edit], segmentB: [Edit]
    )

    private let lock = NSLock()
    private var _state: DictationWorkflowState = .idle
    private var _lastTranscript: String?
    private var _lastTranscriptAndEdits: TranscriptEdits?

    public var state: DictationWorkflowState {
        lock.lock(); defer { lock.unlock() }
        return _state
    }

    public var lastTranscript: String? {
        lock.lock(); defer { lock.unlock() }
        return _lastTranscript
    }

    /// The most recent transcript with its attributed edits, or nil if none yet.
    public var lastTranscriptAndEdits: TranscriptEdits? {
        lock.lock(); defer { lock.unlock() }
        return _lastTranscriptAndEdits
    }

    private func setState(_ newValue: DictationWorkflowState) {
        lock.lock(); _state = newValue; lock.unlock()
    }

    private func setLastTranscript(_ newValue: String?) {
        lock.lock(); _lastTranscript = newValue; lock.unlock()
    }

    private func setLastTranscriptAndEdits(_ newValue: TranscriptEdits?) {
        lock.lock(); _lastTranscriptAndEdits = newValue; lock.unlock()
    }

    private let recorder: AudioRecording
    private let transcriber: TranscriptionEngine
    private let inserter: TextInserting
    private let cleanupOptions: TranscriptCleaner.Options?
    /// Deterministic transform applied BEFORE polish — built-in known-mishearing
    /// fixes (e.g. "clot" -> "Claude"). Runs first so the polish model sees the
    /// correct term instead of swapping in an unrelated vocabulary word. Returns the
    /// corrected text plus its attributed edits (Segment A).
    private let preCorrect: (@Sendable (String) -> (String, [Edit]))?
    private let contextSubstitute: (@Sendable (String) async -> (String, [Edit]))?
    private let polisher: TextPolishing?
    /// Deterministic transform applied AFTER polish, just before insertion — e.g.
    /// user text replacements / snippet expansion. Runs after polish so an
    /// expansion can't trip the polish word-divergence guardrail. Returns the
    /// processed text plus its attributed edits (Segment B).
    private let postProcess: (@Sendable (String) -> (String, [Edit]))?

    public init(
        recorder: AudioRecording,
        transcriber: TranscriptionEngine,
        inserter: TextInserting,
        cleanupOptions: TranscriptCleaner.Options? = nil,
        preCorrect: (@Sendable (String) -> (String, [Edit]))? = nil,
        contextSubstitute: (@Sendable (String) async -> (String, [Edit]))? = nil,
        polisher: TextPolishing? = nil,
        postProcess: (@Sendable (String) -> (String, [Edit]))? = nil
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.inserter = inserter
        self.cleanupOptions = cleanupOptions
        self.preCorrect = preCorrect
        self.contextSubstitute = contextSubstitute
        self.polisher = polisher
        self.postProcess = postProcess
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

    /// Abort an in-progress recording without transcribing or inserting anything.
    /// Stops the recorder, discards the captured audio, and leaves the workflow
    /// in `.cancelled`. A no-op unless currently recording.
    public func cancelRecording() async {
        guard state == .recording else {
            return
        }
        if let audioFile = try? await recorder.stopRecording() {
            try? FileManager.default.removeItem(at: audioFile)
        }
        setLastTranscript(nil)
        setState(.cancelled)
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
            // Deterministic known-mishearing fixes BEFORE polish, so the model
            // sees the correct term and doesn't swap in an unrelated vocab word.
            // The returned edits (Segment A) are in this pre-polish coordinate space.
            var segmentA: [Edit] = []
            if let preCorrect {
                let (corrected, edits) = preCorrect(insertText)
                insertText = corrected
                segmentA = edits
            }
            // Context substitution (async; may suspend for the confirm overlay).
            // Folds its edits into Segment A so they share the pre-polish space
            // and surface as CONTEXT chips in the review panel.
            if let contextSubstitute {
                let (corrected, edits) = await contextSubstitute(insertText)
                insertText = corrected
                segmentA = EditFold.combine([segmentA, edits])
            }
            // The deterministic pre-polish result — the space Segment A edits point
            // into, and what the review panel highlights against.
            let prePolish = insertText
            // Optional LLM polish runs next and is self-guarding: it returns the
            // input unchanged on any failure, so it can never break insertion.
            if let polisher {
                insertText = await polisher.polish(insertText)
            }
            // The corrected transcript — what was said, with mishearings fixed —
            // is what we surface to the user (history, menu bar, overlay). It is
            // captured here, before the post-process expansion below, and replaces
            // the raw transcript that used to be shown (which made corrections
            // invisible even though the fixed text was what actually got typed).
            let correctedTranscript = insertText
            // Deterministic post-process (text replacements / snippets), after
            // polish so an expansion can't trip the polish guardrail. Its edits
            // (Segment B) are in the final inserted-text space.
            var segmentB: [Edit] = []
            if let postProcess {
                let (processed, edits) = postProcess(insertText)
                insertText = processed
                segmentB = edits
            }
            guard !insertText.isEmpty else {
                setState(.failed("No speech was detected."))
                return
            }

            setLastTranscript(correctedTranscript)
            setLastTranscriptAndEdits(
                (raw: transcript, prePolish: prePolish, final: insertText, segmentA: segmentA, segmentB: segmentB)
            )
            setState(.pasting(correctedTranscript))
            try await inserter.insert(insertText)
            setState(.idle)
        } catch {
            setState(.failed(error.localizedDescription))
            throw error
        }
    }
}
