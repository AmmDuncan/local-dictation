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
    private let serverManager = WhisperServerManager()
    private let llamaManager = LlamaServerManager()
    private var workflow: DictationWorkflow?
    private var recorder: AudioFileRecorder?
    private var previewTask: Task<Void, Never>?
    private var isFinishing = false

    init() {
        KeyboardShortcuts.onKeyDown(for: .holdToDictate) { [weak self] in
            Task { @MainActor in
                await self?.beginHold()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .holdToDictate) { [weak self] in
            Task { @MainActor in
                await self?.endHold()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.serverManager.stop()
                self?.llamaManager.stop()
            }
        }

        let settings = AppSettingsSnapshot.current
        warmUpServer(settings: settings)
        warmUpPolishServer(settings: settings)
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
        guard !isRecording, !isFinishing else {
            return
        }

        let settings = AppSettingsSnapshot.current
        errorMessage = nil
        lastTranscript = ""

        guard await PermissionStatus.requestMicrophoneAccess() else {
            fail("Microphone permission is required.")
            return
        }

        if settings.pasteOnRelease, !PermissionStatus.isAccessibilityTrusted {
            PermissionStatus.promptForAccessibilityIfNeeded()
            fail("Accessibility permission is required for paste insertion.")
            return
        }

        WhisperLocator.ensureBackendsLinked()
        warmUpServer(settings: settings)  // (re)starts if the model changed
        warmUpPolishServer(settings: settings)
        let workflow = makeWorkflow(settings: settings)
        self.workflow = workflow

        do {
            status = "Listening"
            isRecording = true
            if settings.showOverlay {
                overlayController.showListening(detail: "") { [weak self] in
                    self?.recorder?.currentLevel ?? 0
                }
            }
            try await workflow.beginRecording()
            if settings.showOverlay, let recorder {
                startPreviewLoop(recorder: recorder, settings: settings)
            }
        } catch {
            isRecording = false
            fail(error.localizedDescription)
        }
    }

    func endHold() async {
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

            if settings.showOverlay {
                if transcript.isEmpty {
                    overlayController.hide(after: 0.4)
                } else {
                    overlayController.showDone(text: transcript)
                    overlayController.hide(after: 2.4)
                }
            }
        } catch {
            fail(error.localizedDescription)
        }

        isFinishing = false
        self.workflow = nil
        self.recorder = nil
    }

    private func makeWorkflow(settings: AppSettingsSnapshot) -> DictationWorkflow {
        // The final pass prefers the resident server, waiting out a cold model
        // load rather than racing a cold CLI against it (which can fail). Only if
        // the server can't come up does it fall back to the per-call CLI.
        let transcriber = ResolvingTranscriptionEngine(
            serverManager: serverManager,
            configuration: makeConfiguration(settings: settings, timeoutSeconds: 60),
            language: settings.normalizedLanguage,
            timeoutSeconds: 60,
            serverWait: 30
        )

        let inserter: TextInserting = settings.pasteOnRelease ? ClipboardInserter() : PreviewOnlyInserter()

        let recorder = AudioFileRecorder()
        self.recorder = recorder

        let polisher: TextPolishing? = settings.polishWithAI
            ? ServerBackedPolisher(serverManager: llamaManager, serverWait: 30)
            : nil

        return DictationWorkflow(
            recorder: recorder,
            transcriber: transcriber,
            inserter: inserter,
            cleanupOptions: settings.cleanUpTranscript ? TranscriptCleaner.Options() : nil,
            polisher: polisher
        )
    }

    private func makeConfiguration(settings: AppSettingsSnapshot, timeoutSeconds: TimeInterval = 60) -> WhisperCLIConfiguration {
        .init(
            executablePath: WhisperLocator.resolved(configured: settings.whisperExecutablePath),
            modelPath: settings.modelPath.expandingTildeInPath,
            language: settings.normalizedLanguage,
            timeoutSeconds: timeoutSeconds,
            vadModelPath: WhisperLocator.resolvedVadModel()
        )
    }

    /// Periodically transcribes the audio captured so far and shows it in the
    /// overlay, so the user sees a rolling preview instead of waiting for the
    /// final result. Partial text is lower quality than the final pass and may
    /// revise itself as more speech arrives.
    private func startPreviewLoop(recorder: AudioFileRecorder, settings: AppSettingsSnapshot) {
        let language = settings.normalizedLanguage

        previewTask?.cancel()
        previewTask = Task { [weak self] in
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
                    baseURL: baseURL, language: language, timeoutSeconds: 8
                )
                let raw = try? await engine.transcribe(audioFile: url)
                let text = WhisperTranscriptParser.strippedForInsertion(raw ?? "")

                guard !Task.isCancelled, !text.isEmpty else {
                    continue
                }

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
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

private struct PreviewOnlyInserter: TextInserting {
    func insert(_ text: String) async throws {}
}

/// Polishes via the resident llama-server, waiting out a cold model load. If the
/// server isn't available it returns the text unchanged (LlamaPolishEngine also
/// falls back on any failure), so polish never blocks or corrupts insertion.
private struct ServerBackedPolisher: TextPolishing {
    let serverManager: LlamaServerManager
    let serverWait: TimeInterval

    func polish(_ text: String) async -> String {
        guard let baseURL = await serverManager.awaitReady(timeout: serverWait) else { return text }
        return await LlamaPolishEngine(baseURL: baseURL).polish(text)
    }
}

/// Resolves the transcription path at call time: prefer the resident
/// whisper-server (waiting out a cold model load up to `serverWait`), and only
/// fall back to the per-call CLI if the server can't come up. Keeps the final
/// pass from racing a cold CLI against a still-loading server.
private struct ResolvingTranscriptionEngine: TranscriptionEngine {
    let serverManager: WhisperServerManager
    let configuration: WhisperCLIConfiguration
    let language: String?
    let timeoutSeconds: TimeInterval
    let serverWait: TimeInterval

    func transcribe(audioFile: URL) async throws -> String {
        if let baseURL = await serverManager.awaitReady(timeout: serverWait) {
            do {
                return try await WhisperServerTranscriptionEngine(
                    baseURL: baseURL, language: language, timeoutSeconds: timeoutSeconds
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
