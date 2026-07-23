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
    @ObservationIgnored
    private lazy var substitutionConfirmer = SubstitutionConfirmer(overlay: overlayController)
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

    /// Gathers on-device context (frontmost app + caret text) when context
    /// awareness is on. AX-only, transient — see AccessibilityContextProvider.
    private let contextProvider: ContextProvider = AccessibilityContextProvider()

    /// Cached OCR text per focused app, so the slow Vision OCR never blocks the
    /// mic: the async refresh fills this, and the NEXT dictation in that app reads
    /// it. Transient (in-memory only). See enrichWithOCR.
    private var ocrCache: (app: String, text: String, at: Date)?
    private var ocrTask: Task<Void, Never>?
    /// Floating review panel for the Door #1 hotkey, and the last dictation it shows.
    private let reviewPanelController = ReviewPanelController()
    private var lastRecord: CorrectionRecord?
    /// A cached OCR result stays usable this long; refreshes are throttled to at
    /// most one per this gap so a burst of dictations doesn't re-capture each time.
    private static let ocrCacheTTL: TimeInterval = 30
    private static let ocrRefreshThrottle: TimeInterval = 6

    private enum PendingEnd { case none, finish, cancel }

    init() {
        // Kill any helper servers left over from a previous run that exited without
        // cleanup (force-quit, crash, or a diagnostic exit()). Runs before warm-up
        // so stale orphans die before fresh servers start. Scoped to this bundle's
        // Helpers dir — never touches a Homebrew whisper-server/llama-server.
        Self.reapOrphanedHelpers()
        Self.migrateActivationShortcutIfNeeded()

        // Load the prefilter's word list during idle startup, not the first
        // dictation's hot path.
        Task.detached(priority: .utility) { SubstitutionPrefilter.prewarm() }

        // Hold-to-talk: record while the key is held down.
        KeyboardShortcuts.onKeyDown(for: .holdToDictate) { [weak self] in
            Task { @MainActor in await self?.beginHold() }
        }
        KeyboardShortcuts.onKeyUp(for: .holdToDictate) { [weak self] in
            Task { @MainActor in await self?.endHold() }
        }

        // Tap-to-toggle: first press starts, next press stops. Key-up ignored.
        KeyboardShortcuts.onKeyDown(for: .toggleDictate) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.isRecording || self.isStarting {
                    await self.endHold()
                } else {
                    await self.beginHold()
                }
            }
        }

        // Door #1: open the review panel for the most recent dictation.
        KeyboardShortcuts.onKeyDown(for: .reviewLastDictation) { [weak self] in
            Task { @MainActor in self?.presentReview() }
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

        // NOTE: no Enter-to-commit key. A global monitor can only observe keys, not
        // consume them, so Enter would both commit AND reach the foreground app (a
        // stray newline). Committing is already covered without a leaky key: pressing
        // the toggle hotkey again stops+transcribes, and the compact HUD's ✓ control
        // commits by mouse. Esc-to-cancel is kept (it long predates this and rarely
        // clashes). A true keyboard-commit would need a CGEventTap that swallows the
        // key — deferred unless it proves necessary.

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.serverManager.shutdown()
                self?.llamaManager.shutdown()
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

        // Mic-less pipeline test: feed a WAV straight through the real
        // transcribe → context → correct path (the mic flow is bypassed). Env
        // LD_PIPELINE_TEST=<wav>; optional LD_PIPELINE_APP / LD_PIPELINE_PRECEDING
        // / LD_PIPELINE_VISIBLE override the context; result → LD_PIPELINE_OUT.
        if let wav = ProcessInfo.processInfo.environment["LD_PIPELINE_TEST"] {
            Task { @MainActor in await self.runPipelineTest(wavPath: wav) }
        }
    }

    /// Sweep away orphaned helper servers from this app bundle's Helpers dir.
    private static func reapOrphanedHelpers() {
        let helpersDir = Bundle.main.bundlePath + "/Contents/Helpers"
        HelperProcessReaper.reap(helpersDir: helpersDir)
        // Also reap helpers WE spawned that live outside the bundle (a dev build's
        // Homebrew fallback) — by recorded PID, so unrelated servers are never hit.
        HelperProcessReaper.reapTracked(file: SpawnedHelpers.pidFile)
    }

    /// One-time migration from the old single-shortcut "Activation" setting to two
    /// dedicated shortcuts. Users who were on `toggle` keep tap-to-toggle by moving
    /// their dictation key onto the new toggle shortcut (and clearing the hold one).
    /// Hold-mode users (the default) are untouched.
    @MainActor
    private static func migrateActivationShortcutIfNeeded() {
        let defaults = UserDefaults.standard
        let flag = "didMigrateActivationShortcut"
        guard !defaults.bool(forKey: flag) else { return }
        defaults.set(true, forKey: flag)

        guard defaults.string(forKey: "activationMode") == "toggle",
              let current = KeyboardShortcuts.getShortcut(for: .holdToDictate) else { return }
        KeyboardShortcuts.setShortcut(current, for: .toggleDictate)
        KeyboardShortcuts.setShortcut(nil, for: .holdToDictate)
    }

    /// Run a WAV through the real dictation pipeline with no microphone — same
    /// transcribe → cleanup → correct path as a live dictation, so the context /
    /// command-mode behaviour can be verified deterministically. Context is the
    /// real frontmost app unless overridden via env for a controlled test. Writes
    /// the corrected transcript and exits. Diagnostic-only (env-gated).
    @MainActor
    private func runPipelineTest(wavPath: String) async {
        var settings = AppSettingsSnapshot.current
        settings.pasteOnRelease = false  // never insert into a real app during a test
        WhisperLocator.ensureBackendsLinked()
        warmUpServer(settings: settings)

        let env = ProcessInfo.processInfo.environment
        var context: DictationContext? = settings.useContextAwareness ? await contextProvider.currentContext() : nil
        if let app = env["LD_PIPELINE_APP"] {
            context = DictationContext(
                activeApplicationName: app,
                precedingText: env["LD_PIPELINE_PRECEDING"],
                visibleText: env["LD_PIPELINE_VISIBLE"]
            )
        }

        let recorder = FixedFileRecorder(source: URL(fileURLWithPath: wavPath))
        let workflow = makeWorkflow(settings: settings, context: context, recorderOverride: recorder)
        try? await workflow.beginRecording()
        try? await workflow.finishRecording()

        let result = workflow.lastTranscript ?? "(no speech detected / nil)"
        let line = """
        app=\(context?.activeApplicationName ?? "nil")
        preceding=\(context?.precedingText.map { "\"\($0)\"" } ?? "nil")
        visibleChars=\(context?.visibleText?.count ?? 0)
        transcript=\(result)
        """
        let out = env["LD_PIPELINE_OUT"] ?? "/tmp/ld-pipeline-out.txt"
        try? line.write(toFile: out, atomically: true, encoding: .utf8)
        // exit() skips willTerminate, so tear the server down explicitly — else the
        // test campaign leaks a resident whisper-server per run.
        serverManager.shutdown()
        exit(0)
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

    /// Start (or stop) the resident llama-server for the optional LLM passes
    /// (formatting polish and/or experimental context substitution). Both share
    /// one resident model (settings.polishModelPath).
    private func warmUpPolishServer(settings: AppSettingsSnapshot) {
        guard settings.polishWithAI || settings.contextSubstitutionEnabled else {
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
        // Invalidate the previous review target: a new dictation supersedes it, and
        // if this one yields nothing the ⌥Z hotkey must not review a stale result.
        lastRecord = nil

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

        // Gather on-device context (frontmost app + caret-preceding text + AX
        // window text) before building the workflow so it can bias recognition and
        // gate command-mode correction. Cheap synchronous AX/NSWorkspace reads (ms)
        // — well under the server-warmup latency the mic-first ordering guards
        // against. OCR (opt-in) is merged from cache only; its refresh is async and
        // never blocks here. Transient: used to build this dictation, then dropped.
        let rawContext = settings.useContextAwareness ? await contextProvider.currentContext() : nil
        let context = enrichWithOCR(rawContext, settings: settings)

        // Start capturing audio FIRST so the first word isn't clipped. Server
        // warmup / backend linking only matter for the final pass (seconds
        // later), so they must not delay the mic. makeWorkflow is cheap (no I/O).
        let workflow = makeWorkflow(settings: settings, context: context)
        self.workflow = workflow

        do {
            try await workflow.beginRecording()
        } catch {
            isStarting = false
            self.workflow = nil
            self.recorder = nil
            if settings.showOverlay { overlayController.hide(after: 0) }
            fail(userFacingMessage(for: error))
            return
        }

        // beginRecording returns only once the mic is actually delivering audio
        // (it waits out the cold-start warmup), so "Listening" — the cue to speak —
        // appears only when audio is flowing. That's what keeps the first words
        // from being clipped on a cold first-of-day dictation.
        if settings.showOverlay {
            overlayController.showListening(
                detail: "",
                levelProvider: { [weak self] in self?.recorder?.currentLevel ?? 0 },
                onCommit: { [weak self] in Task { @MainActor in await self?.endHold() } },
                onCancel: { [weak self] in Task { @MainActor in await self?.cancelHold() } }
            )
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
            startPreviewLoop(recorder: recorder, settings: settings, context: context)
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

            // Build the correction record once: it becomes the last reviewable result
            // (Door #1 hotkey), the Learn-tab log entry, and the swap underlines on
            // the "Typed" card.
            var swappedRanges: [NSRange] = []
            var showPolishStreak = false
            if !transcript.isEmpty, let edits = workflow.lastTranscriptAndEdits {
                let record = CorrectionRecord(
                    raw: edits.raw,
                    prePolish: edits.prePolish,
                    inserted: edits.final,
                    segmentA: edits.segmentA,
                    segmentB: edits.segmentB,
                    polishOutcome: edits.polish
                )
                lastRecord = record
                showPolishStreak = recordPolishOutcome(edits.polish)
                // text only; gated on the privacy-respecting logCorrections toggle.
                if settings.logCorrections { CorrectionLogStore.append(record) }
                swappedRanges = validSwapRanges(in: transcript, edits: edits.segmentA + edits.segmentB)
            }

            if settings.showOverlay {
                if transcript.isEmpty {
                    overlayController.hide(after: 0.4)
                } else {
                    overlayController.showDone(text: transcript, swappedRanges: swappedRanges, polishStreak: showPolishStreak)
                    // Short un-hovered linger: the paste itself is the real
                    // confirmation. Hovering the overlay holds it open to read
                    // (OverlayController's cursor check), so the long dwell is
                    // opt-in instead of a flat tax on every dictation.
                    overlayController.hide(after: 1.0, holdWhileHovered: true)
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
        if let error = error as? AppleSpeechError { return error.userMessage }
        if let error = error as? AudioRecordingError { return error.description }
        return "Something went wrong. Please try again."
    }

    /// Derives Apple `contextualStrings` from the whisper-style prompt string:
    /// split on commas / newlines, keep short distinctive phrases. Same vocabulary
    /// source, different delivery (the analyzer wants a term list, not a sentence).
    private static func contextualStrings(from prompt: String?) -> [String] {
        guard let prompt, !prompt.isEmpty else { return [] }
        var seen = Set<String>()
        var terms: [String] = []
        for raw in prompt.split(whereSeparator: { $0 == "," || $0 == "\n" }) {
            let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = term.lowercased()
            guard term.count > 1, term.count <= 60, !seen.contains(key) else { continue }
            seen.insert(key)
            terms.append(term)
        }
        return Array(terms.prefix(300))
    }

    private func makeWorkflow(
        settings: AppSettingsSnapshot, context: DictationContext?, recorderOverride: AudioRecording? = nil
    ) -> DictationWorkflow {
        // The final pass prefers the resident server, waiting out a cold model
        // load rather than racing a cold CLI against it (which can fail). Only if
        // the server can't come up does it fall back to the per-call CLI.
        let prompt = contextPrompt(settings: settings, context: context)
        let transcriber: TranscriptionEngine
        if settings.engineKind == .apple, #available(macOS 26, *) {
            // In-process Apple SpeechAnalyzer — no resident server, no CLI. Vocab
            // bias travels as contextualStrings instead of the whisper prompt.
            transcriber = AppleSpeechEngine(
                localeID: settings.normalizedLanguage ?? "en-US",
                contextualStrings: Self.contextualStrings(from: prompt)
            )
        } else {
            // The final pass prefers the resident server, waiting out a cold model
            // load rather than racing a cold CLI against it (which can fail). Only
            // if the server can't come up does it fall back to the per-call CLI.
            transcriber = ResolvingTranscriptionEngine(
                serverManager: serverManager,
                configuration: makeConfiguration(settings: settings, timeoutSeconds: 60, prompt: prompt),
                language: settings.normalizedLanguage,
                timeoutSeconds: 60,
                serverWait: 30,
                prompt: prompt
            )
        }

        let inserter = makeInserter(settings: settings)

        // recorderOverride feeds a fixed WAV through the real pipeline (the
        // mic-less pipeline test); normal dictation creates the live recorder.
        let recorder: AudioRecording
        if let recorderOverride {
            recorder = recorderOverride
        } else {
            let live = AudioFileRecorder()
            self.recorder = live
            recorder = live
        }

        // Polish (when on) tidies formatting only — caps, punctuation, fillers.
        // Mishearing correction is handled deterministically (preCorrect below)
        // and by whisper's vocab bias, because the small model is unreliable at
        // word substitution (it swaps correct names for unrelated vocab terms).
        let polisher: TextPolishing? = settings.polishWithAI
            ? ServerBackedPolisher(serverManager: llamaManager, serverWait: 30)
            : nil

        // Deterministic known-mishearing fixes run before polish. Free and exact,
        // so they apply whenever any correction is on (cleanup or AI polish) — and
        // keep working even when the AI model is off or its server is unavailable.
        let wantsCorrection = settings.cleanUpTranscript || settings.polishWithAI
        // Context-scoped command mode (e.g. "me" -> "main" after `git push origin`)
        // runs right after the global-safe layer, gated on the focused app class
        // and caret text captured for THIS dictation. CommandModeCorrections.apply
        // is itself a no-op unless the composed line is a branch-taking git command,
        // so the substitution never touches prose — even in a terminal.
        let appClass = ContextBias.classify(appName: context?.activeApplicationName)
        let precedingText = context?.precedingText
        let commandMode = context != nil && appClass.allowsCommandMode
        // Built-in swaps the user has rejected in the Learn tab — skipped at apply time.
        let suppressed = SuppressionSet.decode(settings.rejectedBuiltInSwaps)
        // Candidates a mishearing may be corrected toward: the user's vocabulary
        // (custom + built-in defaults) plus the live on-screen context. Vocabulary
        // is the high-signal source the feature targets — brand/jargon terms like
        // "Vercel"/"Kubernetes" aren't identifier-shaped so they never surface as
        // on-screen candidates, and they're the canonical things to fix. Shared by
        // the deterministic phonetic snap and the experimental LLM substitution.
        let candidates = ContextBias.substitutionCandidates(
            customVocabulary: settings.customVocabulary,
            defaults: settings.useDefaultVocabulary ? DefaultVocabulary.terms : [],
            context: context.map { ContextBias.promptContext(for: $0) }
        )
        // Never snap in a terminal: a wrong swap there lands inside an executable
        // command, and the A/B corpus that proved 0-corruption had no command lines.
        let phoneticSnap = wantsCorrection && settings.phoneticSnapEnabled
            && !candidates.isEmpty && appClass != .terminal
        let preCorrect: (@Sendable (String) -> (String, [Edit]))? = (wantsCorrection || commandMode)
            ? { @Sendable text in
                var result = text
                var passes: [[Edit]] = []
                if wantsCorrection {
                    let (corrected, edits) = MishearingCorrections.applyTracked(to: result, suppressing: suppressed)
                    result = corrected
                    passes.append(edits)
                }
                if commandMode {
                    let (corrected, edits) = CommandModeCorrections.applyTracked(
                        to: result, appClass: appClass, precedingText: precedingText, suppressing: suppressed
                    )
                    result = corrected
                    passes.append(edits)
                }
                if phoneticSnap {
                    let (corrected, edits) = PhoneticSnapCorrections.applyTracked(
                        to: result, vocabulary: candidates, suppressing: suppressed
                    )
                    result = corrected
                    passes.append(edits)
                }
                // Fold the deterministic passes' edits into one list in the final
                // pre-polish (Segment A) coordinate space.
                return (result, EditFold.combine(passes))
            }
            : nil

        // Experimental context substitution: a constrained LLM swap toward
        // on-screen candidates, held in the countdown overlay for confirmation.
        // Shares the resident polish model. Reuses the SAME candidates whisper
        // is biased with (ContextBias), so swaps only target present terms.
        let ctxSubEnabled = settings.contextSubstitutionEnabled
        let countdown = settings.contextSubstitutionCountdown
        let confirmer = substitutionConfirmer
        let manager = llamaManager
        // Swaps the user has already rejected from a CONTEXT chip — never re-propose
        // them (keyed "<from> -> <to>", matching ReviewPanel.revertChange).
        let ctxSubSuppressed = SuppressionSet.decode(settings.rejectedContextSubSwaps)
        ctxSubDebugLog("makeWorkflow: ctxSubEnabled=\(ctxSubEnabled) candidates(\(candidates.count))=\(candidates.prefix(16).joined(separator: "|"))")
        let contextSubstitute: (@Sendable (String) async -> (String, [Edit]))? = (ctxSubEnabled && !candidates.isEmpty)
            ? { @Sendable text in
                ctxSubDebugLog("input=\(text.debugDescription)")
                guard SubstitutionPrefilter.worthCalling(transcript: text, candidates: candidates) else {
                    ctxSubDebugLog("prefilter: nothing candidate-like, skipping LLM")
                    return (text, [])
                }
                guard let baseURL = await manager.awaitReady(timeout: 30) else { ctxSubDebugLog("llama NOT ready"); return (text, []) }
                let engine = ContextSubstituteEngine(baseURL: baseURL, candidates: candidates)
                let swaps = await engine.proposals(for: text).filter {
                    !ctxSubSuppressed.contains("\($0.from) -> \($0.to)")
                }
                ctxSubDebugLog("proposals(\(swaps.count))=\(swaps.map { "\($0.from)->\($0.to)" }.joined(separator: "|"))")
                guard !swaps.isEmpty else { return (text, []) }
                let decision = await confirmer.confirm(text: text, swaps: swaps, countdown: countdown)
                switch decision {
                case .keepOriginal:
                    return (text, [])
                case .apply(let accepted):
                    guard !accepted.isEmpty else { return (text, []) }
                    let (corrected, edits) = ContextSubstitution.apply(accepted, to: text)
                    await MainActor.run { self.learnAcceptedTargets(accepted.map(\.to)) }
                    return (corrected, edits)
                }
            }
            : nil

        return DictationWorkflow(
            recorder: recorder,
            transcriber: transcriber,
            inserter: inserter,
            cleanupOptions: settings.cleanUpTranscript ? TranscriptCleaner.Options() : nil,
            preCorrect: preCorrect,
            contextSubstitute: contextSubstitute,
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

    private func textReplacementsTransform(settings: AppSettingsSnapshot) -> (@Sendable (String) -> (String, [Edit]))? {
        guard settings.useTextReplacements else { return nil }
        let rules = TextReplacements.parse(settings.textReplacements)
        guard !rules.isEmpty else { return nil }
        return { TextReplacements.applyTracked(rules, to: $0, source: .replacement) }
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

    /// Whisper context prompt from the user's vocabulary plus the live on-device
    /// context (focused app + caret-proximate text) when available, to bias
    /// recognition toward their own words and what they're typing into (fewer
    /// mishearings). Recognition is deliberately NOT biased from past transcripts —
    /// that's a feedback loop where one bad result poisons the next. Nil = none.
    private func contextPrompt(settings: AppSettingsSnapshot, context: DictationContext?) -> String? {
        let promptContext = context.map(ContextBias.promptContext(for:))
        let prompt = RecognitionContext.prompt(
            vocabulary: settings.customVocabulary,
            defaults: settings.useDefaultVocabulary ? DefaultVocabulary.terms : [],
            context: promptContext
        )
        return prompt.isEmpty ? nil : prompt
    }

    /// Opt-in OCR: always merge a fresh cached OCR of the focused window into the
    /// context (on TOP of any AX text), so on-screen terms bias recognition no
    /// matter how much the app exposed to Accessibility. Kicks off a throttled async
    /// refresh for next time. Never blocks the mic — the slow Vision pass runs in
    /// the background and only the (instant) cache read happens inline.
    private func enrichWithOCR(_ context: DictationContext?, settings: AppSettingsSnapshot) -> DictationContext? {
        // Skip entirely without permission so we never spawn a no-op OCR task.
        guard settings.useScreenOCR, ScreenOCR.hasPermission,
              var context, let app = context.activeApplicationName else { return context }
        let axText = context.visibleText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Merge cached OCR with the AX text so BOTH contribute on-screen candidates,
        // regardless of how much (or little) AX exposed.
        if let cache = ocrCache, cache.app == app, Date().timeIntervalSince(cache.at) < Self.ocrCacheTTL {
            context.visibleText = [axText, cache.text]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
        refreshOCR(for: app)
        return context
    }

    /// Refresh the OCR cache for `app` in the background, throttled so a quick run
    /// of dictations doesn't trigger repeated captures. At most one OCR in flight.
    private func refreshOCR(for app: String) {
        if let cache = ocrCache, cache.app == app, Date().timeIntervalSince(cache.at) < Self.ocrRefreshThrottle { return }
        guard ocrTask == nil else { return }
        ocrTask = Task { [weak self] in
            let text = await ScreenOCR.recognizeFocusedWindow()
            await MainActor.run {
                guard let self else { return }
                if let text { self.ocrCache = (app: app, text: text, at: Date()) }
                self.ocrTask = nil
            }
        }
    }

    /// Persist accepted swap targets to custom vocabulary so whisper biases
    /// toward them next time (the virtuous cycle). De-duped by the helper.
    private func learnAcceptedTargets(_ targets: [String]) {
        var vocab = UserDefaults.standard.string(forKey: AppSettingsKeys.customVocabulary) ?? ""
        for t in targets { vocab = CustomVocabulary.appending(t, to: vocab) }
        UserDefaults.standard.set(vocab, forKey: AppSettingsKeys.customVocabulary)
    }

    /// Fold this dictation's polish outcome into the persisted visibility counters
    /// (the readiness-strip lifetime tally) and the self-quieting first-run proof
    /// streak. Returns true when the HUD should show its one-time "Polished
    /// on-device" sub-line for THIS dictation — only for the first `streakLength`
    /// applied polishes against a given polish model (re-armed when the model
    /// path changes, including the first-ever run vs the empty default), then never.
    private func recordPolishOutcome(_ outcome: PolishOutcome?) -> Bool {
        let d = UserDefaults.standard
        func bump(_ key: String) { d.set(d.integer(forKey: key) + 1, forKey: key) }
        switch outcome {
        case .applied:
            bump(AppSettingsKeys.polishAppliedCount)
            // A model swap resets the streak so trust is rebuilt for the new model.
            let model = AppSettingsSnapshot.current.polishModelPath
            if d.string(forKey: AppSettingsKeys.polishProofModelPath) != model {
                d.set(0, forKey: AppSettingsKeys.polishProofShown)
                d.set(model, forKey: AppSettingsKeys.polishProofModelPath)
            }
            let shown = d.integer(forKey: AppSettingsKeys.polishProofShown)
            guard shown < PolishProof.streakLength else { return false }
            d.set(shown + 1, forKey: AppSettingsKeys.polishProofShown)
            return true
        case .guardRejected:
            bump(AppSettingsKeys.polishHeldBackCount)
            return false
        case .unchanged, .unavailable, .none:
            return false
        }
    }

    /// Persist the transcript to the user-facing history view (when enabled). This
    /// is display only — it is never fed back into recognition (see contextPrompt).
    private func recordHistory(_ transcript: String) {
        guard AppSettingsSnapshot.current.saveHistory else { return }
        TranscriptHistoryStore.append(transcript)
    }

    /// Open the review panel for the most recent dictation (Door #1 hotkey). No-op
    /// until a dictation has produced a record this session.
    func presentReview() {
        guard let lastRecord else { return }
        reviewPanelController.present(record: lastRecord)
    }

    /// Edit ranges that still line up with the displayed text — only swaps whose
    /// output span matches, so a polished/replaced string never gets a wrong
    /// underline (the polish wall: pre-polish ranges may not map to post-polish text).
    private func validSwapRanges(in text: String, edits: [Edit]) -> [NSRange] {
        let ns = text as NSString
        return edits.compactMap { edit in
            guard !edit.to.isEmpty,
                  edit.range.location >= 0,
                  edit.range.location + edit.range.length <= ns.length,
                  ns.substring(with: edit.range) == edit.to else { return nil }
            return edit.range
        }
    }

    /// Periodically transcribes the audio captured so far and shows it in the
    /// overlay, so the user sees a rolling preview instead of waiting for the
    /// final result. Partial text is lower quality than the final pass and may
    /// revise itself as more speech arrives.
    private func startPreviewLoop(recorder: AudioFileRecorder, settings: AppSettingsSnapshot, context: DictationContext?) {
        let language = settings.normalizedLanguage
        let prompt = contextPrompt(settings: settings, context: context)
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

                // Only refresh the preview when speech actually arrived recently.
                // During a silent hold the audio is near-silence and whisper
                // hallucinates *different* phantom phrases each pass — gating on
                // recent speech freezes the last preview instead of cycling.
                guard recorder.hadSpeechRecently(), let url = recorder.snapshotForPreview() else {
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
            overlayController.hide(after: 6, holdWhileHovered: true)
        } else if message.localizedCaseInsensitiveContains("accessibility") {
            overlayController.showError(message: message, actionTitle: "Open Settings") {
                PermissionStatus.openAccessibilitySettings()
            }
            overlayController.hide(after: 6, holdWhileHovered: true)
        } else if message.localizedCaseInsensitiveContains("model") || message.localizedCaseInsensitiveContains("whisper-cli") {
            overlayController.showError(message: message, actionTitle: "Open Settings") {
                Self.openAppSettings()
            }
            overlayController.hide(after: 6, holdWhileHovered: true)
        } else {
            overlayController.showError(message: message)
            overlayController.hide(after: 4, holdWhileHovered: true)
        }
    }

    private static func openAppSettings() {
        SettingsLauncher.open()
    }
}

private struct PreviewOnlyInserter: TextInserting {
    func insert(_ text: String) async throws {}
}

/// Test recorder that feeds a fixed WAV through the workflow instead of the mic.
/// `finishRecording` deletes the file it's handed (via defer), so each stop
/// returns a fresh copy of the source — the original survives repeated runs.
private final class FixedFileRecorder: AudioRecording, @unchecked Sendable {
    private let source: URL
    init(source: URL) { self.source = source }
    func startRecording() async throws {}
    func stopRecording() async throws -> URL {
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("ld-pipeline-\(UUID().uuidString).wav")
        try FileManager.default.copyItem(at: source, to: copy)
        return copy
    }
}

/// Polishes via the resident llama-server, waiting out a cold model load. If the
/// server isn't available it returns the text unchanged (LlamaPolishEngine also
/// falls back on any failure), so polish never blocks or corrupts insertion.
private struct ServerBackedPolisher: TextPolishing {
    let serverManager: ResidentServerManager
    let serverWait: TimeInterval

    func polish(_ text: String) async -> PolishOutcome {
        guard let baseURL = await serverManager.awaitReady(timeout: serverWait) else { return .unavailable(text) }
        return await LlamaPolishEngine(baseURL: baseURL).polish(text)
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

/// Diagnostic (env LD_CTXSUB_DEBUG): append a line to /tmp/ld-ctxsub-debug.log so a
/// mic smoke can see exactly what context substitution received (input + candidates)
/// and proposed — disambiguating "no overlay" between whisper-got-it-right (input
/// already correct → 0 proposals) and a real wiring gap. No-op unless the env var
/// is set, so production builds never touch the file. Free function (not actor-
/// isolated) so the off-main @Sendable substitution closure can call it directly.
func ctxSubDebugLog(_ line: String) {
    guard ProcessInfo.processInfo.environment["LD_CTXSUB_DEBUG"] != nil else { return }
    let entry = Data((line + "\n").utf8)
    let path = "/tmp/ld-ctxsub-debug.log"
    if let fh = FileHandle(forWritingAtPath: path) {
        defer { try? fh.close() }
        fh.seekToEndOfFile()
        fh.write(entry)
    } else {
        try? entry.write(to: URL(fileURLWithPath: path))
    }
}
