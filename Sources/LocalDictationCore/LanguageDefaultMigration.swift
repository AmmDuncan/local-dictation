import Foundation

/// Decides whether a stored dictation-language preference should be migrated off
/// the legacy `auto` default. Pure so the decision is unit-testable; the app owns
/// the UserDefaults read/write around it.
public enum LanguageDefaultMigration {
    /// The replacement for a legacy `auto` language, or nil to leave the stored
    /// value untouched. English is chosen because per-clip language auto-detect is
    /// unreliable on short push-to-talk clips (it mis-detects on 1–3s of speech and
    /// injects stray foreign words). Returns nil once already migrated, or when the
    /// user holds any non-`auto` choice — a deliberate `auto` re-selection after
    /// migration is therefore respected.
    public static func migratedValue(stored: String?, alreadyMigrated: Bool) -> String? {
        guard !alreadyMigrated, stored == "auto" else { return nil }
        return "en"
    }
}
