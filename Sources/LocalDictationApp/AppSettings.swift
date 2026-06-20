import Foundation

enum AppSettingsKeys {
    static let whisperExecutablePath = "whisperExecutablePath"
    static let modelPath = "modelPath"
    static let language = "language"
    static let pasteOnRelease = "pasteOnRelease"
    static let showOverlay = "showOverlay"
    static let inputDeviceUID = "inputDeviceUID"
    static let cleanUpTranscript = "cleanUpTranscript"
    static let polishWithAI = "polishWithAI"
    static let polishModelPath = "polishModelPath"
    static let customVocabulary = "customVocabulary"
    static let useHistoryContext = "useHistoryContext"
}

struct AppSettingsSnapshot: Equatable {
    var whisperExecutablePath: String
    var modelPath: String
    var language: String
    var pasteOnRelease: Bool
    var showOverlay: Bool
    var inputDeviceUID: String
    var cleanUpTranscript: Bool
    var polishWithAI: Bool
    var polishModelPath: String
    var customVocabulary: String
    var useHistoryContext: Bool

    var normalizedLanguage: String? {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static var current: AppSettingsSnapshot {
        registerDefaults()
        let defaults = UserDefaults.standard
        return AppSettingsSnapshot(
            whisperExecutablePath: defaults.string(forKey: AppSettingsKeys.whisperExecutablePath) ?? Defaults.whisperExecutablePath,
            modelPath: defaults.string(forKey: AppSettingsKeys.modelPath) ?? Defaults.modelPath,
            language: defaults.string(forKey: AppSettingsKeys.language) ?? Defaults.language,
            pasteOnRelease: defaults.object(forKey: AppSettingsKeys.pasteOnRelease) as? Bool ?? Defaults.pasteOnRelease,
            showOverlay: defaults.object(forKey: AppSettingsKeys.showOverlay) as? Bool ?? Defaults.showOverlay,
            inputDeviceUID: defaults.string(forKey: AppSettingsKeys.inputDeviceUID) ?? Defaults.inputDeviceUID,
            cleanUpTranscript: defaults.object(forKey: AppSettingsKeys.cleanUpTranscript) as? Bool ?? Defaults.cleanUpTranscript,
            polishWithAI: defaults.object(forKey: AppSettingsKeys.polishWithAI) as? Bool ?? Defaults.polishWithAI,
            polishModelPath: defaults.string(forKey: AppSettingsKeys.polishModelPath) ?? Defaults.polishModelPath,
            customVocabulary: defaults.string(forKey: AppSettingsKeys.customVocabulary) ?? Defaults.customVocabulary,
            useHistoryContext: defaults.object(forKey: AppSettingsKeys.useHistoryContext) as? Bool ?? Defaults.useHistoryContext
        )
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            AppSettingsKeys.whisperExecutablePath: Defaults.whisperExecutablePath,
            AppSettingsKeys.modelPath: Defaults.modelPath,
            AppSettingsKeys.language: Defaults.language,
            AppSettingsKeys.pasteOnRelease: Defaults.pasteOnRelease,
            AppSettingsKeys.showOverlay: Defaults.showOverlay,
            AppSettingsKeys.inputDeviceUID: Defaults.inputDeviceUID,
            AppSettingsKeys.cleanUpTranscript: Defaults.cleanUpTranscript,
            AppSettingsKeys.polishWithAI: Defaults.polishWithAI,
            AppSettingsKeys.polishModelPath: Defaults.polishModelPath,
            AppSettingsKeys.customVocabulary: Defaults.customVocabulary,
            AppSettingsKeys.useHistoryContext: Defaults.useHistoryContext
        ])
    }

    enum Defaults {
        static let whisperExecutablePath = ""  // empty = auto-locate (bundled, then Homebrew)
        static let modelPath = "~/models/ggml-base.en.bin"
        static let language = "auto"
        static let pasteOnRelease = true
        static let showOverlay = true
        static let inputDeviceUID = ""  // empty = system default input
        static let cleanUpTranscript = true
        static let polishWithAI = false  // opt-in: needs the ~1.8GB model + resident llama-server
        static let polishModelPath = "~/models/Qwen2.5-3B-Instruct-Q4_K_M.gguf"
        static let customVocabulary = ""  // user terms/names/jargon to bias whisper toward
        static let useHistoryContext = true  // feed recent transcripts as context bias
    }
}
