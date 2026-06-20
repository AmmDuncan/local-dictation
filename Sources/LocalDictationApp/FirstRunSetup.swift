import Foundation

/// One-time setup for brand-new installs so a first-time user lands on good
/// defaults instead of the weakest config. Only touches a *completely fresh*
/// preferences domain — an existing user's choices are never overridden.
enum FirstRunSetup {
    private static let marker = "hasCompletedFirstRun"

    static func applyIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: marker) else { return }
        defer { defaults.set(true, forKey: marker) }

        // `persistentDomain` excludes registered defaults, so an empty domain means
        // the user has never set anything — a true fresh install.
        let bundleID = Bundle.main.bundleIdentifier ?? "dev.ammiel.local-dictation"
        let persisted = defaults.persistentDomain(forName: bundleID) ?? [:]
        guard persisted.isEmpty else { return }

        // New installs default to the recommended model (large-v3-turbo) rather
        // than base.en — the Models tab / health strip then prompts the one-time
        // download. Cleanup is already on by default; polish stays opt-in.
        defaults.set("~/models/ggml-large-v3-turbo.bin", forKey: AppSettingsKeys.modelPath)
    }
}
