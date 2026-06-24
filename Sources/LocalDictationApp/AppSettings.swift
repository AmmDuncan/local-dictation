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
    static let useDefaultVocabulary = "useDefaultVocabulary"
    static let useContextAwareness = "useContextAwareness"
    static let useScreenOCR = "useScreenOCR"
    static let useTextReplacements = "useTextReplacements"
    static let textReplacements = "textReplacements"
    static let insertionMethod = "insertionMethod"
    static let smartSpacing = "smartSpacing"
    static let saveHistory = "saveHistory"
    static let rejectedBuiltInSwaps = "rejectedBuiltInSwaps"
    static let liveReinsertionEnabled = "liveReinsertionEnabled"
    static let logCorrections = "logCorrections"
    // Crash reporting (handled by CrashReporter, not the dictation snapshot).
    static let crashReportingEnabled = "crashReportingEnabled"
    static let crashReportConsentAsked = "crashReportConsentAsked"
    static let contextSubstitutionEnabled = "contextSubstitutionEnabled"
    static let contextSubstitutionCountdown = "contextSubstitutionCountdown"
    static let rejectedContextSubSwaps = "rejectedContextSubSwaps"
    // Polish visibility (runtime counters, not user-facing settings): the lifetime
    // tally shown in the readiness strip, and the self-quieting first-run proof
    // streak shown on the HUD (reset when the polish model changes).
    static let polishAppliedCount = "polishAppliedCount"
    static let polishHeldBackCount = "polishHeldBackCount"
    static let polishProofShown = "polishProofShown"
    static let polishProofModelPath = "polishProofModelPath"
}

/// First-run "Polished" HUD streak length and a comma-grouped tally formatter,
/// kept here so the overlay, readiness strip, and counter logic agree.
enum PolishProof {
    /// How many of the first successful (applied) polishes show the HUD "Polished"
    /// sub-line before it auto-quiets forever. Single knob (Ammiel may tune 3…7).
    static let streakLength = 5

    static func grouped(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

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
    var useDefaultVocabulary: Bool
    var useContextAwareness: Bool
    var useScreenOCR: Bool
    var useTextReplacements: Bool
    var textReplacements: String
    var insertionMethod: String
    var smartSpacing: Bool
    var saveHistory: Bool
    var rejectedBuiltInSwaps: String
    var liveReinsertionEnabled: Bool
    var logCorrections: Bool
    var contextSubstitutionEnabled: Bool
    var contextSubstitutionCountdown: Double
    var rejectedContextSubSwaps: String

    var normalizedLanguage: String? {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var insertion: InsertionMethod { InsertionMethod(rawValue: insertionMethod) ?? .paste }

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
            useDefaultVocabulary: defaults.object(forKey: AppSettingsKeys.useDefaultVocabulary) as? Bool ?? Defaults.useDefaultVocabulary,
            useContextAwareness: defaults.object(forKey: AppSettingsKeys.useContextAwareness) as? Bool ?? Defaults.useContextAwareness,
            useScreenOCR: defaults.object(forKey: AppSettingsKeys.useScreenOCR) as? Bool ?? Defaults.useScreenOCR,
            useTextReplacements: defaults.object(forKey: AppSettingsKeys.useTextReplacements) as? Bool ?? Defaults.useTextReplacements,
            textReplacements: defaults.string(forKey: AppSettingsKeys.textReplacements) ?? Defaults.textReplacements,
            insertionMethod: defaults.string(forKey: AppSettingsKeys.insertionMethod) ?? Defaults.insertionMethod,
            smartSpacing: defaults.object(forKey: AppSettingsKeys.smartSpacing) as? Bool ?? Defaults.smartSpacing,
            saveHistory: defaults.object(forKey: AppSettingsKeys.saveHistory) as? Bool ?? Defaults.saveHistory,
            rejectedBuiltInSwaps: defaults.string(forKey: AppSettingsKeys.rejectedBuiltInSwaps) ?? Defaults.rejectedBuiltInSwaps,
            liveReinsertionEnabled: defaults.object(forKey: AppSettingsKeys.liveReinsertionEnabled) as? Bool ?? Defaults.liveReinsertionEnabled,
            logCorrections: defaults.object(forKey: AppSettingsKeys.logCorrections) as? Bool ?? Defaults.logCorrections,
            contextSubstitutionEnabled: defaults.object(forKey: AppSettingsKeys.contextSubstitutionEnabled) as? Bool ?? Defaults.contextSubstitutionEnabled,
            contextSubstitutionCountdown: defaults.object(forKey: AppSettingsKeys.contextSubstitutionCountdown) as? Double ?? Defaults.contextSubstitutionCountdown,
            rejectedContextSubSwaps: defaults.string(forKey: AppSettingsKeys.rejectedContextSubSwaps) ?? Defaults.rejectedContextSubSwaps
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
            AppSettingsKeys.useDefaultVocabulary: Defaults.useDefaultVocabulary,
            AppSettingsKeys.useContextAwareness: Defaults.useContextAwareness,
            AppSettingsKeys.useScreenOCR: Defaults.useScreenOCR,
            AppSettingsKeys.useTextReplacements: Defaults.useTextReplacements,
            AppSettingsKeys.textReplacements: Defaults.textReplacements,
            AppSettingsKeys.insertionMethod: Defaults.insertionMethod,
            AppSettingsKeys.smartSpacing: Defaults.smartSpacing,
            AppSettingsKeys.saveHistory: Defaults.saveHistory,
            AppSettingsKeys.rejectedBuiltInSwaps: Defaults.rejectedBuiltInSwaps,
            AppSettingsKeys.liveReinsertionEnabled: Defaults.liveReinsertionEnabled,
            AppSettingsKeys.logCorrections: Defaults.logCorrections,
            AppSettingsKeys.contextSubstitutionEnabled: Defaults.contextSubstitutionEnabled,
            AppSettingsKeys.contextSubstitutionCountdown: Defaults.contextSubstitutionCountdown,
            AppSettingsKeys.rejectedContextSubSwaps: Defaults.rejectedContextSubSwaps
        ])
        migrateLegacyLanguageDefault()
    }

    /// One-time bump of the legacy `auto` language to `en`. Short push-to-talk
    /// clips make Whisper's per-clip language auto-detect unreliable — on 1–3s of
    /// speech it mis-detects and injects stray foreign words — so English is the
    /// better default for an English user. Runs exactly once: a later explicit
    /// language choice (including deliberately re-selecting `auto`) is respected
    /// because the migration flag is already set.
    private static func migrateLegacyLanguageDefault() {
        let defaults = UserDefaults.standard
        let migrationKey = "languageDefaultMigratedToEn"
        let alreadyMigrated = defaults.bool(forKey: migrationKey)
        defaults.set(true, forKey: migrationKey)
        if let migrated = LanguageDefaultMigration.migratedValue(
            stored: defaults.string(forKey: AppSettingsKeys.language),
            alreadyMigrated: alreadyMigrated
        ) {
            defaults.set(migrated, forKey: AppSettingsKeys.language)
        }
    }

    enum Defaults {
        static let whisperExecutablePath = ""  // empty = auto-locate (bundled, then Homebrew)
        static let modelPath = "~/models/ggml-base.en.bin"
        // English by default: per-clip language auto-detect is unreliable on short
        // dictation clips. Non-English users can switch in Settings (see the
        // one-time `auto` → `en` migration in registerDefaults).
        static let language = "en"
        static let pasteOnRelease = true
        static let showOverlay = true
        static let inputDeviceUID = ""  // empty = system default input
        static let cleanUpTranscript = true
        static let polishWithAI = false  // opt-in: needs the ~3GB model + resident llama-server
        static let polishModelPath = "~/models/gemma-4-E2B-it-Q4_K_M.gguf"
        static let customVocabulary = ""  // user terms/names/jargon to bias whisper toward
        static let useDefaultVocabulary = true  // bias toward common terms (Claude, GitHub, …)
        // Use the focused app + caret-preceding text to bias recognition and enable
        // context-scoped command-mode corrections (e.g. "me" -> "main" after
        // `git push origin`). AX-only (no new permission), transient, on by default.
        static let useContextAwareness = true
        // OCR the focused window (Vision) as a fallback for apps that expose no
        // accessibility text (canvas / some Chromium). Off by default: needs Screen
        // Recording permission, so it's strictly opt-in.
        static let useScreenOCR = false
        static let useTextReplacements = false
        static let textReplacements = ""
        static let insertionMethod = InsertionMethod.paste.rawValue
        static let smartSpacing = false  // opt-in: needs accessibility to read caret context
        static let saveHistory = true
        static let rejectedBuiltInSwaps = ""  // JSON [String] of rejected built-in swap identities (suppression set)
        static let liveReinsertionEnabled = false  // experimental: AX select-verify-replace of the current instance
        static let logCorrections = true  // log dictations + their edits for the Learn-tab review queue
        static let contextSubstitutionEnabled = false  // experimental: constrained LLM swap with countdown confirm
        static let contextSubstitutionCountdown: Double = 5.0
        static let rejectedContextSubSwaps = ""
    }
}
