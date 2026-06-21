import Foundation
import LocalDictationCore

@main
struct LocalDictationCoreTestRunner {
    static func main() async {
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
        await suite.run("Polish guardrail accepts faithful, rejects divergent", testPolishGuardrail)
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
        await suite.run("Recognition prompt folds in live context, weighted + capped", testContextPrompt)
        await suite.run("Workflow command mode: terminal git push me -> main", testWorkflowCommandModeInsertsMain)
        await suite.run("Workflow prose: chat 'push to me' left alone", testWorkflowProseLeavesMeAlone)
        await suite.run("Workflow command mode survives prose cleanup (caps/period)", testWorkflowCommandModeWithCleanup)
        await suite.run("Polish prompt is formatting cleanup only", testPolishPromptCleansOnly)
        await suite.run("Corrector guardrail allows word swaps, rejects expand/summary", testCorrectorGuardrail)
        await suite.run("Text replacements parse + whole-word apply", testTextReplacements)
        await suite.run("Insertion formatter handles mid-sentence continuation", testInsertionFormatter)
        await suite.run("Transcript history caps, skips blanks, searches", testTranscriptHistory)
        await suite.run("Keystroke inserter chunks UTF-16 correctly", testKeystrokeChunks)
        await suite.run("Recognition prompt merges default vocabulary", testDefaultVocabularyMerge)
        await suite.run("TranscriptionError userMessage is jargon-free", testTranscriptionErrorUserMessage)
        suite.finish()
    }
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
    try expect(messages.count == 8, "system + 3 few-shot pairs + transcript = 8 messages")

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

private func testDictationContext() throws {
    // appendingHistory caps to maxEntries and skips blanks.
    var h: [String] = []
    for i in 0..<15 { h = RecognitionContext.appendingHistory("line \(i)", to: h, maxEntries: 12) }
    try expect(h.count == 12, "history should cap at 12, got \(h.count)")
    try expect(h.first == "line 3", "should drop oldest, got \(h.first ?? "nil")")
    h = RecognitionContext.appendingHistory("   ", to: h)
    try expect(h.count == 12, "blank should not be added")

    // prompt: vocabulary + recent history, capped.
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
    let polisher = FakePolisher { $0.replacingOccurrences(of: "clot", with: "Claude") }
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
    let polisher = FakePolisher { $0 }  // identity: passes its input straight through
    let workflow = DictationWorkflow(
        recorder: StubRecorder(),
        transcriber: StubTranscriber(transcript: "ship it with clot today"),
        inserter: inserter,
        preCorrect: { MishearingCorrections.apply(to: $0) },
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
    try expect(p.hasPrefix("Nxabyte"), "user vocabulary leads")
    try expect(p.contains("git push origin"), "preceding text folded in")
    try expect(p.contains("feat/login") && p.contains("UserStore.swift"), "candidates folded in")
    try expect(p.contains("main") && p.contains("branch"), "app-class vocabulary folded in")
    let preceding = p.range(of: "git push origin")!.lowerBound
    let appVocab = p.range(of: "branch")!.lowerBound
    try expect(preceding < appVocab, "caret-proximate preceding text precedes app-class vocab")

    // No context → byte-identical to before (backward compatible).
    try expect(
        RecognitionContext.prompt(vocabulary: "X", history: [], context: nil) == "X",
        "nil context → unchanged"
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

private func testWorkflowCommandModeInsertsMain() async throws {
    // Mirrors AppModel's preCorrect composition: global-safe fixes, then the
    // context-gated command mode. In a terminal after `git push origin`, the
    // misheard "me" must be inserted as "main".
    let inserter = StubInserter()
    let workflow = DictationWorkflow(
        recorder: StubRecorder(),
        transcriber: StubTranscriber(transcript: "me"),
        inserter: inserter,
        preCorrect: { text in
            CommandModeCorrections.apply(
                to: MishearingCorrections.apply(to: text), appClass: .terminal, precedingText: "git push origin "
            )
        }
    )
    try await workflow.beginRecording()
    try await workflow.finishRecording()
    try expect(inserter.insertedText == "main", "terminal git push: me -> main, got \(inserter.insertedText ?? "nil")")
}

private func testWorkflowProseLeavesMeAlone() async throws {
    // Same composition, but in Slack (chat) — command mode must NOT fire, so the
    // exact same words are inserted unchanged.
    let inserter = StubInserter()
    let workflow = DictationWorkflow(
        recorder: StubRecorder(),
        transcriber: StubTranscriber(transcript: "push to me"),
        inserter: inserter,
        preCorrect: { text in
            CommandModeCorrections.apply(
                to: MishearingCorrections.apply(to: text), appClass: .chat, precedingText: "tell them to "
            )
        }
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
        preCorrect: { text in
            CommandModeCorrections.apply(
                to: MishearingCorrections.apply(to: text), appClass: .terminal, precedingText: nil
            )
        }
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
    try expect(msgs.count == 8, "system + 3 few-shot pairs + transcript = 8, got \(msgs.count)")
}

private func testCorrectorGuardrail() throws {
    // Corrector accepts a likely-mishearing fix that the strict guardrail rejects.
    try expect(
        TranscriptPolisher.isFaithfulCorrection(
            polished: "I was vibe coding the whole thing", original: "i was webcoded the whole thing"
        ),
        "corrector should accept a same-length word substitution"
    )
    try expect(
        !TranscriptPolisher.isFaithful(
            polished: "I was vibe coding the whole thing", original: "i was webcoded the whole thing"
        ),
        "strict guardrail should reject that word change"
    )
    // Corrector still rejects an answer/expansion and a summary.
    try expect(
        !TranscriptPolisher.isFaithfulCorrection(
            polished: "Sure, I can help you book a flight to Paris next week!", original: "book a flight"
        ),
        "corrector should reject an expansion/answer"
    )
    try expect(
        !TranscriptPolisher.isFaithfulCorrection(
            polished: "Done.",
            original: "so the meeting we scheduled for tuesday has been moved to thursday afternoon"
        ),
        "corrector should reject a summary that drops most words"
    )
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
        RecognitionContext.prompt(vocabulary: "X", defaults: [], history: [], maxChars: 100) == "X",
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
    private let transform: @Sendable (String) -> String
    private(set) var receivedInput: String?

    init(_ transform: @escaping @Sendable (String) -> String) {
        self.transform = transform
    }

    func polish(_ text: String) async -> String {
        receivedInput = text
        return transform(text)
    }
}
