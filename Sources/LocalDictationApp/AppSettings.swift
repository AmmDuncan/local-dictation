import Foundation

enum AppSettingsKeys {
    static let whisperExecutablePath = "whisperExecutablePath"
    static let modelPath = "modelPath"
    static let language = "language"
    static let pasteOnRelease = "pasteOnRelease"
    static let showOverlay = "showOverlay"
    static let inputDeviceUID = "inputDeviceUID"
    static let cleanUpTranscript = "cleanUpTranscript"
}

struct AppSettingsSnapshot: Equatable {
    var whisperExecutablePath: String
    var modelPath: String
    var language: String
    var pasteOnRelease: Bool
    var showOverlay: Bool
    var inputDeviceUID: String
    var cleanUpTranscript: Bool

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
            cleanUpTranscript: defaults.object(forKey: AppSettingsKeys.cleanUpTranscript) as? Bool ?? Defaults.cleanUpTranscript
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
            AppSettingsKeys.cleanUpTranscript: Defaults.cleanUpTranscript
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
    }
}
