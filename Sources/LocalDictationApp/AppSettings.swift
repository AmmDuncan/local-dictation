import Foundation
import LocalDictationCore

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
    static let useDefaultVocabulary = "useDefaultVocabulary"
    static let dictationMode = "dictationMode"
    static let useTextReplacements = "useTextReplacements"
    static let textReplacements = "textReplacements"
    static let insertionMethod = "insertionMethod"
    static let smartSpacing = "smartSpacing"
    static let activationMode = "activationMode"
    static let useAppProfiles = "useAppProfiles"
    static let appProfiles = "appProfiles"
    static let saveHistory = "saveHistory"
}

/// How a dictation key-press behaves.
enum ActivationMode: String { case hold, toggle }
/// How transcribed text reaches the cursor.
enum InsertionMethod: String { case paste, keystroke }

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
    var useDefaultVocabulary: Bool
    var dictationMode: String
    var useTextReplacements: Bool
    var textReplacements: String
    var insertionMethod: String
    var smartSpacing: Bool
    var activationMode: String
    var useAppProfiles: Bool
    var appProfiles: [AppProfile]
    var saveHistory: Bool

    var normalizedLanguage: String? {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The globally-selected output mode (falls back to clean for unknown values).
    var mode: DictationMode { DictationMode(rawValue: dictationMode) ?? .clean }
    var activation: ActivationMode { ActivationMode(rawValue: activationMode) ?? .hold }
    var insertion: InsertionMethod { InsertionMethod(rawValue: insertionMethod) ?? .paste }

    static var current: AppSettingsSnapshot {
        registerDefaults()
        let defaults = UserDefaults.standard
        let profiles = defaults.data(forKey: AppSettingsKeys.appProfiles)
            .flatMap { try? JSONDecoder().decode([AppProfile].self, from: $0) } ?? []
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
            useHistoryContext: defaults.object(forKey: AppSettingsKeys.useHistoryContext) as? Bool ?? Defaults.useHistoryContext,
            useDefaultVocabulary: defaults.object(forKey: AppSettingsKeys.useDefaultVocabulary) as? Bool ?? Defaults.useDefaultVocabulary,
            dictationMode: defaults.string(forKey: AppSettingsKeys.dictationMode) ?? Defaults.dictationMode,
            useTextReplacements: defaults.object(forKey: AppSettingsKeys.useTextReplacements) as? Bool ?? Defaults.useTextReplacements,
            textReplacements: defaults.string(forKey: AppSettingsKeys.textReplacements) ?? Defaults.textReplacements,
            insertionMethod: defaults.string(forKey: AppSettingsKeys.insertionMethod) ?? Defaults.insertionMethod,
            smartSpacing: defaults.object(forKey: AppSettingsKeys.smartSpacing) as? Bool ?? Defaults.smartSpacing,
            activationMode: defaults.string(forKey: AppSettingsKeys.activationMode) ?? Defaults.activationMode,
            useAppProfiles: defaults.object(forKey: AppSettingsKeys.useAppProfiles) as? Bool ?? Defaults.useAppProfiles,
            appProfiles: profiles,
            saveHistory: defaults.object(forKey: AppSettingsKeys.saveHistory) as? Bool ?? Defaults.saveHistory
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
            AppSettingsKeys.useHistoryContext: Defaults.useHistoryContext,
            AppSettingsKeys.useDefaultVocabulary: Defaults.useDefaultVocabulary,
            AppSettingsKeys.dictationMode: Defaults.dictationMode,
            AppSettingsKeys.useTextReplacements: Defaults.useTextReplacements,
            AppSettingsKeys.textReplacements: Defaults.textReplacements,
            AppSettingsKeys.insertionMethod: Defaults.insertionMethod,
            AppSettingsKeys.smartSpacing: Defaults.smartSpacing,
            AppSettingsKeys.activationMode: Defaults.activationMode,
            AppSettingsKeys.useAppProfiles: Defaults.useAppProfiles,
            AppSettingsKeys.saveHistory: Defaults.saveHistory
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
        static let useDefaultVocabulary = true  // bias toward common terms (Claude, GitHub, …)
        static let dictationMode = DictationMode.clean.rawValue
        static let useTextReplacements = false
        static let textReplacements = ""
        static let insertionMethod = InsertionMethod.paste.rawValue
        static let smartSpacing = false  // opt-in: needs accessibility to read caret context
        static let activationMode = ActivationMode.hold.rawValue
        static let useAppProfiles = false
        static let saveHistory = true
    }
}
