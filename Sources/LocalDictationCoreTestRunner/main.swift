import Foundation
import LocalDictationCore

@main
struct LocalDictationCoreTestRunner {
    static func main() async {
        runPhoneticParityIfRequested()
        var suite = TestSuite()
        await suite.run("Whisper parser prefers sidecar transcript", testWhisperParserPrefersSidecarTranscript)
        await suite.run("Whisper parser removes timestamps", testWhisperParserRemovesTimestamps)
        await suite.run("Whisper parser returns empty for logs", testWhisperParserReturnsEmptyForLogs)
        await suite.run("Whisper CLI rejects missing binary", testWhisperCLIRejectsMissingBinary)
        await suite.run("Whisper CLI rejects missing model", testWhisperCLIRejectsMissingModel)
        await suite.run("Whisper CLI rejects missing audio file", testWhisperCLIRejectsMissingAudioFile)
        await suite.run("Whisper CLI times out a hung process", testWhisperCLITimesOutHungProcess)
        await suite.run("TranscriptionError surfaces friendly localizedDescription", testTranscriptionErrorLocalizedDescription)
        await suite.run("Cleaner removes fillers + fixes caps/spacing", testTranscriptCleanerBasics)
        await suite.run("Cleaner preserves meaning + safe tokens", testTranscriptCleanerSafety)
        await suite.run("Dictation context + prompt biasing args", testDictationContext)
        await suite.run("Audio input follows the OS default (incl. Bluetooth)", testAudioInputFollowsOSDefault)
        await suite.run("Polish guardrail accepts faithful, rejects divergent", testPolishGuardrail)
        await suite.run("Polish preservesContentWords: rejects fabrication, allows fillers/ellipsis", testPolishPreservesContentWords)
        await suite.run("Polish request body + response parsing", testPolishRequestAndParsing)
        await suite.run("Whisper args omit language for auto/empty/nil", testWhisperArgsOmitLanguage)
        await suite.run("Whisper args clamp bad beam size", testWhisperArgsClampBeam)
        await suite.run("Whisper args add tuned VAD flags when model present", testWhisperArgsVADTuning)
        await suite.run("Audio peak-normalization boosts quiet, spares hot/silent, caps gain", testAudioPeakNormalization)
        await suite.run("Language migration: auto->en once, respects other choices", testLanguageDefaultMigration)
        await suite.run("Parser falls through whitespace-only sidecar", testParserWhitespaceSidecarFallsThrough)
        await suite.run("Parser filters ggml log lines", testParserFiltersGgmlLogs)
        await suite.run("Parser keeps annotations, insertion strips them", testParserKeepsAnnotationsButInsertionStrips)
        await suite.run("Server multipart body has required fields", testServerMultipartBody)
        await suite.run("Server multipart omits auto language", testServerMultipartOmitsAutoLanguage)
        await suite.run("Clipboard inserter restores previous value", testClipboardInserterRestoresPreviousValue)
        await suite.run("Clipboard inserter clears initially empty clipboard", testClipboardInserterClearsInitiallyEmptyClipboard)
        await suite.run("Clipboard inserter restores when paste command fails", testClipboardRestoresOnPasteFailure)
        await suite.run("Workflow records and pastes transcript", testWorkflowRecordsAndPastesTranscript)
        await suite.run("Workflow skips blank transcript", testWorkflowSkipsBlankTranscript)
        await suite.run("Workflow fails when recorder throws", testWorkflowRecorderThrows)
        await suite.run("Workflow fails when transcriber throws", testWorkflowTranscriberThrows)
        await suite.run("Workflow skips degenerate (too-short) recording", testWorkflowSkipsDegenerateRecording)
        await suite.run("Workflow cancel discards recording without inserting", testWorkflowCancelDiscardsRecording)
        await suite.run("Workflow surfaces corrected (post-polish) transcript, not raw", testWorkflowSurfacesCorrectedTranscript)
        await suite.run("Workflow pre-correct runs before polish", testWorkflowPreCorrectRunsBeforePolish)
        await suite.run("Mishearing corrections fix names, spare real words", testMishearingCorrections)
        await suite.run("App class classification + command-mode eligibility", testAppClassClassification)
        await suite.run("Context candidate extraction (identifiers, proximity, dedup)", testContextCandidates)
        await suite.run("Visible-window text → candidates → prompt (P3)", testVisibleTextCandidates)
        await suite.run("Command mode: me->main in command context, left alone in prose", testCommandModeCorrections)
        await suite.run("Recognition prompt folds in discrete context terms only (no raw preceding text)", testContextPrompt)
        await suite.run("Workflow command mode: terminal git push me -> main", testWorkflowCommandModeInsertsMain)
        await suite.run("Workflow prose: chat 'push to me' left alone", testWorkflowProseLeavesMeAlone)
        await suite.run("Workflow command mode survives prose cleanup (caps/period)", testWorkflowCommandModeWithCleanup)
        await suite.run("Polish prompt is formatting cleanup only", testPolishPromptCleansOnly)
        await suite.run("Text replacements parse + whole-word apply", testTextReplacements)
        await suite.run("Suppression set encode/decode/toggle/isSuppressed", testSuppressionSet)
        await suite.run("TextReplacements tracked: output-space edits + rebasing", testTextReplacementsEditTracking)
        await suite.run("Mishearing tracked: rules + clot edits, blood-clot spared", testMishearingEditTracking)
        await suite.run("Command mode tracked: me->main + formatting edits, gated", testCommandModeEditTracking)
        await suite.run("EditFold.combine folds chained passes into final space", testEditFoldCombine)
        await suite.run("RuleDerivation: revert identity + teach rule", testRuleDerivation)
        await suite.run("CorrectionLog: changeCount, codable, cap, pending", testCorrectionLog)
        await suite.run("BuiltInCorrections: stable identities match revert convention", testBuiltInCorrections)
        await suite.run("Apply path consults the suppression set", testSuppressionConsult)
        await suite.run("Span selection: grow/shrink/toggle/adjacent/separated", testSpanSelection)
        await suite.run("Insertion formatter handles mid-sentence continuation", testInsertionFormatter)
        await suite.run("Transcript history caps, skips blanks, searches", testTranscriptHistory)
        await suite.run("Keystroke inserter chunks UTF-16 correctly", testKeystrokeChunks)
        await suite.run("Recognition prompt merges default vocabulary", testDefaultVocabularyMerge)
        await suite.run("Custom vocabulary append dedups (case/space-insensitive)", testCustomVocabularyAppendDedup)
        await suite.run("TranscriptionError userMessage is jargon-free", testTranscriptionErrorUserMessage)
        await suite.run("HelperReaper matches bundle Helpers path only", testHelperReaperPathMatching)
        await suite.run("HelperReaper reaps orphan under Helpers dir, spares others", testHelperReaperReapsOrphanOnly)
        await suite.run("reapTracked kills only recorded live helpers (PID-reuse safe)", testReapTrackedKillsOnlyRecordedLiveHelpers)
        await suite.run("Edit.Source.contextSub round-trips", testEditSourceContextSubRoundTrips)
        await suite.run("guard accepts valid swap", testGuardAcceptsValidSwap)
        await suite.run("guard accepts compound fix", testGuardAcceptsCompoundFix)
        await suite.run("guard rejects off-list", testGuardRejectsOffList)
        await suite.run("guard rejects collapse", testGuardRejectsCollapse)
        await suite.run("guard rejects pure deletion", testGuardRejectsPureDeletion)
        await suite.run("guard candidate is case-insensitive", testGuardCaseInsensitiveCandidate)
        await suite.run("diff single swap", testDiffSingleSwap)
        await suite.run("diff compound swap", testDiffCompoundSwap)
        await suite.run("diff two swaps", testDiffTwoSwaps)
        await suite.run("diff no change", testDiffNoChange)
        await suite.run("diff ignores case-only tokens", testDiffIgnoresCaseOnlyTokens)
        await suite.run("apply single swap", testApplySingle)
        await suite.run("apply two swaps offsets", testApplyTwoSwapsOffsets)
        await suite.run("apply empty", testApplyEmpty)
        await suite.run("substitution request body shape", testRequestBodyShape)
        await suite.run("substitution parseContent", testParseContent)
        await suite.run("contextSubstitute folds into segmentA", testContextSubstituteFoldsIntoSegmentA)
        await suite.run("guard rejects non-candidate duplication", testGuardRejectsNonCandidateDuplication)
        await suite.run("guard rejects expansion", testGuardRejectsExpansion)
        await suite.run("diff handles NBSP whitespace", testDiffUnicodeWhitespace)
        await suite.run("CustomVocabulary.terms splits on comma + newline", testCustomVocabularyTerms)
        await suite.run("substitution candidates include custom vocab", testSubstitutionCandidatesCustomVocab)
        await suite.run("substitution candidates include defaults", testSubstitutionCandidatesDefaults)
        await suite.run("substitution candidates dedupe case-insensitively", testSubstitutionCandidatesDedupe)
        await suite.run("substitution candidates include on-screen context", testSubstitutionCandidatesOnScreen)
        await suite.run("substitution candidates cap at limit, vocab leads", testSubstitutionCandidatesCap)
        await suite.run("PolishOutcome.text returns the insertable text", testPolishOutcomeText)
        await suite.run("Polish outcome classification", testPolishOutcomeClassification)
        await suite.run("Workflow exposes the polish outcome", testWorkflowExposesPolishOutcome)
        await suite.run("Correction apply composes for the clipboard", testCorrectionApply)
        await suite.run("RecentRecordingsPrune.namesToPrune keeps newest, prunes oldest", testRecentRecordingsNamesToPrune)
        await suite.run("SubstitutionPrefilter fires on every in-scope mishearing", testPrefilterRecall)
        await suite.run("SubstitutionPrefilter skips candidate-free prose", testPrefilterSkips)
        await suite.run("SubstitutionPrefilter edge cases", testPrefilterEdgeCases)
        await suite.run("TailCapture stops early on silence, runs to cap on speech", testTailCapture)
        await suite.run("Metaphone.key matches the jellyfish reference fixture", testMetaphoneFixture)
        await suite.run("PhoneticSnap fixes non-word mangles toward vocabulary", testPhoneticSnapFixes)
        await suite.run("PhoneticSnap never touches real words or present terms", testPhoneticSnapGuards)
        await suite.run("PhoneticSnap preserves punctuation and tracks edits", testPhoneticSnapEditsAndPunctuation)
        await suite.run("Workflow preCorrect chain carries a phonetic snap to insertion", testPhoneticSnapThroughWorkflow)
        suite.finish()
    }
}

private func testCorrectionApply() throws {
    try expect(CorrectionApply.apply("Vue", for: "view", to: "build the view in view") == "build the Vue in view",
               "replaces only the first occurrence")
    let once = CorrectionApply.apply("Vercel", for: "versal", to: "deploy versal then post grass")
    try expect(CorrectionApply.apply("Postgres", for: "post grass", to: once) == "deploy Vercel then Postgres",
               "fixes compose onto the running text")
    try expect(CorrectionApply.apply("X", for: "missing", to: "abc") == "abc", "absent target → unchanged")
    try expect(CorrectionApply.apply("", for: "abc", to: "abc") == "abc", "empty replacement → unchanged")
}

private func testCustomVocabularyTerms() throws {
    let terms = CustomVocabulary.terms("Vercel, Kubernetes\nVue\n\n  Docker  ,")
    try expect(terms == ["Vercel", "Kubernetes", "Vue", "Docker"],
               "split on comma + newline, trimmed, empties dropped; got \(terms)")
    try expect(CustomVocabulary.terms("") == [], "empty list → no terms")
}

private func testSubstitutionCandidatesCustomVocab() throws {
    let c = ContextBias.substitutionCandidates(customVocabulary: "Vercel\nVue", defaults: [], context: nil)
    try expect(c.contains("Vercel") && c.contains("Vue"), "custom vocab terms must be candidates; got \(c)")
}

private func testSubstitutionCandidatesDefaults() throws {
    let c = ContextBias.substitutionCandidates(customVocabulary: "", defaults: ["Kubernetes", "Postgres"], context: nil)
    try expect(c.contains("Kubernetes") && c.contains("Postgres"), "built-in defaults must be candidates; got \(c)")
}

private func testSubstitutionCandidatesDedupe() throws {
    let c = ContextBias.substitutionCandidates(customVocabulary: "vercel", defaults: ["Vercel"], context: nil)
    try expect(c.filter { $0.lowercased() == "vercel" }.count == 1, "case-insensitive dedupe; got \(c)")
}

private func testSubstitutionCandidatesOnScreen() throws {
    let ctx = ContextBias.PromptContext(
        appVocabulary: ContextBias.vocabulary(for: .terminal),
        candidates: ["UserStore.swift", "feat/login"]
    )
    let c = ContextBias.substitutionCandidates(customVocabulary: "", defaults: [], context: ctx)
    try expect(c.contains("UserStore.swift") && c.contains("feat/login"), "on-screen candidates included; got \(c)")
    try expect(c.contains("git"), "app-class vocabulary included; got \(c)")
}

private func testSubstitutionCandidatesCap() throws {
    let ctx = ContextBias.PromptContext(candidates: (0..<50).map { "tok\($0)" })
    let c = ContextBias.substitutionCandidates(customVocabulary: "Vercel", defaults: ["Kubernetes"], context: ctx, limit: 5)
    try expect(c.count == 5, "capped at limit; got \(c.count)")
    try expect(c.first == "Vercel", "custom vocab leads so the cap preserves it; got \(c)")
    try expect(c.contains("Kubernetes"), "defaults precede on-screen tokens under the cap; got \(c)")
}

private func testHelperReaperPathMatching() throws {
    let dir = "/Applications/LocalDictation.app/Contents/Helpers"
    try expect(HelperProcessReaper.isBundledHelper(executablePath: dir + "/whisper-server", helpersDir: dir),
               "bundled whisper-server should match")
    try expect(HelperProcessReaper.isBundledHelper(executablePath: dir + "/llama-server", helpersDir: dir),
               "bundled llama-server should match")
    try expect(!HelperProcessReaper.isBundledHelper(executablePath: dir + "/whisper-cli", helpersDir: dir),
               "whisper-cli is not a server, must not match")
    try expect(!HelperProcessReaper.isBundledHelper(executablePath: "/opt/homebrew/bin/whisper-server", helpersDir: dir),
               "Homebrew whisper-server must never match")
    try expect(!HelperProcessReaper.isBundledHelper(executablePath: dir + "-evil/whisper-server", helpersDir: dir),
               "sibling dir with shared prefix must not match")
}

private func testHelperReaperReapsOrphanOnly() throws {
    let fm = FileManager.default
    let base = NSTemporaryDirectory() + "ld-reaper-\(getpid())"
    let helpers = base + "/Contents/Helpers"
    try fm.createDirectory(atPath: helpers, withIntermediateDirectories: true)
    defer { try? fm.removeItem(atPath: base) }

    let fakeHelper = helpers + "/whisper-server"
    try fm.copyItem(atPath: "/bin/sleep", toPath: fakeHelper)

    // The orphan: a "helper" living under our Helpers dir.
    let orphan = Process()
    orphan.executableURL = URL(fileURLWithPath: fakeHelper)
    orphan.arguments = ["30"]
    try orphan.run()
    // A control process that must survive — same binary, different path.
    let control = Process()
    control.executableURL = URL(fileURLWithPath: "/bin/sleep")
    control.arguments = ["30"]
    try control.run()
    defer { control.terminate() }

    // Poll until the orphan appears in proc_listpids (up to 2 s) to avoid a
    // race where the kernel hasn't yet added the freshly exec'd process.
    var orphans: [pid_t] = []
    for _ in 0..<8 {
        orphans = HelperProcessReaper.orphanPIDs(helpersDir: helpers)
        if orphans.contains(orphan.processIdentifier) { break }
        usleep(250_000)
    }
    try expect(orphans.contains(orphan.processIdentifier), "orphan helper should be detected")
    try expect(!orphans.contains(control.processIdentifier), "control /bin/sleep must not be detected")

    // `keeping` excludes a live PID even when it matches the path.
    let kept = HelperProcessReaper.orphanPIDs(helpersDir: helpers, keeping: [orphan.processIdentifier])
    try expect(!kept.contains(orphan.processIdentifier), "keeping should exclude our own child")

    HelperProcessReaper.reap(helpersDir: helpers)
    usleep(500_000)
    try expect(!orphan.isRunning, "orphan should be killed")
    try expect(control.isRunning, "control must still be running")
}

private func testReapTrackedKillsOnlyRecordedLiveHelpers() throws {
    let fm = FileManager.default
    let base = NSTemporaryDirectory() + "ld-reaptracked-\(getpid())"
    try fm.createDirectory(atPath: base, withIntermediateDirectories: true)
    defer { try? fm.removeItem(atPath: base) }

    // A fake helper whose basename is a known helper name, plus a control with a
    // NON-helper basename — both recorded, simulating a later recycled PID.
    let fakeHelper = base + "/whisper-server"
    try fm.copyItem(atPath: "/bin/sleep", toPath: fakeHelper)

    let helper = Process()
    helper.executableURL = URL(fileURLWithPath: fakeHelper)
    helper.arguments = ["30"]
    try helper.run()
    let control = Process()
    control.executableURL = URL(fileURLWithPath: "/bin/sleep")
    control.arguments = ["30"]
    try control.run()
    defer { helper.terminate(); control.terminate() }
    usleep(250_000)

    let pidFile = base + "/spawned.pids"
    HelperProcessReaper.recordSpawnedPID(helper.processIdentifier, toFile: pidFile)
    HelperProcessReaper.recordSpawnedPID(control.processIdentifier, toFile: pidFile)

    let killed = HelperProcessReaper.reapTracked(file: pidFile)
    usleep(500_000)
    try expect(killed.contains(helper.processIdentifier), "a recorded live helper must be reaped")
    try expect(!helper.isRunning, "the recorded helper should be killed")
    // The control is a recorded PID whose executable is NOT a helper (the PID-reuse
    // guard) — it must be spared even though it was recorded.
    try expect(!killed.contains(control.processIdentifier), "a recorded non-helper PID must not be reaped")
    try expect(control.isRunning, "control must still be running")
    let leftover = (try? String(contentsOfFile: pidFile, encoding: .utf8)) ?? ""
    try expect(leftover.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "pid file cleared after reaping")
}

private struct TestSuite {
    private var failures: [String] = []
    private var passed = 0

    mutating func run(_ name: String, _ test: () async throws -> Void) async {
        do {
            try await test()
            passed += 1
            print("PASS \(name)")
        } catch {
            failures.append("\(name): \(error)")
            print("FAIL \(name): \(error)")
        }
    }

    func finish() -> Never {
        if failures.isEmpty {
            print("All \(passed) tests passed.")
            exit(0)
        }

        print("\n\(failures.count) test failure(s):")
        for failure in failures {
            print("- \(failure)")
        }
        exit(1)
    }
}

private struct AssertionFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw AssertionFailure(description: message)
    }
}

private func testSpanSelection() throws {
    typealias S = SpanSelection
    // First tap selects a single word; tapping it again clears it.
    try expect(S.tap(current: nil, index: 2) == 2...2, "nil + tap 2 → 2…2")
    try expect(S.tap(current: 2...2, index: 2) == nil, "lone selected word tapped → clear")
    // Adjacent words grow the span; a separated word starts fresh.
    try expect(S.tap(current: 2...2, index: 3) == 2...3, "adjacent right → grow")
    try expect(S.tap(current: 2...3, index: 1) == 1...3, "adjacent left → grow")
    try expect(S.tap(current: 2...2, index: 5) == 5...5, "separated → fresh single")
    // Tapping a selected word toggles it off (shrink from the tapped end).
    try expect(S.tap(current: 2...3, index: 3) == 2...2, "tap end of 2-span → drop last")
    try expect(S.tap(current: 2...3, index: 2) == 3...3, "tap start of 2-span → drop first")
    try expect(S.tap(current: 0...2, index: 0) == 1...2, "tap start of 3-span → drop first")
    try expect(S.tap(current: 0...2, index: 2) == 0...1, "tap end of 3-span → drop last")
    // A middle tap collapses the selection to that single word.
    try expect(S.tap(current: 0...2, index: 1) == 1...1, "tap middle → collapse to word")
}

private func testWhisperParserPrefersSidecarTranscript() throws {
    let transcript = WhisperTranscriptParser.parse(
        standardOutput: "[00:00:00.000 --> 00:00:02.000] ignored",
        standardError: "",
        transcriptFileContents: " Hello from the model.\n"
    )

    try expect(transcript == "Hello from the model.", "Expected sidecar transcript, got \(transcript)")
}

private func testWhisperParserRemovesTimestamps() throws {
    let transcript = WhisperTranscriptParser.parse(
        standardOutput: """
        [00:00:00.000 --> 00:00:02.000] Hello there.
        [00:00:02.000 --> 00:00:04.000] This is local dictation.
        """,
        standardError: "",
        transcriptFileContents: nil
    )

    try expect(transcript == "Hello there. This is local dictation.", "Expected cleaned transcript, got \(transcript)")
}

private func testWhisperParserReturnsEmptyForLogs() throws {
    let transcript = WhisperTranscriptParser.parse(
        standardOutput: "whisper_init_from_file_with_params_no_state: loading model",
        standardError: "",
        transcriptFileContents: nil
    )

    try expect(transcript.isEmpty, "Expected empty transcript, got \(transcript)")
}

private func testWhisperCLIRejectsMissingBinary() async throws {
    let engine = WhisperCLITranscriptionEngine(
        configuration: .init(
            executablePath: "/tmp/local-dictation-missing-whisper-cli",
            modelPath: "/tmp/local-dictation-model.bin",
            language: nil
        )
    )

    do {
        _ = try await engine.transcribe(audioFile: URL(fileURLWithPath: "/tmp/audio.wav"))
        throw AssertionFailure(description: "Expected missing executable error.")
    } catch let error as TranscriptionError {
        try expect(error == .missingExecutable("/tmp/local-dictation-missing-whisper-cli"), "Unexpected error \(error)")
    }
}

private func testWhisperCLIRejectsMissingModel() async throws {
    let executable = try temporaryExecutable()
    let engine = WhisperCLITranscriptionEngine(
        configuration: .init(
            executablePath: executable.path,
            modelPath: "/tmp/local-dictation-missing-model.bin",
            language: "en"
        )
    )

    do {
        _ = try await engine.transcribe(audioFile: URL(fileURLWithPath: "/tmp/audio.wav"))
        throw AssertionFailure(description: "Expected missing model error.")
    } catch let error as TranscriptionError {
        try expect(error == .missingModel("/tmp/local-dictation-missing-model.bin"), "Unexpected error \(error)")
    }
}

private func testWhisperCLITimesOutHungProcess() async throws {
    let executable = try temporaryExecutable(body: "sleep 10\n")
    let model = FileManager.default.temporaryDirectory
        .appendingPathComponent("local-dictation-test-model-\(UUID().uuidString).bin")
    try "model".write(to: model, atomically: true, encoding: .utf8)
    let audio = FileManager.default.temporaryDirectory
        .appendingPathComponent("local-dictation-test-audio-\(UUID().uuidString).wav")
    try "audio".write(to: audio, atomically: true, encoding: .utf8)
    defer {
        try? FileManager.default.removeItem(at: model)
        try? FileManager.default.removeItem(at: audio)
    }

    let engine = WhisperCLITranscriptionEngine(
        configuration: .init(
            executablePath: executable.path,
            modelPath: model.path,
            language: nil,
            timeoutSeconds: 0.3
        )
    )

    do {
        _ = try await engine.transcribe(audioFile: audio)
        throw AssertionFailure(description: "Expected timeout error.")
    } catch let error as TranscriptionError {
        try expect(error == .timedOut(0.3), "Unexpected error \(error)")
    }
}

private func testWhisperCLIRejectsMissingAudioFile() async throws {
    let executable = try temporaryExecutable()
    let model = FileManager.default.temporaryDirectory
        .appendingPathComponent("local-dictation-test-model-\(UUID().uuidString).bin")
    try "model".write(to: model, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: model) }

    let engine = WhisperCLITranscriptionEngine(
        configuration: .init(executablePath: executable.path, modelPath: model.path, language: "en")
    )
    let missingAudio = "/tmp/local-dictation-missing-audio-\(UUID().uuidString).wav"

    do {
        _ = try await engine.transcribe(audioFile: URL(fileURLWithPath: missingAudio))
        throw AssertionFailure(description: "Expected missing audio file error.")
    } catch let error as TranscriptionError {
        try expect(error == .missingAudioFile(missingAudio), "Unexpected error \(error)")
    }
}

private func testTranscriptionErrorLocalizedDescription() throws {
    // Regression: the overlay showed "…(LocalDictationCore.TranscriptionError
    // error 3.)" because the enum wasn't a LocalizedError. localizedDescription
    // must carry the friendly text, not the bridged NSError fallback.
    let error = TranscriptionError.processFailed(2, "boom")
    try expect(
        error.localizedDescription == error.description,
        "localizedDescription should equal the friendly description, got \(error.localizedDescription)"
    )
    try expect(
        error.localizedDescription.contains("status 2") && error.localizedDescription.contains("boom"),
        "localizedDescription should include status + message, got \(error.localizedDescription)"
    )
    try expect(
        !error.localizedDescription.contains("couldn’t be completed"),
        "localizedDescription should not be the bridged NSError fallback"
    )
}

private func testPolishRequestAndParsing() throws {
    // Request body carries system prompt, the few-shot turns, and the transcript last.
    let body = TranscriptPolisher.chatRequestBody(transcript: "um hello there")
    let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    let messages = json?["messages"] as? [[String: String]] ?? []
    try expect(messages.first?["role"] == "system", "first message should be system")
    try expect(messages.last?["role"] == "user", "last message should be the user transcript")
    try expect(messages.last?["content"] == "um hello there", "last message should carry the transcript")
    try expect((json?["temperature"] as? Double) == 0, "temperature should be 0")
    try expect(messages.count == 10, "system + 4 few-shot pairs + transcript = 10 messages")

    // Response parsing pulls choices[0].message.content.
    let sample = Data(#"{"choices":[{"message":{"role":"assistant","content":"Hello there."}}]}"#.utf8)
    try expect(TranscriptPolisher.parseContent(sample) == "Hello there.", "should parse content")

    // Contractions fold so apostrophe styling isn't seen as new content.
    try expect(
        TranscriptPolisher.isFaithful(polished: "Don't be late.", original: "dont be late"),
        "contraction styling should stay faithful"
    )
}

private func testPolishGuardrail() throws {
    // Faithful: only mechanics/fillers changed → accept.
    try expect(
        TranscriptPolisher.isFaithful(polished: "Hello there.", original: "um hello there"),
        "should accept caps/punct + filler removal"
    )
    // The model answered the content instead of cleaning it → reject.
    try expect(
        !TranscriptPolisher.isFaithful(
            polished: "Sure, I can help you book a flight to Paris next week!",
            original: "book a flight"
        ),
        "should reject an answer/expansion"
    )
    // Translated/reworded into new words → reject.
    try expect(
        !TranscriptPolisher.isFaithful(polished: "Bonjour tout le monde", original: "hello everyone today"),
        "should reject a translation"
    )
    // Summarized away most of the text → reject.
    try expect(
        !TranscriptPolisher.isFaithful(
            polished: "Meeting moved.",
            original: "so the meeting that we had scheduled for tuesday has now been moved to thursday afternoon"
        ),
        "should reject a summary that drops most words"
    )
}

private func testPolishPreservesContentWords() throws {
    let ok = TranscriptPolisher.preservesContentWords

    // ACCEPT — pure reformat: filler + stutter removal, caps/punct.
    try expect(ok("The report is due Friday.", "um the the report is due friday"),
               "filler+stutter removal should pass")
    try expect(ok("So I was just testing the thing.", "so i i was just testing the thing you know"),
               "stutter + 'you know' removal should pass")
    // ACCEPT — clean text untouched.
    try expect(ok("Hello, how are you today?", "Hello, how are you today?"), "unchanged should pass")
    // ACCEPT — disfluency marked with an ellipsis, every word kept (… is punctuation).
    try expect(ok("So I was gonna… the thing with the… and then maybe we could, but…",
                  "so i was gonna the thing with the and then maybe we could but"),
               "ellipsis-marked, word-preserving output should pass")

    // REJECT — the actual fabrications observed from the live polish model.
    try expect(!ok("So I was going to do the thing, and then maybe we could.",
                   "so i was gonna the thing with the and then maybe we could but"),
               "added words ('going','do') + reword must be rejected")
    try expect(!ok("The I know every project, but we have not every.",
                   "the I know every project but we have there are not every"),
               "dropping real content ('there are') must be rejected")
    // REJECT — reordering and substitution.
    try expect(!ok("Sat the cat down.", "the cat sat down"), "reordering must be rejected")
    try expect(!ok("The dog sat down.", "the cat sat down"), "substitution ('cat'→'dog') must be rejected")
    // REJECT — empty polish on non-empty input.
    try expect(!ok("", "the cat sat"), "empty polish of real input must be rejected")
}

private func testDictationContext() throws {
    // prompt: vocabulary + optional history (a general capability the app no
    // longer feeds — see RecognitionContext), capped to maxChars.
    let p = RecognitionContext.prompt(vocabulary: "Nxabyte VAD Whisper", history: ["hello world"], maxChars: 100)
    try expect(p.contains("Nxabyte"), "prompt should include vocabulary")
    try expect(p.contains("hello world"), "prompt should include recent history")
    let capped = RecognitionContext.prompt(
        vocabulary: "", history: Array(repeating: "word word word word", count: 50), maxChars: 80
    )
    try expect(capped.count <= 80, "prompt should respect maxChars, got \(capped.count)")

    // CLI args carry --prompt when set.
    let cfg = WhisperCLIConfiguration(executablePath: "/x", modelPath: "/m", language: nil, prompt: "bias terms")
    let args = WhisperCLICommand.arguments(
        configuration: cfg, audioFile: URL(fileURLWithPath: "/a.wav"), outputBase: URL(fileURLWithPath: "/o")
    )
    guard let i = args.firstIndex(of: "--prompt") else {
        throw AssertionFailure(description: "args missing --prompt")
    }
    try expect(args[i + 1] == "bias terms", "prompt value should follow --prompt")
}

private struct StubInputDevice: AudioInputDeviceInfo {
    let deviceID: UInt32
    let uid: String
    let isBluetooth: Bool
    let isBuiltIn: Bool
}

private func testAudioInputFollowsOSDefault() throws {
    let builtIn = StubInputDevice(deviceID: 1, uid: "builtin", isBluetooth: false, isBuiltIn: true)
    let bt = StubInputDevice(deviceID: 2, uid: "buds", isBluetooth: true, isBuiltIn: false)

    // System Default → nil (record from the live OS default as-is), even when a
    // Bluetooth device is connected. Predictable; no auto-steering.
    try expect(
        AudioInputSelection.choose(uid: "", devices: [builtIn, bt]) == nil,
        "System Default must record from the live OS default, not steer around Bluetooth"
    )

    // Explicitly chosen device is honored — including Bluetooth (user asked for it).
    try expect(
        AudioInputSelection.choose(uid: "buds", devices: [builtIn, bt]) == 2,
        "an explicit Bluetooth choice must be respected"
    )
    try expect(
        AudioInputSelection.choose(uid: "builtin", devices: [builtIn, bt]) == 1,
        "an explicit built-in choice must be respected"
    )

    // Saved device no longer present → nil (fall back to the OS default).
    try expect(
        AudioInputSelection.choose(uid: "ghost", devices: [builtIn, bt]) == nil,
        "a missing saved device falls back to the OS default"
    )
}

private func testTranscriptCleanerBasics() throws {
    let cases: [(String, String)] = [
        ("Um, hello there.", "Hello there."),
        ("i think uh this works", "I think this works"),
        ("hello  world ,nice", "Hello world, nice"),
        ("first sentence. second one", "First sentence. Second one"),
        ("um uh um", ""),  // filler-only collapses to nothing
    ]
    for (input, expected) in cases {
        let got = TranscriptCleaner.clean(input)
        try expect(got == expected, "clean(\"\(input)\") == \"\(got)\", expected \"\(expected)\"")
    }
}

private func testTranscriptCleanerSafety() throws {
    // Meaning-preserving: never reorders or drops real words.
    try expect(
        TranscriptCleaner.clean("send it to jane not john") == "Send it to jane not john",
        "cleaner must not reword/reorder content"
    )
    // "mm" is millimetres here, not a filler — must survive.
    try expect(
        TranscriptCleaner.clean("the rain was 5 mm today") == "The rain was 5 mm today",
        "cleaner must not eat 'mm' (units)"
    )
    // Filler removal can be turned off.
    try expect(
        TranscriptCleaner.clean("um okay", options: .init(removeFillers: false)) == "Um okay",
        "removeFillers:false should keep fillers"
    )
}

private func testWhisperArgsOmitLanguage() throws {
    let audio = URL(fileURLWithPath: "/tmp/a.wav")
    let outputBase = URL(fileURLWithPath: "/tmp/out")
    for language in ["auto", "AUTO", "", "   ", nil] as [String?] {
        let args = WhisperCLICommand.arguments(
            configuration: .init(executablePath: "/x", modelPath: "/m", language: language),
            audioFile: audio, outputBase: outputBase
        )
        try expect(!args.contains("-l"), "Expected no -l for language \(language ?? "nil"), got \(args)")
    }
    let enArgs = WhisperCLICommand.arguments(
        configuration: .init(executablePath: "/x", modelPath: "/m", language: "en"),
        audioFile: audio, outputBase: outputBase
    )
    try expect(enArgs.contains("-l") && enArgs.contains("en"), "Expected -l en, got \(enArgs)")
}

private func testWhisperArgsClampBeam() throws {
    let audio = URL(fileURLWithPath: "/tmp/a.wav")
    let outputBase = URL(fileURLWithPath: "/tmp/out")
    let greedy = WhisperCLICommand.arguments(
        configuration: .init(executablePath: "/x", modelPath: "/m", language: nil, beamSize: 0),
        audioFile: audio, outputBase: outputBase
    )
    try expect(greedy.contains("-bs") && greedy.contains("1"), "Expected beam clamped to 1, got \(greedy)")
    let beam = WhisperCLICommand.arguments(
        configuration: .init(executablePath: "/x", modelPath: "/m", language: nil, beamSize: 4),
        audioFile: audio, outputBase: outputBase
    )
    let bsIndex = beam.firstIndex(of: "-bs")!
    try expect(beam[beam.index(after: bsIndex)] == "4", "Expected -bs 4, got \(beam)")
}

private func testWhisperArgsVADTuning() throws {
    let audio = URL(fileURLWithPath: "/tmp/a.wav")
    let outputBase = URL(fileURLWithPath: "/tmp/out")
    // No VAD model → no VAD flags at all.
    let noVad = WhisperCLICommand.arguments(
        configuration: .init(executablePath: "/x", modelPath: "/m", language: nil),
        audioFile: audio, outputBase: outputBase
    )
    try expect(!noVad.contains("--vad"), "Expected no --vad without a model, got \(noVad)")
    // With a VAD model → --vad -vm <path> followed by the dictation tuning flags.
    let withVad = WhisperCLICommand.arguments(
        configuration: .init(executablePath: "/x", modelPath: "/m", language: nil, vadModelPath: "/v/silero.bin"),
        audioFile: audio, outputBase: outputBase
    )
    try expect(withVad.contains("--vad") && withVad.contains("-vm"), "Expected --vad -vm, got \(withVad)")
    for flag in WhisperVAD.dictationTuningArguments {
        try expect(withVad.contains(flag), "Expected tuned VAD flag \(flag), got \(withVad)")
    }
    try expect(
        withVad.contains("200") && withVad.contains("100"),
        "Expected tuned VAD values 200/100, got \(withVad)"
    )
}

private func testCustomVocabularyAppendDedup() throws {
    try expect(CustomVocabulary.appending("Vercel", to: "") == "Vercel", "append to empty list")
    try expect(CustomVocabulary.appending("Supabase", to: "Vercel") == "Vercel\nSupabase", "new term appended newline-joined")
    try expect(CustomVocabulary.appending("Vercel", to: "Vercel") == "Vercel", "exact duplicate skipped")
    try expect(CustomVocabulary.appending("  vercel ", to: "Vercel\nSupabase") == "Vercel\nSupabase", "case/space-insensitive duplicate skipped")
    try expect(CustomVocabulary.appending("Vercel", to: "Vercel\r\nSupabase") == "Vercel\r\nSupabase", "CRLF list: existing term still deduped")
    try expect(CustomVocabulary.appending("   ", to: "Vercel") == "Vercel", "empty/whitespace term is a no-op")
    try expect(CustomVocabulary.appending("  Kubernetes ", to: "") == "Kubernetes", "term trimmed on insert")
}

private func testAudioPeakNormalization() throws {
    func peak(_ s: [Float]) -> Float { s.map(abs).max() ?? 0 }
    let approx: (Float, Float) -> Bool = { abs($0 - $1) < 1e-4 }

    // Quiet clip (peak 0.1) → scaled up to the 0.9 target.
    let quiet = AudioNormalizer.peakNormalized([0.1, -0.1, 0.05])
    try expect(approx(peak(quiet), 0.9), "Expected quiet clip boosted to ~0.9, got \(peak(quiet))")

    // Already hot (peak 0.8 ≥ 0.7) → untouched.
    let hot: [Float] = [0.8, -0.2, 0.4]
    try expect(AudioNormalizer.peakNormalized(hot) == hot, "Expected hot clip unchanged, got \(AudioNormalizer.peakNormalized(hot))")

    // Very quiet (peak 0.01) → gain capped at 30, so peak lands at 0.3, not 0.9.
    let capped = AudioNormalizer.peakNormalized([0.01, -0.01])
    try expect(approx(peak(capped), 0.3), "Expected capped boost to ~0.3, got \(peak(capped))")

    // Silence and empty → untouched.
    try expect(AudioNormalizer.peakNormalized([0, 0, 0]) == [0, 0, 0], "Expected silence unchanged")
    try expect(AudioNormalizer.peakNormalized([]) == [], "Expected empty unchanged")
}

private func testLanguageDefaultMigration() throws {
    try expect(
        LanguageDefaultMigration.migratedValue(stored: "auto", alreadyMigrated: false) == "en",
        "Legacy auto should migrate to en"
    )
    try expect(
        LanguageDefaultMigration.migratedValue(stored: "auto", alreadyMigrated: true) == nil,
        "Already-migrated auto must be left alone (respects a deliberate re-selection)"
    )
    for stored in ["en", "fr", "", nil] as [String?] {
        try expect(
            LanguageDefaultMigration.migratedValue(stored: stored, alreadyMigrated: false) == nil,
            "Non-auto choice \(stored ?? "nil") must be respected, not migrated"
        )
    }
}

private func testParserWhitespaceSidecarFallsThrough() throws {
    let transcript = WhisperTranscriptParser.parse(
        standardOutput: "[00:00:00.000 --> 00:00:02.000] From stdout.",
        standardError: "",
        transcriptFileContents: "   \n  "
    )
    try expect(transcript == "From stdout.", "Expected stdout fallthrough, got \(transcript)")
}

private func testParserFiltersGgmlLogs() throws {
    let transcript = WhisperTranscriptParser.parse(
        standardOutput: "ggml_metal_init: allocating",
        standardError: "",
        transcriptFileContents: nil
    )
    try expect(transcript.isEmpty, "Expected empty for ggml log, got \(transcript)")
}

private func testParserKeepsAnnotationsButInsertionStrips() throws {
    // Display keeps annotations…
    let shown = WhisperTranscriptParser.parse(standardOutput: "", standardError: "", transcriptFileContents: "Hello [BLANK_AUDIO] world.")
    try expect(shown == "Hello [BLANK_AUDIO] world.", "display should keep annotations, got \(shown)")
    // …but the inserted text strips them.
    try expect(WhisperTranscriptParser.strippedForInsertion("Hello [BLANK_AUDIO] world.") == "Hello world.", "inline annotation should be stripped for insertion")
    try expect(WhisperTranscriptParser.strippedForInsertion("[BLANK_AUDIO]").isEmpty, "whole-annotation should strip to empty")
    try expect(WhisperTranscriptParser.strippedForInsertion("( silence )").isEmpty, "parenthetical silence should strip to empty")
    try expect(WhisperTranscriptParser.strippedForInsertion("*whistling*").isEmpty, "asterisk annotation should strip to empty")
    // Bare punctuation from silence/noise inserts nothing.
    try expect(WhisperTranscriptParser.strippedForInsertion(".").isEmpty, "bare period should be empty")
    try expect(WhisperTranscriptParser.strippedForInsertion(". . .").isEmpty, "bare dots should be empty")
    try expect(WhisperTranscriptParser.strippedForInsertion("Hello world.") == "Hello world.", "real speech with a period should be kept")
}

private func testServerMultipartBody() throws {
    let body = WhisperServerTranscriptionEngine.multipartBody(boundary: "BND", audio: Data("RIFFxxxx".utf8), language: "en")
    let text = String(data: body, encoding: .utf8) ?? ""
    try expect(text.contains("name=\"file\"; filename=\"audio.wav\""), "missing file part")
    try expect(text.contains("name=\"response_format\"\r\n\r\njson"), "missing response_format")
    try expect(text.contains("name=\"language\"\r\n\r\nen"), "missing language en")
    try expect(text.hasSuffix("--BND--\r\n"), "missing closing boundary")
}

private func testServerMultipartOmitsAutoLanguage() throws {
    for language in ["auto", "", nil] as [String?] {
        let body = WhisperServerTranscriptionEngine.multipartBody(boundary: "B", audio: Data(), language: language)
        let text = String(data: body, encoding: .utf8) ?? ""
        try expect(!text.contains("name=\"language\""), "language should be omitted for \(language ?? "nil")")
    }
}

private func testClipboardRestoresOnPasteFailure() async throws {
    let pasteboard = InMemoryPasteboard(text: "important note")
    let sender = FailingPasteCommandSender()
    let inserter = ClipboardInserter(pasteboard: pasteboard, pasteCommandSender: sender)

    do {
        try await inserter.insert("dictated text")
        throw AssertionFailure(description: "Expected paste command to throw.")
    } catch is PasteInsertionError {
        try expect(pasteboard.currentText == "important note", "Clipboard not restored after failure: \(String(describing: pasteboard.currentText))")
    }
}

private func testWorkflowRecorderThrows() async throws {
    let workflow = DictationWorkflow(
        recorder: ThrowingRecorder(),
        transcriber: StubTranscriber(transcript: "x"),
        inserter: StubInserter()
    )
    do {
        try await workflow.beginRecording()
        throw AssertionFailure(description: "Expected recorder to throw.")
    } catch is StubError {
        guard case .failed = workflow.state else {
            throw AssertionFailure(description: "Expected failed state, got \(workflow.state)")
        }
    }
}

private func testWorkflowTranscriberThrows() async throws {
    let workflow = DictationWorkflow(
        recorder: StubRecorder(),
        transcriber: ThrowingTranscriber(),
        inserter: StubInserter()
    )
    try await workflow.beginRecording()
    do {
        try await workflow.finishRecording()
        throw AssertionFailure(description: "Expected transcriber to throw.")
    } catch is StubError {
        guard case .failed = workflow.state else {
            throw AssertionFailure(description: "Expected failed state, got \(workflow.state)")
        }
    }
}

private func testWorkflowSkipsDegenerateRecording() async throws {
    // A too-short tap produces a tiny/empty wav the server 400s on — the workflow
    // must skip transcription entirely and report no speech.
    let transcriber = StubTranscriber(transcript: "should not run")
    let inserter = StubInserter()
    let workflow = DictationWorkflow(recorder: TinyRecorder(), transcriber: transcriber, inserter: inserter)
    try await workflow.beginRecording()
    try await workflow.finishRecording()
    try expect(transcriber.audioFile == nil, "transcriber must not run on a degenerate recording")
    try expect(inserter.insertedText == nil, "nothing should be inserted for a degenerate recording")
}

private func testClipboardInserterRestoresPreviousValue() async throws {
    let pasteboard = InMemoryPasteboard(text: "previous")
    let sender = RecordingPasteCommandSender()
    let inserter = ClipboardInserter(pasteboard: pasteboard, pasteCommandSender: sender)

    try await inserter.insert("new transcript")

    try expect(sender.pasteCount == 1, "Expected one paste command.")
    try expect(pasteboard.currentText == "previous", "Expected previous clipboard to be restored.")
    try expect(pasteboard.writes == ["new transcript", "previous"], "Unexpected clipboard writes \(pasteboard.writes)")
}

private func testClipboardInserterClearsInitiallyEmptyClipboard() async throws {
    let pasteboard = InMemoryPasteboard(text: nil)
    let sender = RecordingPasteCommandSender()
    let inserter = ClipboardInserter(pasteboard: pasteboard, pasteCommandSender: sender)

    try await inserter.insert("new transcript")

    try expect(sender.pasteCount == 1, "Expected one paste command.")
    try expect(pasteboard.currentText == nil, "Expected clipboard to be empty after restore.")
}

private func testWorkflowRecordsAndPastesTranscript() async throws {
    let recorder = StubRecorder()
    let transcriber = StubTranscriber(transcript: "Hello workflow.")
    let inserter = StubInserter()
    let workflow = DictationWorkflow(
        recorder: recorder,
        transcriber: transcriber,
        inserter: inserter
    )

    try await workflow.beginRecording()
    try await workflow.finishRecording()

    try expect(workflow.state == .idle, "Expected idle state, got \(workflow.state)")
    try expect(recorder.didStart, "Expected recorder to start.")
    try expect(recorder.didStop, "Expected recorder to stop.")
    try expect(transcriber.audioFile == recorder.audioFile, "Expected transcriber to receive recorded file.")
    try expect(inserter.insertedText == "Hello workflow.", "Expected transcript insertion.")
}

private func testWorkflowSkipsBlankTranscript() async throws {
    let recorder = StubRecorder()
    let inserter = StubInserter()
    let workflow = DictationWorkflow(
        recorder: recorder,
        transcriber: StubTranscriber(transcript: "  "),
        inserter: inserter
    )

    try await workflow.beginRecording()
    try await workflow.finishRecording()

    try expect(workflow.state == .failed("No speech was detected."), "Expected no-speech failure, got \(workflow.state)")
    try expect(inserter.insertedText == nil, "Expected no text insertion.")
}

private func testWorkflowCancelDiscardsRecording() async throws {
    let recorder = StubRecorder()
    let transcriber = StubTranscriber(transcript: "should not run")
    let inserter = StubInserter()
    let workflow = DictationWorkflow(recorder: recorder, transcriber: transcriber, inserter: inserter)

    try await workflow.beginRecording()
    await workflow.cancelRecording()

    try expect(workflow.state == .cancelled, "Expected cancelled state, got \(workflow.state)")
    try expect(recorder.didStop, "Recorder should stop on cancel.")
    try expect(transcriber.audioFile == nil, "Transcriber must not run on cancel.")
    try expect(inserter.insertedText == nil, "Nothing should be inserted on cancel.")
    try expect(workflow.lastTranscript == nil, "No transcript should be kept on cancel.")

    // Cancel when not recording is a no-op (stays idle).
    let idle = DictationWorkflow(
        recorder: StubRecorder(), transcriber: StubTranscriber(transcript: "x"), inserter: StubInserter()
    )
    await idle.cancelRecording()
    try expect(idle.state == .idle, "Cancel when idle should be a no-op, got \(idle.state)")
}

private func testWorkflowSurfacesCorrectedTranscript() async throws {
    // The corrected (post-polish) text — not the raw transcript — must be what the
    // app surfaces via lastTranscript (history, menu bar, overlay). This was the
    // bug: "clot" showed everywhere even though "Claude" was what got typed.
    let inserter = StubInserter()
    let polisher = FakePolisher { .applied($0.replacingOccurrences(of: "clot", with: "Claude")) }
    let workflow = DictationWorkflow(
        recorder: StubRecorder(),
        transcriber: StubTranscriber(transcript: "I am coding with clot"),
        inserter: inserter,
        polisher: polisher
    )

    try await workflow.beginRecording()
    try await workflow.finishRecording()

    try expect(
        inserter.insertedText == "I am coding with Claude",
        "Expected polished text inserted, got \(inserter.insertedText ?? "nil")"
    )
    try expect(
        workflow.lastTranscript == "I am coding with Claude",
        "lastTranscript must be the corrected text, got \(workflow.lastTranscript ?? "nil")"
    )
}

private func testWorkflowPreCorrectRunsBeforePolish() async throws {
    // Deterministic mishearing fix must run before the polisher, so the polisher
    // receives the corrected term — not the raw mishearing it would mangle.
    let inserter = StubInserter()
    let polisher = FakePolisher { .unchanged($0) }  // identity: passes its input straight through
    let workflow = DictationWorkflow(
        recorder: StubRecorder(),
        transcriber: StubTranscriber(transcript: "ship it with clot today"),
        inserter: inserter,
        preCorrect: { MishearingCorrections.applyTracked(to: $0) },
        polisher: polisher
    )

    try await workflow.beginRecording()
    try await workflow.finishRecording()

    try expect(
        polisher.receivedInput == "ship it with Claude today",
        "polisher should receive deterministically-corrected text, got \(polisher.receivedInput ?? "nil")"
    )
    try expect(
        inserter.insertedText == "ship it with Claude today",
        "final inserted text should carry the correction, got \(inserter.insertedText ?? "nil")"
    )
}

private func testMishearingCorrections() throws {
    try expect(MishearingCorrections.apply(to: "I love using clot") == "I love using Claude", "clot -> Claude")
    try expect(MishearingCorrections.apply(to: "CLOT is great") == "Claude is great", "case-insensitive, replacement casing kept")
    try expect(MishearingCorrections.apply(to: "open cloud code now") == "open Claude Code now", "multi-word phrase corrected before single word")
    try expect(MishearingCorrections.apply(to: "claud and clawd") == "Claude and Claude", "claud / clawd variants")
    try expect(MishearingCorrections.apply(to: "the cloud cover today") == "the cloud cover today", "genuine 'cloud' is left alone")
    try expect(MishearingCorrections.apply(to: "clothing") == "clothing", "must not match inside a word")
    // Genuine "clot": "blood clot" is spared; bare "clot" still corrects; inflections untouched.
    try expect(MishearingCorrections.apply(to: "he has a blood clot") == "he has a blood clot", "'blood clot' kept literal")
    try expect(MishearingCorrections.apply(to: "Blood Clot risk") == "Blood Clot risk", "'blood clot' guard is case-insensitive")
    try expect(MishearingCorrections.apply(to: "ask clot about it") == "ask Claude about it", "bare 'clot' still corrects")
    try expect(MishearingCorrections.apply(to: "clots and clotting") == "clots and clotting", "inflected forms untouched")
}

private func testAppClassClassification() throws {
    try expect(ContextBias.classify(appName: "iTerm2") == .terminal, "iTerm2 → terminal")
    try expect(ContextBias.classify(appName: "Terminal") == .terminal, "Terminal → terminal")
    try expect(ContextBias.classify(appName: "Warp") == .terminal, "Warp → terminal")
    try expect(ContextBias.classify(appName: "Ghostty") == .terminal, "Ghostty → terminal")
    try expect(ContextBias.classify(appName: "Visual Studio Code") == .editor, "VS Code → editor")
    try expect(ContextBias.classify(appName: "Code") == .editor, "Code → editor")
    try expect(ContextBias.classify(appName: "Xcode") == .editor, "Xcode → editor")
    try expect(ContextBias.classify(appName: "Cursor") == .editor, "Cursor → editor")
    try expect(ContextBias.classify(appName: "Safari") == .browser, "Safari → browser")
    try expect(ContextBias.classify(appName: "Google Chrome") == .browser, "Chrome → browser")
    try expect(ContextBias.classify(appName: "Slack") == .chat, "Slack → chat")
    try expect(ContextBias.classify(appName: "Messages") == .chat, "Messages → chat")
    try expect(ContextBias.classify(appName: "Notes") == .notes, "Notes → notes")
    try expect(ContextBias.classify(appName: "Obsidian") == .notes, "Obsidian → notes")
    try expect(ContextBias.classify(appName: nil) == .unknown, "nil → unknown")
    try expect(ContextBias.classify(appName: "Spotify") == .unknown, "unrelated app → unknown")

    // Only shells/editors are eligible for command-mode substitution.
    try expect(ContextBias.AppClass.terminal.allowsCommandMode, "terminal allows command mode")
    try expect(ContextBias.AppClass.editor.allowsCommandMode, "editor allows command mode")
    try expect(!ContextBias.AppClass.chat.allowsCommandMode, "chat does not")
    try expect(!ContextBias.AppClass.notes.allowsCommandMode, "notes does not")
    try expect(!ContextBias.AppClass.browser.allowsCommandMode, "browser does not")
    try expect(!ContextBias.AppClass.unknown.allowsCommandMode, "unknown does not")

    // App-class vocabulary: dev terms for shells/editors, nothing for prose apps.
    try expect(ContextBias.vocabulary(for: .terminal).contains("main"), "terminal vocab has 'main'")
    try expect(ContextBias.vocabulary(for: .editor).contains("branch"), "editor vocab has 'branch'")
    try expect(ContextBias.vocabulary(for: .chat).isEmpty, "chat gets no jargon bias")
}

private func testContextCandidates() throws {
    // Identifier shapes are interesting; ordinary lowercase words are not.
    try expect(ContextBias.isInteresting("feat/context-aware"), "slash identifier is interesting")
    try expect(ContextBias.isInteresting("main.swift"), "filename is interesting")
    try expect(ContextBias.isInteresting("snake_case"), "underscore id is interesting")
    try expect(ContextBias.isInteresting("camelCase"), "camelCase is interesting")
    try expect(ContextBias.isInteresting("HEAD"), "ALLCAPS is interesting")
    try expect(ContextBias.isInteresting("v0.2.3"), "version is interesting")
    try expect(!ContextBias.isInteresting("the"), "ordinary word is not interesting")
    try expect(!ContextBias.isInteresting("origin"), "plain lowercase word is not interesting")
    try expect(!ContextBias.isInteresting("a"), "single char is not interesting")

    // Extraction: preceding-first proximity order, punctuation trimmed, deduped,
    // ordinary words dropped.
    let cands = ContextBias.candidates(
        precedingText: "git checkout feat/login,",
        visibleText: "On branch develop; see UserStore.swift and feat/login again"
    )
    try expect(cands.first == "feat/login", "preceding candidate leads, trailing comma trimmed")
    try expect(cands.contains("UserStore.swift"), "visible identifiers are extracted")
    try expect(cands.filter { $0.lowercased() == "feat/login" }.count == 1, "deduped across sources")
    try expect(!cands.contains("On") && !cands.contains("branch") && !cands.contains("develop"), "ordinary words excluded")
}

private func testVisibleTextCandidates() throws {
    // P3: AX window text (here, terminal-scrollback style) — branch names,
    // filenames, and identifiers are surfaced; ordinary prose is dropped. This is
    // what lets recognition lean toward on-screen terms even with no caret text.
    let scrollback = """
    ammiel@host project % git status
    On branch feature/login-v2
    Your branch is up to date with origin/main
    modified:   Sources/AppModel.swift
    nothing to commit, working tree clean
    """
    let cands = ContextBias.candidates(precedingText: nil, visibleText: scrollback)
    try expect(cands.contains("feature/login-v2"), "branch name extracted from window text")
    try expect(cands.contains(where: { $0.contains("AppModel.swift") }), "filename extracted")
    try expect(cands.contains(where: { $0.lowercased().contains("origin/main") }), "origin/main extracted")
    try expect(!cands.contains("branch") && !cands.contains("nothing"), "ordinary words excluded")

    // promptContext surfaces window-text candidates, and they reach the prompt.
    let ctx = ContextBias.promptContext(
        for: DictationContext(activeApplicationName: "Terminal", visibleText: scrollback)
    )
    try expect(ctx.candidates.contains("feature/login-v2"), "promptContext carries window-text candidates")
    let p = RecognitionContext.prompt(vocabulary: "", history: [], context: ctx)
    try expect(p.contains("feature/login-v2"), "window-text candidate reaches the whisper prompt")
}

private func testCommandModeCorrections() throws {
    // Command context = terminal/editor AND a branch-taking git command in the line.
    try expect(
        CommandModeCorrections.isCommandContext(appClass: .terminal, line: "git push origin me"),
        "terminal + git push is command context"
    )
    try expect(
        CommandModeCorrections.isCommandContext(appClass: .editor, line: "git checkout me"),
        "editor + git checkout is command context"
    )
    try expect(
        !CommandModeCorrections.isCommandContext(appClass: .chat, line: "git push origin me"),
        "chat is never command context, even with a git command"
    )
    try expect(
        !CommandModeCorrections.isCommandContext(appClass: .terminal, line: "git commit -m fix me"),
        "git commit is not a branch command (takes a message)"
    )
    try expect(
        !CommandModeCorrections.isCommandContext(appClass: .terminal, line: "tell me about it"),
        "a non-git line is not command context"
    )

    // THE fix — "me" -> "main" FIRES in command context.
    try expect(
        CommandModeCorrections.apply(to: "me", appClass: .terminal, precedingText: "git push origin ") == "main",
        "me -> main when preceding text is a git push"
    )
    try expect(
        CommandModeCorrections.apply(to: "git push origin me", appClass: .terminal, precedingText: nil) == "git push origin main",
        "whole dictated command: me -> main"
    )
    try expect(
        CommandModeCorrections.apply(to: "mane", appClass: .editor, precedingText: "git checkout ") == "main",
        "homophone 'mane' -> main"
    )
    // Command-aware formatting: lowercase a leading "Git", strip a trailing period.
    try expect(
        CommandModeCorrections.apply(to: "Git push origin me.", appClass: .terminal, precedingText: nil) == "git push origin main",
        "command formatting: lowercase Git + strip trailing period"
    )

    // git-homophone recovery: whisper mis-hears the command head "git" as "get"/"guit"
    // (observed in the A/B harness: "git checkout main" -> "get checkout main"). When
    // it heads an UNAMBIGUOUS git subcommand we recover it to "git".
    try expect(
        CommandModeCorrections.apply(to: "get checkout main", appClass: .terminal, precedingText: nil) == "git checkout main",
        "misheard 'get checkout' -> 'git checkout'"
    )
    try expect(
        CommandModeCorrections.apply(to: "guit rebase mane", appClass: .editor, precedingText: nil) == "git rebase main",
        "misheard 'guit rebase' + 'mane' -> 'git rebase main' (length-changing head fix)"
    )
    try expect(
        CommandModeCorrections.isCommandContext(appClass: .terminal, line: "get checkout main"),
        "'get checkout' is command context (misheard git)"
    )
    // But a misheard-git homophone before a PROSE-ambiguous word is left alone — we
    // never rewrite "get push notifications" into a git command.
    try expect(
        !CommandModeCorrections.isCommandContext(appClass: .terminal, line: "get push notifications working"),
        "'get push' prose is not command context"
    )
    try expect(
        CommandModeCorrections.apply(to: "get push notifications working", appClass: .terminal, precedingText: nil) == "get push notifications working",
        "'get push ...' prose is untouched"
    )

    // LEFT ALONE in prose context — the whole point of context-scoping.
    try expect(
        CommandModeCorrections.apply(to: "push to me", appClass: .chat, precedingText: "tell them to ") == "push to me",
        "prose 'push to me' is left alone in chat"
    )
    try expect(
        CommandModeCorrections.apply(to: "me", appClass: .notes, precedingText: "git push origin ") == "me",
        "notes is prose → left alone even with a git-like preceding line"
    )
    try expect(
        CommandModeCorrections.apply(to: "fix me", appClass: .terminal, precedingText: "git commit -m ") == "fix me",
        "terminal commit message 'fix me' left alone (commit isn't a branch command)"
    )
}

private func testContextPrompt() throws {
    let context = ContextBias.PromptContext(
        precedingText: "git push origin",
        appVocabulary: ContextBias.vocabulary(for: .terminal),
        candidates: ["feat/login", "UserStore.swift"]
    )
    let p = RecognitionContext.prompt(vocabulary: "Nxabyte", defaults: [], history: [], context: context, maxChars: 600)
    try expect(p.hasPrefix("Technical terms: Nxabyte"), "user vocabulary leads inside the framing")
    // Raw free-form preceding TEXT must NOT be folded into the whisper prompt — it
    // triggers previous-text-conditioning cutoffs/repetition. Only discrete terms.
    try expect(!p.contains("git push origin"), "raw preceding text is NOT folded into the prompt")
    try expect(p.contains("feat/login") && p.contains("UserStore.swift"), "candidates folded in")
    try expect(p.contains("main") && p.contains("branch"), "app-class vocabulary folded in")

    // No context → byte-identical to before (backward compatible).
    try expect(
        RecognitionContext.prompt(vocabulary: "X", history: [], context: nil) == "Technical terms: X.",
        "nil context → framed vocabulary only"
    )
    // Nothing to bias toward → empty prompt, never a bare "Technical terms: ." header.
    try expect(
        RecognitionContext.prompt(vocabulary: "", history: [], context: nil).isEmpty,
        "no terms → empty prompt, no dangling framing"
    )
    // Budget is respected even with context: an over-long preceding text is dropped
    // rather than blowing the cap.
    let capped = RecognitionContext.prompt(
        vocabulary: "", defaults: [], history: [],
        context: ContextBias.PromptContext(
            precedingText: String(repeating: "x", count: 500),
            appVocabulary: ContextBias.vocabulary(for: .terminal),
            candidates: []
        ),
        maxChars: 120
    )
    try expect(capped.count <= 120, "context prompt respects maxChars, got \(capped.count)")
}

/// Mirrors `AppModel.makeWorkflow`'s preCorrect: global-safe mishearing fixes, then
/// the context-gated command mode, with the two passes' edits folded into one
/// Segment-A list.
private func composedPreCorrect(
    _ appClass: ContextBias.AppClass, _ preceding: String?
) -> (@Sendable (String) -> (String, [Edit])) {
    { text in
        let (afterMishearing, mishearingEdits) = MishearingCorrections.applyTracked(to: text)
        let (afterCommand, commandEdits) = CommandModeCorrections.applyTracked(
            to: afterMishearing, appClass: appClass, precedingText: preceding
        )
        return (afterCommand, EditFold.combine([mishearingEdits, commandEdits]))
    }
}

private func testWorkflowCommandModeInsertsMain() async throws {
    // Mirrors AppModel's preCorrect composition: global-safe fixes, then the
    // context-gated command mode. In a terminal after `git push origin`, the
    // misheard "me" must be inserted as "main".
    let inserter = StubInserter()
    let workflow = DictationWorkflow(
        recorder: StubRecorder(),
        transcriber: StubTranscriber(transcript: "me"),
        inserter: inserter,
        preCorrect: composedPreCorrect(.terminal, "git push origin ")
    )
    try await workflow.beginRecording()
    try await workflow.finishRecording()
    try expect(inserter.insertedText == "main", "terminal git push: me -> main, got \(inserter.insertedText ?? "nil")")
    // The whole P1 chain: the swap surfaces as a Segment-A edit on the workflow.
    let edits = workflow.lastTranscriptAndEdits
    try expect(
        edits?.segmentA.contains { $0.to == "main" && $0.from.lowercased() == "me" && $0.source == .command } == true,
        "segmentA carries the me->main command edit"
    )
    try expect(edits?.final == "main", "final text recorded")
}

private func testWorkflowProseLeavesMeAlone() async throws {
    // Same composition, but in Slack (chat) — command mode must NOT fire, so the
    // exact same words are inserted unchanged.
    let inserter = StubInserter()
    let workflow = DictationWorkflow(
        recorder: StubRecorder(),
        transcriber: StubTranscriber(transcript: "push to me"),
        inserter: inserter,
        preCorrect: composedPreCorrect(.chat, "tell them to ")
    )
    try await workflow.beginRecording()
    try await workflow.finishRecording()
    try expect(inserter.insertedText == "push to me", "chat prose left alone, got \(inserter.insertedText ?? "nil")")
}

private func testWorkflowCommandModeWithCleanup() async throws {
    // With prose cleanup ON (it capitalizes the first word), command mode must
    // still produce a clean shell command — "git push origin main", not
    // "Git push origin main".
    let inserter = StubInserter()
    let workflow = DictationWorkflow(
        recorder: StubRecorder(),
        transcriber: StubTranscriber(transcript: "git push origin me"),
        inserter: inserter,
        cleanupOptions: TranscriptCleaner.Options(),
        preCorrect: composedPreCorrect(.terminal, nil)
    )
    try await workflow.beginRecording()
    try await workflow.finishRecording()
    try expect(
        inserter.insertedText == "git push origin main",
        "cleanup + command mode → git push origin main, got \(inserter.insertedText ?? "nil")"
    )
}

private func testPolishPromptCleansOnly() throws {
    // The polish pass is formatting-only: it must tidy caps/punctuation/fillers and
    // explicitly forbid word substitution (mishearings are handled before polish).
    let prompt = TranscriptPolisher.systemPrompt()
    try expect(prompt.localizedCaseInsensitiveContains("capitalization"), "cleanup prompt should mention capitalization")
    try expect(prompt.localizedCaseInsensitiveContains("filler"), "cleanup prompt should mention fillers")
    try expect(prompt.localizedCaseInsensitiveContains("substitute"), "cleanup prompt should forbid substitution explicitly")
    try expect(!prompt.localizedCaseInsensitiveContains("known terms"), "no vocabulary/known-terms block in cleanup prompt")
    try expect(!prompt.contains("REPLACE it"), "cleanup prompt must not license replacing words")

    let body = TranscriptPolisher.chatRequestBody(transcript: "hi")
    let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    let msgs = json?["messages"] as? [[String: String]] ?? []
    try expect(msgs.count == 10, "system + 4 few-shot pairs + transcript = 10, got \(msgs.count)")
}

private func testTextReplacements() throws {
    let list = """
    # comment ignored
    teh => the
    btw = by the way
    my address => 12 Oak Street

    """
    let rules = TextReplacements.parse(list)
    try expect(rules.count == 3, "3 rules parsed (comment + blank ignored), got \(rules.count)")
    try expect(
        TextReplacements.apply(rules, to: "send teh file btw") == "send the file by the way",
        "whole-word replacement"
    )
    try expect(
        TextReplacements.apply(rules, to: "BTW hello") == "by the way hello",
        "case-insensitive match, replacement casing kept"
    )
    try expect(
        TextReplacements.applying(list, to: "my address is here") == "12 Oak Street is here",
        "phrase trigger expands"
    )
    try expect(TextReplacements.apply(rules, to: "theory") == "theory", "must not replace inside a word")
    // serialize round-trips through parse (the Learn-tab structured editor relies on this).
    try expect(TextReplacements.parse(TextReplacements.serialize(rules)) == rules, "serialize -> parse round-trips")
}

private func testSuppressionSet() throws {
    // Blank / invalid JSON decode to an empty set (never throws into the pipeline).
    try expect(SuppressionSet.decode("") == [], "blank decodes to empty")
    try expect(SuppressionSet.decode("{not json") == [], "invalid decodes to empty")
    try expect(
        !SuppressionSet.isSuppressed("mishearing:clot→Claude", in: ""),
        "nothing suppressed when the set is empty"
    )

    // encode → decode round-trips the identity set.
    let ids: Set<String> = ["mishearing:clot→Claude", "command:me→main"]
    let json = SuppressionSet.encode(ids)
    try expect(SuppressionSet.decode(json) == ids, "encode/decode round-trips")
    try expect(
        SuppressionSet.isSuppressed("command:me→main", in: json),
        "a member identity reads back as suppressed"
    )

    // toggling on adds, off removes; both re-encode to a stable string.
    let added = SuppressionSet.toggling("mishearing:cloud-code", in: json, on: true)
    try expect(SuppressionSet.isSuppressed("mishearing:cloud-code", in: added), "toggle on adds")
    let removed = SuppressionSet.toggling("command:me→main", in: added, on: false)
    try expect(!SuppressionSet.isSuppressed("command:me→main", in: removed), "toggle off removes")
    try expect(SuppressionSet.isSuppressed("mishearing:cloud-code", in: removed), "toggle off spares others")
}

private func testTextReplacementsEditTracking() throws {
    let rules = TextReplacements.parse("teh => the\nclot => Claude")
    let (out, edits) = TextReplacements.applyTracked(rules, to: "teh clot here", source: .replacement)
    try expect(out == "the Claude here", "tracked output equals apply(): got \(out)")
    try expect(out == TextReplacements.apply(rules, to: "teh clot here"), "apply() delegates to applyTracked")
    let sorted = edits.sorted { $0.range.location < $1.range.location }
    try expect(sorted.count == 2, "two edits, got \(sorted.count)")
    try expect(sorted[0].from == "teh" && sorted[0].to == "the" && sorted[0].source == .replacement, "edit 0 text+source")
    try expect(sorted[0].range.location == 0 && sorted[0].range.length == 3, "edit 0 output range 0..3, got \(sorted[0].range)")
    try expect(sorted[1].from == "clot" && sorted[1].to == "Claude", "edit 1 text")
    try expect(sorted[1].range.location == 4 && sorted[1].range.length == 6, "edit 1 output range 4..10, got \(sorted[1].range)")

    // A length-changing earlier replacement rebases a later edit's output range forward.
    let r2 = TextReplacements.parse("c => dddd\na => bb")
    let (out2, edits2) = TextReplacements.applyTracked(r2, to: "c a", source: .replacement)
    try expect(out2 == "dddd bb", "rebase output: got \(out2)")
    let s2 = edits2.sorted { $0.range.location < $1.range.location }
    try expect(s2[0].to == "dddd" && s2[0].range.location == 0 && s2[0].range.length == 4, "c->dddd at 0..4")
    try expect(s2[1].to == "bb" && s2[1].range.location == 5 && s2[1].range.length == 2, "a->bb rebased to 5..7, got \(s2[1].range)")

    // UTF-16 surrogate: a swap after an emoji must count the emoji's two code units,
    // so the edit range lands correctly past it (never splits the surrogate pair).
    let r3 = TextReplacements.parse("clot => Claude")
    let (out3, edits3) = TextReplacements.applyTracked(r3, to: "😀 clot", source: .mishearing)
    try expect(out3 == "😀 Claude", "emoji preserved: \(out3)")
    try expect(edits3.count == 1, "one edit, got \(edits3.count)")
    try expect((out3 as NSString).substring(with: edits3[0].range) == "Claude", "range maps past the surrogate pair")
    try expect(edits3[0].range.location == 3, "Claude at UTF-16 loc 3 (emoji 2 + space 1), got \(edits3[0].range.location)")
}

private func testMishearingEditTracking() throws {
    // Rules path: "cloud code" -> "Claude Code", tagged .mishearing, range maps to output.
    let (o1, e1) = MishearingCorrections.applyTracked(to: "open cloud code now")
    try expect(o1 == "open Claude Code now", "rules output: \(o1)")
    try expect(o1 == MishearingCorrections.apply(to: "open cloud code now"), "apply() delegates to applyTracked")
    let m1 = e1.first { $0.to == "Claude Code" }
    try expect(m1 != nil && m1!.source == .mishearing, "cloud-code edit tagged .mishearing")
    try expect(m1!.from == "cloud code", "from = heard text")
    try expect((o1 as NSString).substring(with: m1!.range) == "Claude Code", "range points at the output span")

    // correctClot path emits its own edit (not routed through the rules).
    let (o2, e2) = MishearingCorrections.applyTracked(to: "ask clot please")
    try expect(o2 == "ask Claude please", "clot output: \(o2)")
    let c2 = e2.first { $0.from.lowercased() == "clot" }
    try expect(c2 != nil && c2!.to == "Claude" && c2!.source == .mishearing, "clot edit present")
    try expect((o2 as NSString).substring(with: c2!.range) == "Claude", "clot range maps to output")

    // "blood clot" is spared (negative lookbehind) — no edits at all.
    let (o3, e3) = MishearingCorrections.applyTracked(to: "a blood clot here")
    try expect(o3 == "a blood clot here", "blood clot spared: \(o3)")
    try expect(e3.isEmpty, "no edits when nothing changed, got \(e3.count)")
}

private func testCommandModeEditTracking() throws {
    let terminal = ContextBias.classify(appName: "Terminal")

    // In command context: "me" -> "main", tagged .command, range maps to output.
    let (o, e) = CommandModeCorrections.applyTracked(to: "me", appClass: terminal, precedingText: "git push origin")
    try expect(o == "main", "command output: \(o)")
    try expect(
        o == CommandModeCorrections.apply(to: "me", appClass: terminal, precedingText: "git push origin"),
        "apply() delegates to applyTracked"
    )
    let me = e.first { $0.from.lowercased() == "me" && $0.to == "main" }
    try expect(me != nil && me!.source == .command, "me->main edit tagged .command")
    try expect((o as NSString).substring(with: me!.range) == "main", "range maps to output span")

    // commandFormatting emits a period-strip edit (to == "").
    let (o2, e2) = CommandModeCorrections.applyTracked(to: "push origin me.", appClass: terminal, precedingText: "git")
    try expect(o2 == "push origin main", "me->main + trailing period stripped: \(o2)")
    try expect(e2.contains { $0.from == "." && $0.to == "" && $0.source == .command }, "period-strip edit present")

    // Gated: terminal app but no git command in the line → untouched, no edits.
    let (o3, e3) = CommandModeCorrections.applyTracked(to: "remind me", appClass: terminal, precedingText: "please")
    try expect(o3 == "remind me" && e3.isEmpty, "no git command -> untouched, no edits")

    // git-homophone head fix is tracked; the length-changing "guit"->"git" (-1) must
    // rebase the later "mane"->"main" edit so its range still maps to the output.
    let (o4, e4) = CommandModeCorrections.applyTracked(to: "guit checkout mane", appClass: terminal, precedingText: nil)
    try expect(o4 == "git checkout main", "guit->git + mane->main: \(o4)")
    try expect(e4.contains { $0.from.lowercased() == "guit" && $0.to == "git" && $0.source == .command }, "guit->git edit present")
    let mainEdit = e4.first { $0.to == "main" }
    try expect(mainEdit != nil && (o4 as NSString).substring(with: mainEdit!.range) == "main", "main edit range maps to output after head shift")
}

private func testEditFoldCombine() throws {
    // Pass 1 runs on "c a": a -> bb  (=> "c bb", the edit is AFTER c).
    let (s1, p1) = TextReplacements.applyTracked(TextReplacements.parse("a => bb"), to: "c a", source: .mishearing)
    try expect(s1 == "c bb", "pass1 output: \(s1)")
    // Pass 2 runs on "c bb": c -> dddd  (=> "dddd bb", shifts the pass-1 edit forward).
    let (s2, p2) = TextReplacements.applyTracked(TextReplacements.parse("c => dddd"), to: s1, source: .command)
    try expect(s2 == "dddd bb", "pass2 output: \(s2)")

    let folded = EditFold.combine([p1, p2]).sorted { $0.location < $1.location }
    try expect(folded.count == 2, "two folded edits, got \(folded.count)")
    // Both ranges must be valid in the FINAL string after the fold rebases pass 1.
    try expect((s2 as NSString).substring(with: folded[0].range) == "dddd", "c->dddd valid in final")
    try expect((s2 as NSString).substring(with: folded[1].range) == "bb", "a->bb rebased valid in final, got loc \(folded[1].range.location)")
    try expect(folded[1].range.location == 5, "a->bb shifted +3 by earlier c->dddd, got \(folded[1].range.location)")

    // Empty / single pass are identities.
    try expect(EditFold.combine([]).isEmpty, "empty chain -> no edits")
    try expect(EditFold.combine([p1]).count == 1, "single pass passes through")
}

private func testRuleDerivation() throws {
    // Built-in swap edit -> a suppression identity, symmetric on heard casing.
    let clot = Edit(location: 4, length: 6, from: "Clot", to: "Claude", source: .mishearing)
    try expect(
        RuleDerivation.suppressionIdentity(for: clot) == "mishearing:clot→Claude",
        "mishearing identity lowercases heard text"
    )
    let me = Edit(location: 0, length: 4, from: "me", to: "main", source: .command)
    try expect(RuleDerivation.suppressionIdentity(for: me) == "command:me→main", "command identity")

    // User replacement + zero-length edits have no suppression identity.
    let user = Edit(location: 0, length: 3, from: "teh", to: "the", source: .replacement)
    try expect(RuleDerivation.suppressionIdentity(for: user) == nil, "user replacement isn't suppressible")
    let strip = Edit(location: 0, length: 0, from: ".", to: "", source: .command)
    try expect(RuleDerivation.suppressionIdentity(for: strip) == nil, "empty-to edit has no identity")

    // Teach turns a heard span + correction into a rule; blank/no-op -> nil.
    let rule = RuleDerivation.teach(heard: "vad", correction: "VAD")
    try expect(rule?.pattern == "vad" && rule?.replacement == "VAD", "teach builds heard->correction rule")
    try expect(RuleDerivation.teach(heard: "vad", correction: "  ") == nil, "blank correction -> nil")
    try expect(RuleDerivation.teach(heard: "the", correction: "the") == nil, "no-op correction -> nil")
}

private func testCorrectionLog() throws {
    let edit = Edit(location: 4, length: 6, from: "clot", to: "Claude", source: .mishearing)
    let rec = CorrectionRecord(
        raw: "ask clot", prePolish: "ask Claude", inserted: "ask Claude",
        segmentA: [edit], segmentB: [], date: Date(timeIntervalSince1970: 100)
    )
    try expect(rec.changeCount == 1, "changeCount = segmentA + segmentB, got \(rec.changeCount)")

    // Codable round-trip preserves the attributed edits.
    let data = try JSONEncoder().encode(rec)
    let back = try JSONDecoder().decode(CorrectionRecord.self, from: data)
    try expect(back == rec, "record round-trips through JSON")
    try expect(back.segmentA.first?.to == "Claude", "edit survives encode/decode")

    // append caps at maxEntries, dropping the oldest.
    var records: [CorrectionRecord] = []
    for i in 0..<205 {
        let r = CorrectionRecord(
            raw: "r\(i)", prePolish: "r\(i)", inserted: "r\(i)",
            segmentA: [], segmentB: [], date: Date(timeIntervalSince1970: Double(i))
        )
        records = CorrectionLog.appending(r, to: records)
    }
    try expect(records.count == 200, "capped at 200, got \(records.count)")
    try expect(records.first?.raw == "r5", "oldest dropped, got \(records.first?.raw ?? "nil")")

    // pending = records with a change, newest first.
    let changed = CorrectionRecord(
        raw: "x", prePolish: "y", inserted: "y", segmentA: [edit], segmentB: [],
        date: Date(timeIntervalSince1970: 9999)
    )
    let pending = CorrectionLog.pending(CorrectionLog.appending(changed, to: records))
    try expect(pending.first?.raw == "x", "pending newest-first, got \(pending.first?.raw ?? "nil")")
    try expect(pending.allSatisfy { $0.changeCount > 0 }, "pending holds only changed records")
}

private func testBuiltInCorrections() throws {
    let all = BuiltInCorrections.all
    try expect(all.contains { $0.identity == "mishearing:clot→Claude" }, "clot built-in present")
    try expect(all.contains { $0.from == "cloud code" && $0.to == "Claude Code" }, "cloud code present")
    try expect(all.contains { $0.identity == "command:me→main" && $0.source == .command }, "me->main present")
    try expect(all.allSatisfy { !$0.identity.isEmpty }, "every built-in has a stable identity")
    // The list's identity must equal what a reverted edit produces, so a built-in
    // toggled off in the Learn tab actually matches at apply time.
    let me = Edit(location: 0, length: 4, from: "Me", to: "main", source: .command)
    try expect(
        all.contains { $0.identity == RuleDerivation.suppressionIdentity(for: me) },
        "built-in identity matches the revert/suppression convention"
    )
}

private func testSuppressionConsult() throws {
    // Mishearing: clot fires by default; suppressing its identity skips it; others stay.
    try expect(MishearingCorrections.applyTracked(to: "ask clot").0 == "ask Claude", "clot fires by default")
    let suppressed: Set<String> = ["mishearing:clot→Claude"]
    let (o, e) = MishearingCorrections.applyTracked(to: "ask clot", suppressing: suppressed)
    try expect(o == "ask clot", "suppressed clot is not applied, got \(o)")
    try expect(e.isEmpty, "no edit emitted when suppressed")
    try expect(
        MishearingCorrections.applyTracked(to: "open cloud code", suppressing: suppressed).0 == "open Claude Code",
        "a non-suppressed rule still fires"
    )

    // Command: me->main fires by default; suppressing its identity leaves it alone.
    let term = ContextBias.classify(appName: "Terminal")
    try expect(
        CommandModeCorrections.applyTracked(to: "me", appClass: term, precedingText: "git push origin").0 == "main",
        "me->main fires by default"
    )
    let cmdSuppressed: Set<String> = ["command:me→main"]
    try expect(
        CommandModeCorrections.applyTracked(to: "me", appClass: term, precedingText: "git push origin", suppressing: cmdSuppressed).0 == "me",
        "suppressed me->main is left alone"
    )
}


private func testInsertionFormatter() throws {
    try expect(
        InsertionFormatter.format("Hello there.", precedingCharacter: nil) == "Hello there.",
        "start of field is unchanged"
    )
    try expect(
        InsertionFormatter.format("Hello there", precedingCharacter: "o") == " hello there",
        "mid-sentence continuation is lowercased + spaced"
    )
    try expect(
        InsertionFormatter.format("Hello there", precedingCharacter: ".") == " Hello there",
        "after a sentence end, capitalization is kept"
    )
    try expect(
        InsertionFormatter.format("hello", precedingCharacter: " ") == "hello",
        "no double space after existing whitespace"
    )
    try expect(
        InsertionFormatter.format("I think", precedingCharacter: "o") == " I think",
        "standalone I is preserved"
    )
    try expect(
        InsertionFormatter.format("API call", precedingCharacter: "e") == " API call",
        "acronym is preserved"
    )
}

private func testTranscriptHistory() throws {
    let t0 = Date(timeIntervalSince1970: 1_000)
    var recs: [TranscriptRecord] = []
    for i in 0..<5 {
        recs = TranscriptHistory.appending("entry \(i)", to: recs, at: t0.addingTimeInterval(Double(i)), maxEntries: 3)
    }
    try expect(recs.count == 3, "history caps at 3, got \(recs.count)")
    try expect(recs.first?.text == "entry 2", "drops the oldest, got \(recs.first?.text ?? "nil")")
    recs = TranscriptHistory.appending("   ", to: recs, at: t0)
    try expect(recs.count == 3, "blank is not added")

    let hits = TranscriptHistory.search(recs, query: "ENTRY 4")
    try expect(hits.count == 1 && hits.first?.text == "entry 4", "case-insensitive search finds entry 4")
    let all = TranscriptHistory.search(recs, query: "  ")
    try expect(all.first?.text == "entry 4", "empty query returns newest first")
}

private func testTranscriptionErrorUserMessage() throws {
    // User-facing messages must never leak binary names, paths, or status codes
    // (those stay in `description` for logs).
    let errors: [TranscriptionError] = [
        .missingExecutable("/opt/homebrew/bin/whisper-cli"),
        .missingModel("/Users/x/models/m.bin"),
        .missingAudioFile("/tmp/a.wav"),
        .processFailed(2, "boom"),
        .timedOut(60),
        .emptyTranscript,
    ]
    for error in errors {
        let m = error.userMessage
        try expect(!m.localizedCaseInsensitiveContains("whisper-cli"), "userMessage must not name whisper-cli: \(m)")
        try expect(!m.contains("/"), "userMessage must not contain a file path: \(m)")
        try expect(!m.localizedCaseInsensitiveContains("status "), "userMessage must not contain a status code: \(m)")
    }
    try expect(TranscriptionError.emptyTranscript.userMessage == "No speech was detected.", "empty → no speech")
}

private func testDefaultVocabularyMerge() throws {
    // User vocab first, then defaults (deduped vs vocab), then history — in budget.
    let p = RecognitionContext.prompt(
        vocabulary: "Acme, Zeta",
        defaults: ["Claude", "Acme", "GitHub"],  // "Acme" already in user vocab → skipped
        history: ["hello there"],
        maxChars: 200
    )
    try expect(p.contains("Acme") && p.contains("Zeta"), "should include user vocab")
    try expect(p.contains("Claude") && p.contains("GitHub"), "should include defaults")
    try expect(p.contains("hello there"), "should include history")
    let zeta = p.range(of: "Zeta")!.lowerBound
    let claude = p.range(of: "Claude")!.lowerBound
    try expect(zeta < claude, "user vocab should precede defaults")
    try expect(p.components(separatedBy: "Acme").count - 1 == 1, "user-vocab term should not be duplicated by defaults")
    try expect(p.count <= 200, "should respect maxChars")

    // No defaults → same as before (backward compatible).
    try expect(
        RecognitionContext.prompt(vocabulary: "X", defaults: [], history: [], maxChars: 100) == "Technical terms: X.",
        "no defaults → just the vocabulary"
    )
    // Defaults work with empty user vocab (the out-of-the-box case).
    let noVocab = RecognitionContext.prompt(vocabulary: "", defaults: ["Claude", "Qwen"], history: [], maxChars: 100)
    try expect(noVocab.contains("Claude") && noVocab.contains("Qwen"), "defaults apply even with no user vocab")
}

private func testKeystrokeChunks() throws {
    try expect(KeystrokeInserter.chunks(of: "", size: 5).isEmpty, "empty text → no chunks")
    let chunks = KeystrokeInserter.chunks(of: "abcdefg", size: 3)
    try expect(chunks.count == 3, "7 chars / 3 = 3 chunks, got \(chunks.count)")
    try expect(chunks[0].count == 3 && chunks[2].count == 1, "chunk sizes should be 3,3,1")
    let joined = chunks.flatMap { $0 }
    try expect(String(utf16CodeUnits: joined, count: joined.count) == "abcdefg", "chunks reconstruct the text")

    // A surrogate pair (emoji) must never be split across a chunk boundary.
    let emoji = KeystrokeInserter.chunks(of: "ab📍cd", size: 3)
    for chunk in emoji {
        let s = String(utf16CodeUnits: chunk, count: chunk.count)
        try expect(Array(s.utf16) == chunk, "each chunk must be valid UTF-16 (no split surrogate), got \(chunk)")
    }
    let emojiJoined = emoji.flatMap { $0 }
    try expect(String(utf16CodeUnits: emojiJoined, count: emojiJoined.count) == "ab📍cd", "chunks reconstruct emoji text")
}

private func temporaryExecutable(body: String = "exit 0\n") throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("local-dictation-test-whisper-\(UUID().uuidString)")
    try "#!/bin/sh\n\(body)".write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

private final class InMemoryPasteboard: TextPasteboard, @unchecked Sendable {
    private(set) var currentText: String?
    private(set) var writes: [String] = []

    init(text: String?) {
        currentText = text
    }

    func readString() -> String? {
        currentText
    }

    func writeString(_ value: String) {
        writes.append(value)
        currentText = value
    }

    func clear() {
        currentText = nil
    }
}

private final class RecordingPasteCommandSender: PasteCommandSending, @unchecked Sendable {
    private(set) var pasteCount = 0

    func sendPasteCommand() throws {
        pasteCount += 1
    }
}

private final class FailingPasteCommandSender: PasteCommandSending, @unchecked Sendable {
    func sendPasteCommand() throws {
        throw PasteInsertionError.pasteCommandFailed
    }
}

private struct StubError: Error {}

private final class ThrowingRecorder: AudioRecording, @unchecked Sendable {
    func startRecording() async throws { throw StubError() }
    func stopRecording() async throws -> URL { throw StubError() }
}

private final class ThrowingTranscriber: TranscriptionEngine, @unchecked Sendable {
    func transcribe(audioFile: URL) async throws -> String { throw StubError() }
}

private final class StubRecorder: AudioRecording, @unchecked Sendable {
    let audioFile = URL(fileURLWithPath: "/tmp/local-dictation-test.wav")
    private(set) var didStart = false
    private(set) var didStop = false

    func startRecording() async throws {
        didStart = true
    }

    func stopRecording() async throws -> URL {
        didStop = true
        // Write a non-degenerate file so the workflow's minimum-audio guard passes
        // (the workflow deletes it via defer). A real recording is several KB.
        try Data(count: 2048).write(to: audioFile)
        return audioFile
    }
}

private final class TinyRecorder: AudioRecording, @unchecked Sendable {
    let audioFile = URL(fileURLWithPath: "/tmp/local-dictation-tiny-\(UUID().uuidString).wav")
    func startRecording() async throws {}
    func stopRecording() async throws -> URL {
        try Data(count: 100).write(to: audioFile)  // degenerate: below the workflow's guard
        return audioFile
    }
}

private final class StubTranscriber: TranscriptionEngine, @unchecked Sendable {
    let transcript: String
    private(set) var audioFile: URL?

    init(transcript: String) {
        self.transcript = transcript
    }

    func transcribe(audioFile: URL) async throws -> String {
        self.audioFile = audioFile
        return transcript
    }
}

private final class StubInserter: TextInserting, @unchecked Sendable {
    private(set) var insertedText: String?

    func insert(_ text: String) async throws {
        insertedText = text
    }
}

private final class FakePolisher: TextPolishing, @unchecked Sendable {
    private let transform: @Sendable (String) -> PolishOutcome
    private(set) var receivedInput: String?

    init(_ transform: @escaping @Sendable (String) -> PolishOutcome) {
        self.transform = transform
    }

    func polish(_ text: String) async -> PolishOutcome {
        receivedInput = text
        return transform(text)
    }
}

private func testPolishOutcomeText() throws {
    try expect(PolishOutcome.applied("Hi.").text == "Hi.", "applied carries the polished text")
    try expect(PolishOutcome.unchanged("hi").text == "hi", "unchanged carries the input")
    try expect(PolishOutcome.guardRejected("raw").text == "raw", "guardRejected keeps the original")
    try expect(PolishOutcome.unavailable("raw").text == "raw", "unavailable keeps the original")
}

private func testPolishOutcomeClassification() throws {
    try expect(TranscriptPolisher.outcome(forContent: nil, original: "the report") == .unavailable("the report"),
               "nil content → unavailable")
    try expect(TranscriptPolisher.outcome(forContent: "", original: "the report") == .unavailable("the report"),
               "empty content → unavailable")
    try expect(TranscriptPolisher.outcome(forContent: "the quarterly status report is late now", original: "the report") == .guardRejected("the report"),
               "added content words → guardRejected, original kept")
    try expect(TranscriptPolisher.outcome(forContent: "the report", original: "the report") == .unchanged("the report"),
               "byte-identical faithful reply → unchanged")
    try expect(TranscriptPolisher.outcome(forContent: "The report.", original: "the report") == .applied("The report."),
               "faithful reformat (caps/punct) → applied(polished)")
}

private func testWorkflowExposesPolishOutcome() async throws {
    let inserter = StubInserter()
    let polisher = FakePolisher { _ in .applied("The report.") }
    let workflow = DictationWorkflow(
        recorder: StubRecorder(),
        transcriber: StubTranscriber(transcript: "the report"),
        inserter: inserter,
        polisher: polisher
    )
    try await workflow.beginRecording()
    try await workflow.finishRecording()
    try expect(workflow.lastTranscriptAndEdits?.polish == .applied("The report."),
               "workflow threads the polish outcome onto its result")
    try expect(inserter.insertedText == "The report.", "inserts outcome.text, got \(inserter.insertedText ?? "nil")")
}

private func testEditSourceContextSubRoundTrips() throws {
    let edit = Edit(location: 3, length: 6, from: "versal", to: "Vercel", source: .contextSub)
    let data = try JSONEncoder().encode(edit)
    let decoded = try JSONDecoder().decode(Edit.self, from: data)
    try expect(decoded.source == .contextSub, "contextSub source must round-trip through Codable")
}

private func testGuardAcceptsValidSwap() throws {
    let out = ContextSubstitution.guardOutput("deploy it to Vercel", original: "deploy it to versal", candidates: ["Vercel"])
    try expect(out == "deploy it to Vercel", "valid single candidate swap must pass")
}
private func testGuardAcceptsCompoundFix() throws {
    let out = ContextSubstitution.guardOutput("write it in TypeScript", original: "write it in type script", candidates: ["TypeScript"])
    try expect(out == "write it in TypeScript", "type script -> TypeScript (2->1) must pass")
}
private func testGuardRejectsOffList() throws {
    let out = ContextSubstitution.guardOutput("let's use Docker", original: "let's use cuban eats", candidates: ["Kubernetes"])
    try expect(out == "let's use cuban eats", "swapping in a non-candidate must reject to original")
}
private func testGuardRejectsCollapse() throws {
    let out = ContextSubstitution.guardOutput("Vercel", original: "deploy it to versal", candidates: ["Vercel"])
    try expect(out == "deploy it to versal", "dropping >1 word (collapse) must reject")
}
private func testGuardRejectsPureDeletion() throws {
    let out = ContextSubstitution.guardOutput("deploy it to", original: "deploy it to versal", candidates: ["Vercel"])
    try expect(out == "deploy it to versal", "dropping content with nothing added must reject")
}
private func testGuardCaseInsensitiveCandidate() throws {
    let out = ContextSubstitution.guardOutput("ping me on Slack", original: "ping me on slock", candidates: ["slack"])
    try expect(out == "ping me on Slack", "candidate match is case-insensitive")
}
private func testGuardRejectsNonCandidateDuplication() throws {
    // A repeated non-candidate word must be caught by the multiset guard (a plain
    // set would see "push" already present and miss the duplication).
    let out = ContextSubstitution.guardOutput("push push it", original: "push it", candidates: ["it"])
    try expect(out == "push it", "duplicated non-candidate word must reject")
}
private func testGuardRejectsExpansion() throws {
    // Adding more than one word — even candidate words — is unbounded expansion.
    let out = ContextSubstitution.guardOutput("type it right now", original: "type it", candidates: ["right", "now"])
    try expect(out == "type it", "expanding output by >1 word must reject")
}

private func testDiffSingleSwap() throws {
    let swaps = ContextSubstitution.diffSwaps(original: "deploy it to versal", guarded: "deploy it to Vercel")
    try expect(swaps.count == 1, "one swap expected")
    try expect(swaps[0].from == "versal" && swaps[0].to == "Vercel", "from/to text")
    let ns = "deploy it to versal" as NSString
    try expect(ns.substring(with: swaps[0].range) == "versal", "range must address the original word")
}
private func testDiffCompoundSwap() throws {
    let swaps = ContextSubstitution.diffSwaps(original: "write it in type script", guarded: "write it in TypeScript")
    try expect(swaps.count == 1, "compound is one swap")
    try expect(swaps[0].from == "type script" && swaps[0].to == "TypeScript", "2->1 compound from/to")
}
private func testDiffTwoSwaps() throws {
    let swaps = ContextSubstitution.diffSwaps(
        original: "deploy it to versal then spin up cuban eats",
        guarded:  "deploy it to Vercel then spin up Kubernetes")
    try expect(swaps.count == 2, "two independent swaps must stay separate")
    try expect(swaps[0].to == "Vercel" && swaps[1].to == "Kubernetes", "ordered targets")
}
private func testDiffNoChange() throws {
    let swaps = ContextSubstitution.diffSwaps(original: "the dock was full of boats", guarded: "the dock was full of boats")
    try expect(swaps.isEmpty, "identical text yields no swaps")
}
private func testDiffIgnoresCaseOnlyTokens() throws {
    let swaps = ContextSubstitution.diffSwaps(original: "deploy it to versal", guarded: "Deploy it to Vercel")
    try expect(swaps.count == 1 && swaps[0].to == "Vercel", "case-only differences are not swaps")
}
private func testDiffUnicodeWhitespace() throws {
    // A non-breaking space in the guarded output must still tokenize as a word
    // boundary, so the swap is found cleanly instead of merging two words.
    let swaps = ContextSubstitution.diffSwaps(original: "deploy to versal", guarded: "deploy to\u{00A0}Vercel")
    try expect(swaps.count == 1, "NBSP must not merge tokens")
    try expect(swaps[0].from == "versal" && swaps[0].to == "Vercel", "clean swap across NBSP")
}

private func testApplySingle() throws {
    let original = "deploy it to versal"
    let swaps = ContextSubstitution.diffSwaps(original: original, guarded: "deploy it to Vercel")
    let (out, edits) = ContextSubstitution.apply(swaps, to: original)
    try expect(out == "deploy it to Vercel", "applied text")
    try expect(edits.count == 1 && edits[0].source == .contextSub, "one contextSub edit")
    let ns = out as NSString
    try expect(ns.substring(with: edits[0].range) == "Vercel", "edit range addresses 'to' in OUTPUT space")
}
private func testApplyTwoSwapsOffsets() throws {
    let original = "deploy it to versal then spin up cuban eats"
    let swaps = ContextSubstitution.diffSwaps(original: original, guarded: "deploy it to Vercel then spin up Kubernetes")
    let (out, edits) = ContextSubstitution.apply(swaps, to: original)
    try expect(out == "deploy it to Vercel then spin up Kubernetes", "both applied")
    let ns = out as NSString
    try expect(ns.substring(with: edits[0].range) == "Vercel", "first edit range valid post-shift")
    try expect(ns.substring(with: edits[1].range) == "Kubernetes", "second edit range valid post-shift")
}
private func testApplyEmpty() throws {
    let (out, edits) = ContextSubstitution.apply([], to: "unchanged")
    try expect(out == "unchanged" && edits.isEmpty, "no swaps -> no change")
}

private func testRequestBodyShape() throws {
    let data = ContextSubstitution.chatRequestBody(transcript: "deploy it to versal", candidates: ["Vercel", "Netlify"])
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    try expect((json["temperature"] as? Double) == 0, "temperature must be 0")
    let kwargs = json["chat_template_kwargs"] as? [String: Any]
    try expect((kwargs?["enable_thinking"] as? Bool) == false, "thinking disabled")
    let messages = json["messages"] as! [[String: String]]
    try expect(messages.first?["role"] == "system", "first message is system")
    try expect(messages.first!["content"]!.contains("Vercel, Netlify"), "system prompt lists candidates")
    try expect(messages.last?["role"] == "user", "last message is user")
    try expect(messages.last!["content"]!.contains("deploy it to versal"), "user carries the transcript")
}
private func testParseContent() throws {
    let payload = #"{"choices":[{"message":{"content":"deploy it to Vercel"}}]}"#.data(using: .utf8)!
    try expect(ContextSubstitution.parseContent(payload) == "deploy it to Vercel", "parses choices[0].message.content")
}

private func testContextSubstituteFoldsIntoSegmentA() async throws {
    // A stub stage that swaps "versal" -> "Vercel" and reports the edit.
    let stage: @Sendable (String) async -> (String, [Edit]) = { text in
        ContextSubstitution.apply(
            ContextSubstitution.diffSwaps(original: text, guarded: text.replacingOccurrences(of: "versal", with: "Vercel")),
            to: text)
    }
    let (out, edits) = await stage("deploy it to versal")
    try expect(out == "deploy it to Vercel", "stage applies the swap")
    let folded = EditFold.combine([[], edits])
    try expect(folded.count == 1 && folded[0].source == .contextSub, "edits fold into segmentA space")
}

private func testRecentRecordingsNamesToPrune() throws {
    // Below the cap → nothing to prune.
    try expect(RecentRecordingsPrune.namesToPrune(existing: [], keepCount: 10) == [],
               "empty list → no pruning")
    try expect(RecentRecordingsPrune.namesToPrune(existing: ["a.wav", "b.wav"], keepCount: 10) == [],
               "under cap → nothing pruned")
    // Exactly at cap → nothing to prune.
    let atCap = (0..<10).map { "rec-\($0).wav" }
    try expect(RecentRecordingsPrune.namesToPrune(existing: atCap, keepCount: 10) == [],
               "at cap → nothing pruned")
    // One over the cap → drop the oldest (first in sort order).
    let oneOver = (0..<11).map { "rec-\($0).wav" }
    let pruned = RecentRecordingsPrune.namesToPrune(existing: oneOver, keepCount: 10)
    try expect(pruned == ["rec-0.wav"], "one over cap → oldest entry pruned; got \(pruned)")
    // Several over the cap → drop the oldest N.
    let several = (0..<15).map { "rec-\($0).wav" }
    let prunedSeveral = RecentRecordingsPrune.namesToPrune(existing: several, keepCount: 10)
    try expect(prunedSeveral == (0..<5).map { "rec-\($0).wav" },
               "five over cap → oldest five pruned; got \(prunedSeveral)")
    // keepCount of 0 → everything pruned.
    try expect(RecentRecordingsPrune.namesToPrune(existing: ["a.wav"], keepCount: 0) == ["a.wav"],
               "keepCount 0 → all entries pruned")
}

// MARK: - SubstitutionPrefilter

/// The 11 in-scope mishear cases from tools/accuracy-harness/substitution_ab.py
/// (targets >= 5 squashed chars). Prefilter recall here must stay 100% — a miss
/// means a fixable dictation never reaches the substitution LLM.
private func testPrefilterRecall() throws {
    let mishears: [(String, [String])] = [
        ("deploy it to versal", ["Vercel", "Netlify", "Render"]),
        ("open it in super base", ["Supabase", "Firebase", "Postgres"]),
        ("let's use cuban eats", ["Kubernetes", "Docker", "Helm"]),
        ("the cooper netties cluster", ["Kubernetes", "Nomad"]),
        ("check the next js config", ["Next.js", "Nuxt", "Vite"]),
        ("write it in type script", ["TypeScript", "JavaScript"]),
        ("store it in post grass", ["Postgres", "SQLite", "Redis"]),
        ("query the my sequel database", ["MySQL", "Postgres"]),
        ("push it to git hub", ["GitHub", "GitLab"]),
        ("use git lab for ci", ["GitLab", "GitHub", "CircleCI"]),
        ("open the project in ex code", ["Xcode", "VSCode"]),
    ]
    for (transcript, candidates) in mishears {
        try expect(SubstitutionPrefilter.worthCalling(transcript: transcript, candidates: candidates),
                   "must fire on: \(transcript)")
    }
}

private func testPrefilterSkips() throws {
    let vocab = ["Vercel", "Supabase", "Kubernetes", "TypeScript", "Postgres", "GitHub",
                 "Xcode", "Tailwind", "Docker", "Figma", "Notion"]
    let prose = [
        "Please remember to back up your files regularly.",
        "Thanks so much for your help, I really appreciate it.",
        "We need to schedule a follow up call next Tuesday.",
        "I need to buy two items as well too",
    ]
    for text in prose {
        try expect(!SubstitutionPrefilter.worthCalling(transcript: text, candidates: vocab),
                   "must skip candidate-free prose: \(text)")
    }
}

private func testPrefilterEdgeCases() throws {
    // Short candidates are out of scope — deterministic layers own them.
    try expect(!SubstitutionPrefilter.worthCalling(transcript: "push to me", candidates: ["main", "git"]),
               "short candidates never trigger the prefilter")
    // No candidates at all -> never call.
    try expect(!SubstitutionPrefilter.worthCalling(transcript: "deploy it to versal", candidates: []),
               "empty candidates -> skip")
    // Exact presence of a long candidate still fires (a second occurrence may be misheard).
    try expect(SubstitutionPrefilter.worthCalling(transcript: "open GitHub now", candidates: ["GitHub"]),
               "exact candidate presence fires")
    // Dictionary word near a candidate stays blocked below the override band.
    try expect(!SubstitutionPrefilter.worthCalling(transcript: "the notion of fairness", candidates: ["Docker", "Vercel"]),
               "real English word with weak similarity is dictionary-blocked")
}

private func testTailCapture() throws {
    // Hard cap always stops, whatever the levels say.
    try expect(TailCapture.shouldStop(elapsedMillis: 400, recentLevels: [0.9, 0.9]), "cap reached -> stop")
    // Before the minimum, silence must not stop capture (mid-word buffer not landed).
    try expect(!TailCapture.shouldStop(elapsedMillis: 50, recentLevels: [0.0]), "below minimum -> keep capturing")
    // Sustained silence after the minimum stops early.
    try expect(TailCapture.shouldStop(elapsedMillis: 150, recentLevels: [0.1, 0.05, 0.02]), "quiet tail -> early stop")
    // Speech in the tail keeps the tap alive.
    try expect(!TailCapture.shouldStop(elapsedMillis: 150, recentLevels: [0.1, 0.6]), "loud last poll -> keep capturing")
    try expect(!TailCapture.shouldStop(elapsedMillis: 200, recentLevels: [0.6, 0.2]), "one quiet poll is not enough")
    // Not enough samples yet -> keep capturing.
    try expect(!TailCapture.shouldStop(elapsedMillis: 150, recentLevels: [0.1]), "single sample -> keep capturing")
}

// Mirrors AppModel.makeWorkflow's deterministic preCorrect chain (mishearing ->
// command -> phonetic snap) so a wiring regression there has a failing shape here.
private func testPhoneticSnapThroughWorkflow() async throws {
    let vocabulary = ContextBias.substitutionCandidates(customVocabulary: "", defaults: DefaultVocabulary.terms)
    let inserter = StubInserter()
    let workflow = DictationWorkflow(
        recorder: StubRecorder(),
        transcriber: StubTranscriber(transcript: "ask clot to deploy the superbase schema"),
        inserter: inserter,
        preCorrect: { text in
            var result = text
            var passes: [[Edit]] = []
            let (misheard, mishearEdits) = MishearingCorrections.applyTracked(to: result)
            result = misheard
            passes.append(mishearEdits)
            let (snapped, snapEdits) = PhoneticSnapCorrections.applyTracked(to: result, vocabulary: vocabulary)
            result = snapped
            passes.append(snapEdits)
            return (result, EditFold.combine(passes))
        }
    )
    try await workflow.beginRecording()
    try await workflow.finishRecording()
    try expect(
        inserter.insertedText == "ask Claude to deploy the Supabase schema",
        "chained corrections should reach insertion, got \(inserter.insertedText ?? "nil")"
    )
}

private func testMetaphoneFixture() throws {
    var mismatches: [String] = []
    for (input, expected) in metaphoneFixture where Metaphone.key(input) != expected {
        mismatches.append("\(input): got \(Metaphone.key(input).debugDescription), want \(expected.debugDescription)")
    }
    try expect(mismatches.isEmpty, "\(mismatches.count)/\(metaphoneFixture.count) mismatches, e.g. \(mismatches.prefix(5).joined(separator: "; "))")
}

private let snapVocabulary = ["Supabase", "LangChain", "OpenAI", "Xcode", "GitHub", "Chollet", "Vercel", "Kubernetes", "Vue"]

private func testPhoneticSnapFixes() throws {
    // The measured win classes: single non-word mangles and multi-word mangles.
    let cases: [(String, String)] = [
        ("Deploying the app with the superbees database", "Deploying the app with the Supabase database"),
        ("Validate the payload inside the LungChain agent", "Validate the payload inside the LangChain agent"),
        ("Francois Choulet created Keras", "Francois Chollet created Keras"),
    ]
    for (input, want) in cases {
        let got = PhoneticSnapCorrections.apply(to: input, vocabulary: snapVocabulary)
        try expect(got == want, "\(input.debugDescription) -> \(got.debugDescription), want \(want.debugDescription)")
    }
}

private func testPhoneticSnapGuards() throws {
    let untouched = [
        // "open" is a real English word — the dictionary gate must block the
        // measured open->OpenAI false swap.
        "Push the branch to GitHub and open the project in Xcode.",
        // The target term already appears: never double-place it.
        "the LangChain LungChain demo",
        // Plain prose with nothing candidate-like.
        "So I was thinking we grab lunch after the meeting today.",
        // A multi-word window of real English words is prose, not a mishearing
        // ("long chain" must not become LangChain) — whatever whitespace joins them.
        "it was a long chain of events",
        "it was a long\u{00A0}chain of events",
        // A window that IS a vocabulary term stays put.
        "deploy it on Kubernetes now",
    ]
    for input in untouched {
        let got = PhoneticSnapCorrections.apply(to: input, vocabulary: snapVocabulary)
        try expect(got == input, "\(input.debugDescription) changed to \(got.debugDescription)")
    }
    // Terms shorter than 4 alphanumerics are out of scope ("view" must not snap to Vue).
    let short = PhoneticSnapCorrections.apply(to: "build the settings view today", vocabulary: snapVocabulary)
    try expect(short == "build the settings view today", "short-term guard: \(short.debugDescription)")
    // Empty vocabulary is a no-op.
    try expect(PhoneticSnapCorrections.apply(to: "the superbees database", vocabulary: []) == "the superbees database", "empty vocabulary must no-op")
}

private func testPhoneticSnapEditsAndPunctuation() throws {
    // Trailing punctuation on the snapped window survives the swap.
    let (comma, commaEdits) = PhoneticSnapCorrections.applyTracked(
        to: "deploy to superbees, then test", vocabulary: snapVocabulary
    )
    try expect(comma == "deploy to Supabase, then test", "comma preserved: \(comma.debugDescription)")
    try expect(commaEdits.count == 1, "one edit, got \(commaEdits.count)")
    if let edit = commaEdits.first {
        try expect(edit.from == "superbees" && edit.to == "Supabase" && edit.source == .mishearing,
                   "edit content: \(edit.from) -> \(edit.to) (\(edit.source))")
        try expect((comma as NSString).substring(with: edit.range) == "Supabase",
                   "edit range must cover the replacement in the output")
    }
    let (period, _) = PhoneticSnapCorrections.applyTracked(
        to: "Validate it inside the LungChain.", vocabulary: snapVocabulary
    )
    try expect(period == "Validate it inside the LangChain.", "period preserved: \(period.debugDescription)")
    // A suppressed swap (review-panel revert) never fires again.
    let suppressed = RuleDerivation.suppressionIdentity(source: .mishearing, from: "superbees", to: "Supabase")!
    let (kept, keptEdits) = PhoneticSnapCorrections.applyTracked(
        to: "deploy to superbees now", vocabulary: snapVocabulary, suppressing: [suppressed]
    )
    try expect(kept == "deploy to superbees now" && keptEdits.isEmpty, "suppressed swap fired: \(kept.debugDescription)")
}
// GENERATED jellyfish (Rust) metaphone reference outputs (gen_metaphone_swift.py).
private let metaphoneFixture: [(String, String)] = [
    ("Actiniaria", "AKTNR"),
    ("Antheraea", "AN0R"),
    ("Anthropic", "AN0RPK"),
    ("Arriet", "ART"),
    ("Bobadilism", "BBTLSM"),
    ("Busaos", "BSS"),
    ("CUDA", "KT"),
    ("Calimeris", "KLMRS"),
    ("Caribbee", "KRB"),
    ("Ceratopteris", "SRTPTRS"),
    ("ChatGPT", "XTKPT"),
    ("Chollet", "XLT"),
    ("Claude", "KLT"),
    ("Clitocybe", "KLTSB"),
    ("Dedanite", "TTNT"),
    ("Docker", "TKR"),
    ("FFmpeg", "FMPK"),
    ("Figma", "FKM"),
    ("Gemini", "JMN"),
    ("GitHub", "J0B"),
    ("Grafana", "KRFN"),
    ("GraphQL", "KRFKL"),
    ("Guido", "KT"),
    ("JavaScript", "JFSKRPT"),
    ("Kafka", "KFK"),
    ("Karpathy", "KRP0"),
    ("Keras", "KRS"),
    ("Kubernetes", "KBRNTS"),
    ("LangChain", "LNKXN"),
    ("Leninite", "LNNT"),
    ("Magian", "MJN"),
    ("Next.js", "NKSTJS"),
    ("Node.js", "NTJS"),
    ("Notion", "NXN"),
    ("OpenAI", "OPN"),
    ("Parakeet", "PRKT"),
    ("Paszke", "PSSK"),
    ("Peronospora", "PRNSPR"),
    ("Pinecone", "PNKN"),
    ("Postgres", "PSTKRS"),
    ("Prionopinae", "PRNPN"),
    ("Prometheus", "PRM0S"),
    ("PyTorch", "PTRX"),
    ("Pydantic", "PTNTK"),
    ("Python", "P0N"),
    ("Pytorch", "PTRX"),
    ("Qwen", "KWN"),
    ("RabbitMQ", "RBTMK"),
    ("React", "RKT"),
    ("Redis", "RTS"),
    ("Romance", "RMNS"),
    ("Scolia", "SKL"),
    ("Shiraz", "XRS"),
    ("Slack", "SLK"),
    ("Supabase", "SPBS"),
    ("Swift", "SWFT"),
    ("SwiftUI", "SWFT"),
    ("Sybil", "SBL"),
    ("Tailwind", "TLWNT"),
    ("Tantalic", "TNTLK"),
    ("Terraform", "TRFRM"),
    ("Torvalds", "TRFLTS"),
    ("TypeScript", "TPSKRPT"),
    ("Vercel", "FRSL"),
    ("Wasm", "WSM"),
    ("Weaviate", "WFT"),
    ("WebAssembly", "WBSMBL"),
    ("Winnie", "WN"),
    ("Xcode", "SKT"),
    ("accept", "AKSPT"),
    ("aegis", "EJS"),
    ("ai", "A"),
    ("amyloplastic", "AMLPLSTK"),
    ("anastate", "ANSTT"),
    ("annale", "ANL"),
    ("anthracemia", "AN0RSM"),
    ("askingly", "ASKNKL"),
    ("assuetude", "ASTT"),
    ("away", "AW"),
    ("backfriend", "BKFRNT"),
    ("badge", "BJ"),
    ("beglerbeglic", "BKLRBKLK"),
    ("berthed", "BR0T"),
    ("bewinged", "BWNJT"),
    ("blot", "BLT"),
    ("box", "BKS"),
    ("branch", "BRNX"),
    ("brew", "BR"),
    ("bribemonger", "BRBMNJR"),
    ("bulbule", "BLBL"),
    ("buzzer", "BSR"),
    ("cache", "KX"),
    ("capuchin", "KPXN"),
    ("cardiotoxic", "KRTTKSK"),
    ("casio", "KX"),
    ("chalcanthite", "XLKN0T"),
    ("check out", "XK OT"),
    ("checkout", "XKT"),
    ("choulet", "XLT"),
    ("chrome", "XRM"),
    ("clean-off", "KLNF"),
    ("climb", "KLM"),
    ("combine", "KMBN"),
    ("commit", "KMT"),
    ("contactual", "KNTKTL"),
    ("converting", "KNFRTNK"),
    ("convictional", "KNFKXNL"),
    ("cooper netties", "KPR NTS"),
    ("corrode", "KRT"),
    ("cuda kernel", "KT KRNL"),
    ("culteranismo", "KLTRNSM"),
    ("cycadlike", "SKTLK"),
    ("darky", "TRK"),
    ("dasymeter", "TSMTR"),
    ("declaim", "TKLM"),
    ("detubation", "TTBXN"),
    ("dyke", "TK"),
    ("echo", "EX"),
    ("emanative", "EMNTF"),
    ("equoid", "EKT"),
    ("erythrophage", "ER0RFJ"),
    ("ethics", "E0KS"),
    ("everything", "EFR0NK"),
    ("evreen", "EFRN"),
    ("exit", "EKST"),
    ("explanatory", "EKSPLNTR"),
    ("extended", "EKSTNTT"),
    ("extollingly", "EKSTLNKL"),
    ("eyeglass", "EYKLS"),
    ("fascinatress", "FSSNTRS"),
    ("figurante", "FKRNT"),
    ("finish", "FNX"),
    ("flocculent", "FLKKLNT"),
    ("floodcock", "FLTKK"),
    ("fute", "FT"),
    ("futwa", "FTW"),
    ("gRPC", "KRPK"),
    ("galvanology", "KLFNLJ"),
    ("ghost", "KHST"),
    ("ginks", "JNKS"),
    ("git", "JT"),
    ("git hub", "JT HB"),
    ("gnome", "NM"),
    ("graycoat", "KRKT"),
    ("groschen", "KRSXN"),
    ("groved", "KRFT"),
    ("guna", "KN"),
    ("gutweed", "KTWT"),
    ("gym", "JM"),
    ("hairup", "HRP"),
    ("heathbird", "H0BRT"),
    ("hedge", "HJ"),
    ("hedgehog", "HJHK"),
    ("hemihydrate", "HMTRT"),
    ("hemiolia", "HML"),
    ("hemitremor", "HMTRMR"),
    ("houbara", "HBR"),
    ("hydroscope", "HTRSKP"),
    ("ingress", "INKRS"),
    ("intestacy", "INTSTS"),
    ("introductor", "INTRTKTR"),
    ("jigman", "JKMN"),
    ("judge", "JJ"),
    ("knowledge", "NLJ"),
    ("kubectl", "KBKTL"),
    ("lactagogue", "LKTKK"),
    ("lamb", "LM"),
    ("lasque", "LSK"),
    ("long chain", "LNK XN"),
    ("lucky", "LK"),
    ("lumbang", "LMBNK"),
    ("lungchain", "LNKXN"),
    ("main", "MN"),
    ("mammonish", "MMNX"),
    ("mandatee", "MNTT"),
    ("marmoreal", "MRMRL"),
    ("match", "MX"),
    ("melanopathia", "MLNP0"),
    ("merge", "MRJ"),
    ("miler", "MLR"),
    ("mimetite", "MMTT"),
    ("miniator", "MNTR"),
    ("ministryship", "MNSTRXP"),
    ("mutuary", "MTR"),
    ("nanoGPT", "NNKPT"),
    ("narcomedusan", "NRKMTSN"),
    ("nation", "NXN"),
    ("necessitate", "NSSTT"),
    ("next js", "NKST JS"),
    ("nginx", "NJNKS"),
    ("night", "NT"),
    ("npm", "NPM"),
    ("occupancy", "OKKPNS"),
    ("occur", "OKKR"),
    ("ocean", "OSN"),
    ("ogdoas", "OKTS"),
    ("oillike", "OLK"),
    ("oleoduct", "OLTKT"),
    ("open", "OPN"),
    ("openai", "OPN"),
    ("origin", "ORJN"),
    ("ornate", "ORNT"),
    ("paramatta", "PRMT"),
    ("paszk", "PSSK"),
    ("patinous", "PTNS"),
    ("patio", "PX"),
    ("penultima", "PNLTM"),
    ("percentile", "PRSNTL"),
    ("pineconen", "PNKNN"),
    ("pneumonia", "NMN"),
    ("pnpm", "NPM"),
    ("prefragrance", "PRFRKRNS"),
    ("protoplastic", "PRTPLSTK"),
    ("provalds", "PRFLTS"),
    ("psalm", "PSLM"),
    ("pulldown", "PLTN"),
    ("qda", "KT"),
    ("quick", "KK"),
    ("rebase", "RBS"),
    ("reptatorial", "RPTTRL"),
    ("resterilize", "RSTRLS"),
    ("review", "RF"),
    ("ronquil", "RNKL"),
    ("rough", "RKH"),
    ("salableness", "SLBLNS"),
    ("sauterelle", "STRL"),
    ("school", "SXL"),
    ("science", "SSNS"),
    ("scombriform", "SKMBRFRM"),
    ("selihoth", "SLH0"),
    ("she", "X"),
    ("sign", "S"),
    ("signal", "SKNL"),
    ("sirup", "SRP"),
    ("skepful", "SKPFL"),
    ("smother", "SM0R"),
    ("snobbish", "SNBX"),
    ("social", "SXL"),
    ("sporocarp", "SPRKRP"),
    ("square", "SKR"),
    ("stibonium", "STBNM"),
    ("subpavement", "SBPFMNT"),
    ("success", "SKSS"),
    ("super base", "SPR BS"),
    ("superbees", "SPRBS"),
    ("swatter", "SWTR"),
    ("taraph", "TRF"),
    ("telechemic", "TLXMK"),
    ("telfer", "TLFR"),
    ("terrorsome", "TRRSM"),
    ("thiourethan", "0R0N"),
    ("this", "0S"),
    ("though", "0KH"),
    ("thumb", "0M"),
    ("thumbstring", "0MBSTRNK"),
    ("tonguiness", "TNKNS"),
    ("trappous", "TRPS"),
    ("tumefacient", "TMFSNT"),
    ("unalmsed", "UNLMST"),
    ("uncasemated", "UNKSMTT"),
    ("uncudgelled", "UNKJLT"),
    ("undenounced", "UNTNNST"),
    ("undirected", "UNTRKTT"),
    ("uninvitedly", "UNNFTTL"),
    ("unmental", "UNMNTL"),
    ("unmold", "UNMLT"),
    ("unpillared", "UNPLRT"),
    ("untrowed", "UNTRWT"),
    ("unwhite", "UNHT"),
    ("versal", "FRSL"),
    ("vesicule", "FSKL"),
    ("vessel", "FSL"),
    ("viand", "FNT"),
    ("vision", "FXN"),
    ("vue", "F"),
    ("wandsman", "WNTSMN"),
    ("weaviate", "WFT"),
    ("wetched", "WXT"),
    ("whale", "WL"),
    ("what", "WT"),
    ("whereover", "WRFR"),
    ("woodcracker", "WTKRKR"),
    ("wrangler", "RNKLR"),
    ("wrist", "RST"),
    ("x", "S"),
    ("xhosa", "XHS"),
    ("xylophone", "SLFN"),
    ("yes", "YS"),
    ("zebra", "SBR"),
    ("zootechnic", "STXNK"),
]

// Conformance harness vs the measured Python prototype (tools/accuracy-harness/
// phonetic_snap_ab.py). Generate the reference with `--parity <out.json>`, then
// LD_PHONO_PARITY=<out.json> swift run LocalDictationCoreTestRunner
private struct ParityFile: Codable {
    struct Row: Codable { let set: String; let raw: String; let fixed: String }
    let mic_vocab: [String]
    let jargon_vocab: [String]
    let rows: [Row]
}

func runPhoneticParityIfRequested() {
    guard let path = ProcessInfo.processInfo.environment["LD_PHONO_PARITY"],
          let data = FileManager.default.contents(atPath: path),
          let file = try? JSONDecoder().decode(ParityFile.self, from: data) else { return }
    var mismatches = 0
    for row in file.rows {
        let vocab = row.set == "tts_jargon" ? file.jargon_vocab : file.mic_vocab
        let got = PhoneticSnapCorrections.apply(to: row.raw, vocabulary: vocab)
        // Python drops window punctuation; Swift deliberately keeps it. Compare
        // modulo punctuation-free tokens.
        func norm(_ s: String) -> String {
            s.lowercased().split(separator: " ").map { $0.filter { $0.isLetter || $0.isNumber } }
                .filter { !$0.isEmpty }.joined(separator: " ")
        }
        if norm(got) != norm(row.fixed) {
            mismatches += 1
            print("PARITY MISMATCH (\(row.set))\n  raw:    \(row.raw)\n  python: \(row.fixed)\n  swift:  \(got)")
        }
    }
    print("parity: \(file.rows.count - mismatches)/\(file.rows.count) match")
    exit(mismatches == 0 ? 0 : 1)
}
