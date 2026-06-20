import AppKit
import Foundation
import Observation
@preconcurrency import KeyboardShortcuts
import LocalDictationCore

@MainActor
@Observable
final class AppModel {
    private(set) var status = "Idle"
    private(set) var lastTranscript = ""
    private(set) var errorMessage: String?
    private(set) var isRecording = false

    let readiness = ReadinessModel()

    private let overlayController = OverlayController()
    private let serverManager = ResidentServerManager(config: .whisper)
    private let llamaManager = ResidentServerManager(config: .llama)
    private var workflow: DictationWorkflow?
    private var recorder: AudioFileRecorder?
    private var previewTask: Task<Void, Never>?
    private var isFinishing = false
    /// True while a dictation is starting up (perms → recorder warm). A release or
    /// Escape that arrives in this window is deferred via `pendingEnd` and applied
    /// once startup finishes — fixes the fast tap-release race.
    private var isStarting = false
    private var pendingEnd: PendingEnd = .none
    private var escapeMonitor: Any?
    private var localEscapeMonitor: Any?
    /// Rolling recent transcripts, persisted, used to bias whisper toward the
    /// user's own words (fewer mishearings). See RecognitionContext.
    private var history: [String] = UserDefaults.standard.stringArray(forKey: "dictationHistory") ?? []

    private enum PendingEnd { case none, finish, cancel }

    init() {
        KeyboardShortcuts.onKeyDown(for: .holdToDictate) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                // Toggle mode: key-down flips recording on/off. Hold mode: starts.
                if AppSettingsSnapshot.current.activation == .toggle, self.isRecording || self.isStarting {
                    await self.endHold()
                } else {
                    await self.beginHold()
                }
            }
        }

        KeyboardShortcuts.onKeyUp(for: .holdToDictate) { [weak self] in
            Task { @MainActor in
                guard let self, AppSettingsSnapshot.current.activation == .hold else { return }
                await self.endHold()
            }
        }

        // Escape aborts an in-progress dictation (discard, paste nothing). Global
        // monitor needs accessibility/input-monitoring, which dictation already
        // requires; the local monitor covers the rare case our own UI has focus.
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in
                guard let self, self.isRecording || self.isStarting else { return }
                await self.cancelHold()
            }
        }
        // Global monitor fires only for events sent to OTHER apps; the local one
        // covers the case our own window (Settings/History) has focus — so the two
        // are mutually exclusive, never double-firing. Both retained for lifetime.
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, let self, self.isRecording || self.isStarting {
                Task { @MainActor in await self.cancelHold() }
            }
            return event
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.serverManager.stop()
                self?.llamaManager.stop()
            }
        }

        // External control surface (SIGUSR1/2 via AppDelegate, future hooks).
        DictationControl.toggle = { [weak self] in
            Task { @MainActor in await self?.toggleDictation() }
        }
        DictationControl.cancel = { [weak self] in
            Task { @MainActor in await self?.cancelHold() }
        }

        let settings = AppSettingsSnapshot.current
        warmUpServer(settings: settings)
        warmUpPolishServer(settings: settings)
    }

    /// Programmatic start/stop (automation/signals), independent of the hold vs
    /// toggle hotkey setting.
    func toggleDictation() async {
        if isRecording || isStarting {
            await endHold()
        } else {
            await beginHold()
        }
    }

    /// Start whisper-server in the background so the model is resident before the
    /// first dictation. Falls back to the per-call CLI until it's ready.
    private func warmUpServer(settings: AppSettingsSnapshot) {
        let model = settings.modelPath.expandingTildeInPath
        guard FileManager.default.fileExists(atPath: model),
              let server = WhisperLocator.resolvedServer() else {
            return
        }
        serverManager.ensureRunning(modelPath: model, executablePath: server)
    }

    /// Start (or stop) the resident llama-server for the optional LLM polish pass.
    /// Only runs when polish is enabled and both the model + executable exist.
    private func warmUpPolishServer(settings: AppSettingsSnapshot) {
        guard settings.polishWithAI else {
            llamaManager.stop()
            return
        }
        let model = settings.polishModelPath.expandingTildeInPath
        guard FileManager.default.fileExists(atPath: model),
              let server = WhisperLocator.resolvedLlamaServer() else {
            return
        }
        llamaManager.ensureRunning(modelPath: model, executablePath: server)
    }

    func beginHold() async {
        guard !isRecording, !isFinishing, !isStarting else {
            return
        }

        isStarting = true
        pendingEnd = .none
        let settings = AppSettingsSnapshot.current
        errorMessage = nil
        lastTranscript = ""

        guard await PermissionStatus.requestMicrophoneAccess() else {
            isStarting = false
            fail("Microphone permission is required.")
            return
        }

        if settings.pasteOnRelease, !PermissionStatus.isAccessibilityTrusted {
            PermissionStatus.promptForAccessibilityIfNeeded()
            isStarting = false
            fail("Accessibility permission is required for paste insertion.")
            return
        }

        // Start capturing audio FIRST so the first word isn't clipped. Server
        // warmup / backend linking only matter for the final pass (seconds
        // later), so they must not delay the mic. makeWorkflow is cheap (no I/O).
        let workflow = makeWorkflow(settings: settings)
        self.workflow = workflow

        do {
            if settings.showOverlay {
                overlayController.showListening(detail: "") { [weak self] in
                    self?.recorder?.currentLevel ?? 0
                }
            }
            try await workflow.beginRecording()
        } catch {
            isStarting = false
            self.workflow = nil
            self.recorder = nil
            if settings.showOverlay { overlayController.hide(after: 0) }
            fail(userFacingMessage(for: error))
            return
        }

        // Recording is live — only now is it safe to honor end/cancel.
        isStarting = false
        isRecording = true
        status = "Listening"

        // A release or Escape that arrived during startup is applied now.
        switch pendingEnd {
        case .finish: pendingEnd = .none; await finishCurrent(); return
        case .cancel: pendingEnd = .none; await cancelCurrent(); return
        case .none: break
        }

        // Capture is live — now do the slower setup the final pass needs.
        WhisperLocator.ensureBackendsLinked()
        warmUpServer(settings: settings)  // (re)starts if the model changed
        warmUpPolishServer(settings: settings)
        if settings.showOverlay, let recorder {
            startPreviewLoop(recorder: recorder, settings: settings)
        }
    }

    /// Stop and transcribe (hold released / toggled off). Deferred if a dictation
    /// is still starting up.
    func endHold() async {
        if isStarting { pendingEnd = .finish; return }
        await finishCurrent()
    }

    /// Abort and discard (Escape). Deferred if a dictation is still starting up.
    func cancelHold() async {
        if isStarting { pendingEnd = .cancel; return }
        await cancelCurrent()
    }

    private func cancelCurrent() async {
        guard isRecording, !isFinishing, let workflow else {
            return
        }
        isRecording = false
        isFinishing = true
        status = "Cancelled"

        let pendingPreview = previewTask
        previewTask = nil
        pendingPreview?.cancel()
        await pendingPreview?.value

        await workflow.cancelRecording()
        errorMessage = nil
        status = "Idle"
        if AppSettingsSnapshot.current.showOverlay {
            overlayController.showCancelled()
            overlayController.hide(after: 1.2)
        }

        isFinishing = false
        self.workflow = nil
        self.recorder = nil
    }

    private func finishCurrent() async {
        guard isRecording, !isFinishing, let workflow else {
            return
        }

        isRecording = false
        isFinishing = true
        status = "Transcribing"

        // Stop the preview AND wait for any in-flight preview transcription to
        // finish, so two whisper-cli processes never contend for CPU + the model.
        let pendingPreview = previewTask
        previewTask = nil
        pendingPreview?.cancel()
        await pendingPreview?.value

        let settings = AppSettingsSnapshot.current
        if settings.showOverlay {
            overlayController.showTranscribing()
        }

        do {
            try await workflow.finishRecording()
            let transcript = workflow.lastTranscript ?? ""
            lastTranscript = transcript
            status = transcript.isEmpty ? "Idle" : "Inserted"
            errorMessage = nil
            if !transcript.isEmpty { recordHistory(transcript) }

            if settings.showOverlay {
                if transcript.isEmpty {
                    overlayController.hide(after: 0.4)
                } else {
                    overlayController.showDone(text: transcript)
                    overlayController.hide(after: 2.4)
                }
            }
        } catch TranscriptionError.emptyTranscript {
            // The engine ran but heard nothing — that's "no speech", not an error.
            status = "Idle"
            errorMessage = nil
            if settings.showOverlay { overlayController.hide(after: 0.4) }
        } catch {
            fail(userFacingMessage(for: error))
        }

        isFinishing = false
        self.workflow = nil
        self.recorder = nil
    }

    /// Plain-language message for the overlay/menu — never the raw technical
    /// `description` (binary names, paths, status codes), which stays in logs.
    private func userFacingMessage(for error: Error) -> String {
        if let error = error as? TranscriptionError { return error.userMessage }
        if let error = error as? AudioRecordingError { return error.description }
        return "Something went wrong. Please try again."
    }

    private func makeWorkflow(settings: AppSettingsSnapshot) -> DictationWorkflow {
        // The final pass prefers the resident server, waiting out a cold model
        // load rather than racing a cold CLI against it (which can fail). Only if
        // the server can't come up does it fall back to the per-call CLI.
        let prompt = contextPrompt(settings: settings)
        let transcriber = ResolvingTranscriptionEngine(
            serverManager: serverManager,
            configuration: makeConfiguration(settings: settings, timeoutSeconds: 60, prompt: prompt),
            language: settings.normalizedLanguage,
            timeoutSeconds: 60,
            serverWait: 30,
            prompt: prompt
        )

        let inserter = makeInserter(settings: settings)

        let recorder = AudioFileRecorder()
        self.recorder = recorder

        // Polish (when on) always fixes mishearings, fed the same vocab/history
        // context that biases recognition — so it catches the names whisper still
        // gets wrong (e.g. "clot" → "Claude").
        let polisher: TextPolishing? = settings.polishWithAI
            ? ServerBackedPolisher(serverManager: llamaManager, serverWait: 30, context: prompt)
            : nil

        return DictationWorkflow(
            recorder: recorder,
            transcriber: transcriber,
            inserter: inserter,
            cleanupOptions: settings.cleanUpTranscript ? TranscriptCleaner.Options() : nil,
            polisher: polisher,
            postProcess: textReplacementsTransform(settings: settings)
        )
    }

    private func makeInserter(settings: AppSettingsSnapshot) -> TextInserting {
        guard settings.pasteOnRelease else { return PreviewOnlyInserter() }
        let base: TextInserting = settings.insertion == .keystroke ? KeystrokeInserter() : ClipboardInserter()
        // Smart spacing needs to read the caret context (accessibility); when on,
        // wrap so the text lowercases mid-sentence and spaces cleanly at the caret.
        return settings.smartSpacing ? CaretAwareInserter(wrapped: base) : base
    }

    private func textReplacementsTransform(settings: AppSettingsSnapshot) -> (@Sendable (String) -> String)? {
        guard settings.useTextReplacements else { return nil }
        let rules = TextReplacements.parse(settings.textReplacements)
        guard !rules.isEmpty else { return nil }
        return { TextReplacements.apply(rules, to: $0) }
    }

    private func makeConfiguration(settings: AppSettingsSnapshot, timeoutSeconds: TimeInterval = 60, prompt: String? = nil) -> WhisperCLIConfiguration {
        .init(
            executablePath: WhisperLocator.resolved(configured: settings.whisperExecutablePath),
            modelPath: settings.modelPath.expandingTildeInPath,
            language: settings.normalizedLanguage,
            timeoutSeconds: timeoutSeconds,
            vadModelPath: WhisperLocator.resolvedVadModel(),
            prompt: prompt
        )
    }

    /// Whisper context prompt from the user's vocabulary + recent history, to
    /// bias recognition toward their own words (fewer mishearings). Nil = none.
    private func contextPrompt(settings: AppSettingsSnapshot) -> String? {
        let prompt = RecognitionContext.prompt(
            vocabulary: settings.customVocabulary,
            defaults: settings.useDefaultVocabulary ? DefaultVocabulary.terms : [],
            history: settings.useHistoryContext ? history : []
        )
        return prompt.isEmpty ? nil : prompt
    }

    private func recordHistory(_ transcript: String) {
        history = RecognitionContext.appendingHistory(transcript, to: history)
        UserDefaults.standard.set(history, forKey: "dictationHistory")
        if AppSettingsSnapshot.current.saveHistory {
            TranscriptHistoryStore.append(transcript)
        }
    }

    /// Periodically transcribes the audio captured so far and shows it in the
    /// overlay, so the user sees a rolling preview instead of waiting for the
    /// final result. Partial text is lower quality than the final pass and may
    /// revise itself as more speech arrives.
    private func startPreviewLoop(recorder: AudioFileRecorder, settings: AppSettingsSnapshot) {
        let language = settings.normalizedLanguage
        let prompt = contextPrompt(settings: settings)
        let cleanupOptions: TranscriptCleaner.Options? = settings.cleanUpTranscript ? TranscriptCleaner.Options() : nil

        previewTask?.cancel()
        previewTask = Task { [weak self] in
            var lastShown = ""
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 900_000_000)
                if Task.isCancelled {
                    break
                }

                // Preview only through the resident server. A cold CLI spun up
                // mid-recording contends with the still-loading server and can
                // fail, so skip the preview entirely until the server is warm.
                let baseURL = await MainActor.run { self?.serverManager.baseURL }
                guard let baseURL else {
                    continue
                }

                // Skip near-silence so whisper doesn't hallucinate phantom words
                // on no input, and clean what it does return like the final pass.
                guard recorder.currentLevel > 0.05, let url = recorder.snapshotForPreview() else {
                    continue
                }
                defer { try? FileManager.default.removeItem(at: url) }

                let engine = WhisperServerTranscriptionEngine(
                    baseURL: baseURL, language: language, timeoutSeconds: 8, prompt: prompt
                )
                let raw = try? await engine.transcribe(audioFile: url)
                var text = WhisperTranscriptParser.strippedForInsertion(raw ?? "")
                if let cleanupOptions {
                    text = TranscriptCleaner.clean(text, options: cleanupOptions)
                }

                // Skip empties and unchanged text so the preview reads steadily
                // instead of flickering as whisper re-transcribes the window.
                guard !Task.isCancelled, !text.isEmpty, text != lastShown else {
                    continue
                }
                lastShown = text

                await MainActor.run {
                    guard let self, self.isRecording else {
                        return
                    }
                    self.overlayController.updateListeningDetail(text)
                }
            }
        }
    }

    private func fail(_ message: String) {
        status = "Error"
        errorMessage = message

        guard AppSettingsSnapshot.current.showOverlay else { return }
        if message.localizedCaseInsensitiveContains("microphone") {
            overlayController.showError(message: message, actionTitle: "Open Settings") {
                PermissionStatus.openMicrophoneSettings()
            }
            overlayController.hide(after: 6)
        } else if message.localizedCaseInsensitiveContains("accessibility") {
            overlayController.showError(message: message, actionTitle: "Open Settings") {
                PermissionStatus.openAccessibilitySettings()
            }
            overlayController.hide(after: 6)
        } else if message.localizedCaseInsensitiveContains("model") || message.localizedCaseInsensitiveContains("whisper-cli") {
            overlayController.showError(message: message, actionTitle: "Open Settings") {
                Self.openAppSettings()
            }
            overlayController.hide(after: 6)
        } else {
            overlayController.showError(message: message)
            overlayController.hide(after: 4)
        }
    }

    private static func openAppSettings() {
        SettingsLauncher.open()
    }
}

private struct PreviewOnlyInserter: TextInserting {
    func insert(_ text: String) async throws {}
}

/// Polishes via the resident llama-server, waiting out a cold model load. If the
/// server isn't available it returns the text unchanged (LlamaPolishEngine also
/// falls back on any failure), so polish never blocks or corrupts insertion.
private struct ServerBackedPolisher: TextPolishing {
    let serverManager: ResidentServerManager
    let serverWait: TimeInterval
    var context: String?

    func polish(_ text: String) async -> String {
        guard let baseURL = await serverManager.awaitReady(timeout: serverWait) else { return text }
        return await LlamaPolishEngine(baseURL: baseURL, context: context).polish(text)
    }
}

/// Wraps another inserter, reading the caret context (via accessibility) and
/// applying `InsertionFormatter` so the text continues a sentence in lowercase
/// and spaces cleanly against the preceding word. Falls back to the raw text
/// whenever the caret context can't be read.
private struct CaretAwareInserter: TextInserting {
    let wrapped: TextInserting

    func insert(_ text: String) async throws {
        let preceding = await MainActor.run { CaretContext.precedingCharacter() }
        try await wrapped.insert(InsertionFormatter.format(text, precedingCharacter: preceding))
    }
}

/// Resolves the transcription path at call time: prefer the resident
/// whisper-server (waiting out a cold model load up to `serverWait`), and only
/// fall back to the per-call CLI if the server can't come up. Keeps the final
/// pass from racing a cold CLI against a still-loading server.
private struct ResolvingTranscriptionEngine: TranscriptionEngine {
    let serverManager: ResidentServerManager
    let configuration: WhisperCLIConfiguration
    let language: String?
    let timeoutSeconds: TimeInterval
    let serverWait: TimeInterval
    let prompt: String?

    func transcribe(audioFile: URL) async throws -> String {
        if let baseURL = await serverManager.awaitReady(timeout: serverWait) {
            do {
                return try await WhisperServerTranscriptionEngine(
                    baseURL: baseURL, language: language, timeoutSeconds: timeoutSeconds, prompt: prompt
                ).transcribe(audioFile: audioFile)
            } catch TranscriptionError.emptyTranscript {
                // A real "no speech" result — don't waste a cold CLI pass on it.
                throw TranscriptionError.emptyTranscript
            } catch {
                // Any other server hiccup (transient error, busy) → fall back to
                // the per-call CLI rather than failing the dictation.
            }
        }
        return try await WhisperCLITranscriptionEngine(configuration: configuration)
            .transcribe(audioFile: audioFile)
    }
}
