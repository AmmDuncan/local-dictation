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
        await suite.run("Polish guardrail accepts faithful, rejects divergent", testPolishGuardrail)
        await suite.run("Polish request body + response parsing", testPolishRequestAndParsing)
        await suite.run("Whisper args omit language for auto/empty/nil", testWhisperArgsOmitLanguage)
        await suite.run("Whisper args clamp bad beam size", testWhisperArgsClampBeam)
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
