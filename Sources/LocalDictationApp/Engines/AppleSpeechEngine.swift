import AVFAudio
import Foundation
import LocalDictationCore
import Speech

/// Failures specific to the Apple on-device speech engine. Kept separate from
/// `TranscriptionError` (which is whisper-shaped) so neither leaks the other's
/// vocabulary; `AppModel.userFacingMessage` maps these to plain UI copy.
enum AppleSpeechError: Error, LocalizedError {
    case localeNotInstalled(String)
    case assetInstallFailed(String)
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case let .localeNotInstalled(id):
            "The on-device speech model for \(id) isn't installed yet."
        case let .assetInstallFailed(reason):
            "Couldn't install the on-device speech model: \(reason)"
        case let .recognitionFailed(reason):
            "Apple speech recognition failed: \(reason)"
        }
    }

    /// Plain-language copy for the overlay/menu — no locale ids or framework detail.
    var userMessage: String {
        switch self {
        case .localeNotInstalled, .assetInstallFailed:
            "The Apple speech model is still setting up. Try again in a moment, or switch to the Whisper engine in Settings."
        case .recognitionFailed:
            "Couldn't transcribe that with the Apple engine. Please try again."
        }
    }
}

/// On-device transcription via Apple's SpeechAnalyzer/SpeechTranscriber (macOS 26+).
/// Fully local: the language-model asset is downloaded once by macOS. In-process
/// and ANE-backed — no subprocess, no bundled model. `contextualStrings` biases
/// recognition toward the user's vocabulary, the direct analogue of whisper's
/// `--prompt`.
@available(macOS 26, *)
struct AppleSpeechEngine: TranscriptionEngine {
    let locale: Locale
    let contextualStrings: [String]

    init(localeID: String = "en-US", contextualStrings: [String] = []) {
        // SpeechTranscriber wants a language locale (e.g. "en-US"); "auto" and
        // bare "en" are normalized to a concrete recognizer locale.
        let normalized = (localeID == "auto" || localeID.isEmpty) ? "en-US" : localeID
        self.locale = Locale(identifier: normalized.contains("-") ? normalized : "\(normalized)-US")
        self.contextualStrings = Array(contextualStrings.prefix(300))
    }

    func transcribe(audioFile url: URL) async throws -> String {
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        try await ensureModelInstalled(for: transcriber)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if !contextualStrings.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings = [.general: contextualStrings]
            try await analyzer.setContext(context)
        }

        let audio: AVAudioFile
        do {
            audio = try AVAudioFile(forReading: url)
        } catch {
            throw AppleSpeechError.recognitionFailed("couldn't read audio: \(error.localizedDescription)")
        }

        async let transcript: AttributedString = transcriber.results.reduce(
            into: AttributedString("")) { partial, result in
            partial.append(result.text)
            partial.append(AttributedString(" "))
        }

        do {
            if let last = try await analyzer.analyzeSequence(from: audio) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            return String((try await transcript).characters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw AppleSpeechError.recognitionFailed(error.localizedDescription)
        }
    }

    private func ensureModelInstalled(for transcriber: SpeechTranscriber) async throws {
        let installed = await SpeechTranscriber.installedLocales.contains {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }
        if installed { return }
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        } catch {
            throw AppleSpeechError.assetInstallFailed(error.localizedDescription)
        }
    }
}
