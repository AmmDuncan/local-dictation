import Foundation

public protocol TranscriptionEngine: Sendable {
    func transcribe(audioFile: URL) async throws -> String
}

public struct WhisperCLIConfiguration: Equatable, Sendable {
    public var executablePath: String
    public var modelPath: String
    public var language: String?
    public var timeoutSeconds: TimeInterval
    /// Beam width. 1 = greedy decoding (~2x faster, fine for clean dictation).
    public var beamSize: Int
    /// Silero VAD model path. When set, only speech segments are transcribed —
    /// silence/whistle/noise produce nothing instead of hallucinated words.
    public var vadModelPath: String?

    public init(
        executablePath: String,
        modelPath: String,
        language: String?,
        timeoutSeconds: TimeInterval = 60,
        beamSize: Int = 1,
        vadModelPath: String? = nil
    ) {
        self.executablePath = executablePath
        self.modelPath = modelPath
        self.language = language
        self.timeoutSeconds = timeoutSeconds
        self.beamSize = beamSize
        self.vadModelPath = vadModelPath
    }
}

public enum TranscriptionError: Error, Equatable, Sendable, CustomStringConvertible {
    case missingExecutable(String)
    case missingModel(String)
    case missingAudioFile(String)
    case processFailed(Int32, String)
    case timedOut(TimeInterval)
    case emptyTranscript

    public var description: String {
        switch self {
        case let .missingExecutable(path):
            "whisper-cli was not found or is not executable at \(path)."
        case let .missingModel(path):
            "The Whisper model file was not found at \(path)."
        case let .missingAudioFile(path):
            "The recorded audio file was not found at \(path)."
        case let .processFailed(status, message):
            "whisper-cli failed with status \(status): \(message)"
        case let .timedOut(seconds):
            "whisper-cli did not finish within \(Int(seconds)) seconds and was stopped."
        case .emptyTranscript:
            "whisper-cli completed but returned no transcript."
        }
    }
}

// Surface the friendly `description` through `localizedDescription` too — without
// this, callers using `error.localizedDescription` get the useless bridged
// "The operation couldn't be completed. (… error N.)".
extension TranscriptionError: LocalizedError {
    public var errorDescription: String? { description }
}

public enum WhisperTranscriptParser {
    public static func parse(
        standardOutput: String,
        standardError: String,
        transcriptFileContents: String?
    ) -> String {
        if let transcriptFileContents {
            let sidecarText = normalize(transcriptFileContents)
            if !sidecarText.isEmpty {
                return sidecarText
            }
        }

        let cleanedLines = standardOutput
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let cleaned = removeTimestamp(from: String(line))
                guard !cleaned.isEmpty, !isWhisperLog(cleaned) else {
                    return nil
                }
                return cleaned
            }

        return normalize(cleanedLines.joined(separator: " "))
    }

    /// Removes whisper's non-speech annotations (`[BLANK_AUDIO]`, `[ Silence ]`,
    /// `(blank audio)`, `[MUSIC]`, …). Used for what gets *typed* — the overlay
    /// still shows the raw transcript. If the whole thing was one such token,
    /// the result is "" so nothing is inserted.
    public static func strippedForInsertion(_ text: String) -> String {
        let base: String
        if let regex = nonSpeechRegex {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            base = normalize(regex.stringByReplacingMatches(in: text, range: range, withTemplate: " "))
        } else {
            base = text
        }
        // Nothing worth typing unless there's an actual letter or number — drops
        // silence/noise that whisper renders as bare punctuation like "." or ". .".
        return base.contains(where: { $0.isLetter || $0.isNumber }) ? base : ""
    }

    // Whisper wraps non-speech sounds in several styles: [BLANK_AUDIO], (music),
    // *whispers* / **whispering**, ♪ … ♪. Strip all of them from inserted text.
    private static let nonSpeechRegex = try? NSRegularExpression(
        pattern: #"\[[^\]]*\]|\([^)]*\)|\*{1,2}[^*]+\*{1,2}|♪[^♪]*♪|♪"#
    )

    private static func normalize(_ value: String) -> String {
        value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let timestampRegex = try? NSRegularExpression(
        pattern: #"^\s*\[\d{2}:\d{2}:\d{2}\.\d{3}\s+-->\s+\d{2}:\d{2}:\d{2}\.\d{3}\]\s*"#
    )

    private static func removeTimestamp(from line: String) -> String {
        guard let regex = timestampRegex else {
            return line.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        let cleaned = regex.stringByReplacingMatches(in: line, range: range, withTemplate: "")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isWhisperLog(_ line: String) -> Bool {
        let prefixes = [
            "whisper_",
            "ggml_",
            "system_info:",
            "main:",
            "load_time",
            "falling back"
        ]

        return prefixes.contains { line.localizedCaseInsensitiveContains($0) }
    }
}

public struct WhisperCLITranscriptionEngine: TranscriptionEngine {
    public var configuration: WhisperCLIConfiguration

    public init(configuration: WhisperCLIConfiguration) {
        self.configuration = configuration
    }

    public func transcribe(audioFile: URL) async throws -> String {
        try validate(audioFile: audioFile)

        let configuration = configuration
        return try await Task.detached(priority: .userInitiated) {
            try runWhisper(configuration: configuration, audioFile: audioFile)
        }.value
    }

    private func validate(audioFile: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: configuration.executablePath, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isExecutableFile(atPath: configuration.executablePath)
        else {
            throw TranscriptionError.missingExecutable(configuration.executablePath)
        }

        guard FileManager.default.fileExists(atPath: configuration.modelPath, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            throw TranscriptionError.missingModel(configuration.modelPath)
        }

        guard FileManager.default.fileExists(atPath: audioFile.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            throw TranscriptionError.missingAudioFile(audioFile.path)
        }
    }
}

private final class WhisperRunCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var err = Data()
    private var didTimeOut = false

    func append(_ data: Data, isStdout: Bool) {
        lock.lock()
        if isStdout { out.append(data) } else { err.append(data) }
        lock.unlock()
    }

    func markTimedOut() {
        lock.lock()
        didTimeOut = true
        lock.unlock()
    }

    var standardOutput: Data {
        lock.lock(); defer { lock.unlock() }
        return out
    }

    var standardError: Data {
        lock.lock(); defer { lock.unlock() }
        return err
    }

    var timedOut: Bool {
        lock.lock(); defer { lock.unlock() }
        return didTimeOut
    }
}

private func runWhisper(configuration: WhisperCLIConfiguration, audioFile: URL) throws -> String {
    let outputBase = FileManager.default.temporaryDirectory
        .appendingPathComponent("local-dictation-\(UUID().uuidString)")
    let transcriptURL = URL(fileURLWithPath: outputBase.path + ".txt")
    // Always remove the sidecar transcript, on every exit path (incl. processFailed).
    defer { try? FileManager.default.removeItem(at: transcriptURL) }
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()

    process.executableURL = URL(fileURLWithPath: configuration.executablePath)
    process.arguments = WhisperCLICommand.arguments(
        configuration: configuration,
        audioFile: audioFile,
        outputBase: outputBase
    )
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()

    let collector = WhisperRunCollector()
    let readGroup = DispatchGroup()
    for (pipe, isStdout) in [(stdout, true), (stderr, false)] {
        readGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            collector.append(data, isStdout: isStdout)
            readGroup.leave()
        }
    }

    let watchdog = DispatchWorkItem {
        collector.markTimedOut()
        process.terminate()
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + configuration.timeoutSeconds, execute: watchdog)

    process.waitUntilExit()
    watchdog.cancel()
    readGroup.wait()

    let didTimeOut = collector.timedOut
    let standardOutput = String(data: collector.standardOutput, encoding: .utf8) ?? ""
    let standardError = String(data: collector.standardError, encoding: .utf8) ?? ""

    // Only a timeout that the process LOST counts: if it exited 0 in the race
    // window before the watchdog's terminate(), the transcript is valid.
    if didTimeOut, process.terminationStatus != 0 {
        throw TranscriptionError.timedOut(configuration.timeoutSeconds)
    }

    guard process.terminationStatus == 0 else {
        throw TranscriptionError.processFailed(
            process.terminationStatus,
            standardError.isEmpty ? standardOutput : standardError
        )
    }

    let transcriptFileContents = try? String(contentsOf: transcriptURL, encoding: .utf8)

    let transcript = WhisperTranscriptParser.parse(
        standardOutput: standardOutput,
        standardError: standardError,
        transcriptFileContents: transcriptFileContents
    )

    guard !transcript.isEmpty else {
        throw TranscriptionError.emptyTranscript
    }

    return transcript
}

/// Builds the whisper-cli argument vector. Exposed for testing the beam-clamp
/// and language-suppression rules.
public enum WhisperCLICommand {
    public static func arguments(
        configuration: WhisperCLIConfiguration,
        audioFile: URL,
        outputBase: URL
    ) -> [String] {
        var arguments = [
            "-m", configuration.modelPath,
            "-f", audioFile.path,
            "-otxt",
            "-of", outputBase.path,
            "-nt",
            "-bs", String(max(1, configuration.beamSize)),
            "-bo", String(max(1, configuration.beamSize))
        ]

        if let language = configuration.language?.trimmingCharacters(in: .whitespacesAndNewlines),
           !language.isEmpty,
           language.lowercased() != "auto" {
            arguments.append(contentsOf: ["-l", language])
        }

        if let vad = configuration.vadModelPath, !vad.isEmpty {
            arguments.append(contentsOf: ["--vad", "-vm", vad])
        }

        return arguments
    }
}
