import Foundation

/// A per-application dictation profile: when the frontmost app matches
/// `bundleIdentifier`, dictation uses this profile's mode + cleanup settings
/// instead of the global default. Resolution is pure (the frontmost-app lookup
/// itself lives in the app layer via `NSWorkspace`).
public struct AppProfile: Equatable, Sendable, Codable, Identifiable {
    public var id: String { bundleIdentifier }
    /// App bundle identifier this profile applies to, e.g. "com.apple.dt.Xcode".
    public var bundleIdentifier: String
    /// Human label for the settings list (the app's display name).
    public var appName: String
    public var mode: DictationMode
    public var cleanUp: Bool
    public var polish: Bool

    public init(
        bundleIdentifier: String,
        appName: String,
        mode: DictationMode,
        cleanUp: Bool,
        polish: Bool
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.mode = mode
        self.cleanUp = cleanUp
        self.polish = polish
    }
}

public enum AppProfileResolver {
    /// The profile to use for `bundleID`, or `fallback` when no profile matches
    /// (or the frontmost app is unknown). Matching is case-insensitive.
    public static func resolve(
        bundleID: String?,
        profiles: [AppProfile],
        fallback: AppProfile
    ) -> AppProfile {
        guard let bundleID else { return fallback }
        let match = profiles.first {
            $0.bundleIdentifier.caseInsensitiveCompare(bundleID) == .orderedSame
        }
        return match ?? fallback
    }
}
