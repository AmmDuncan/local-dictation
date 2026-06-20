import Foundation

/// Resolves the whisper-cli executable to use. Preference order:
/// 1. an explicit user override (Advanced tab) that exists,
/// 2. the copy bundled inside the .app (zero-setup for friends),
/// 3. a Homebrew install (`/opt/homebrew` Apple Silicon, `/usr/local` Intel).
enum WhisperLocator {
    /// Fixed location the bundled whisper-cli loads its ggml backend plugins
    /// from (its libggml has this path baked in by build-app.sh). Must match
    /// `LD_GGML_BACKENDS_LINK` in build-app.sh byte-for-byte.
    static let backendsLinkPath = "/tmp/local-dictation-ggml-backends-dir01"

    static var bundledPath: String? {
        let path = Bundle.main.bundlePath + "/Contents/Helpers/whisper-cli"
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    /// The bundled Silero VAD model (else a copy in ~/models). Nil if unavailable
    /// — callers then run without VAD.
    static func resolvedVadModel() -> String? {
        let bundled = Bundle.main.bundlePath + "/Contents/Resources/ggml-silero-v5.1.2.bin"
        if FileManager.default.fileExists(atPath: bundled) {
            return bundled
        }
        let home = "~/models/ggml-silero-v5.1.2.bin".expandingTildeInPath
        return FileManager.default.fileExists(atPath: home) ? home : nil
    }

    /// The `whisper-server` executable (bundled, else Homebrew). Used to keep a
    /// model resident across dictations.
    static func resolvedServer() -> String? {
        let bundled = Bundle.main.bundlePath + "/Contents/Helpers/whisper-server"
        if FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        for candidate in ["/opt/homebrew/bin/whisper-server", "/usr/local/bin/whisper-server"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// The `llama-server` executable (bundled, else Homebrew) for the optional
    /// LLM polish pass. Nil if unavailable → polish stays off.
    static func resolvedLlamaServer() -> String? {
        let bundled = Bundle.main.bundlePath + "/Contents/Helpers/llama-server"
        if FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        for candidate in ["/opt/homebrew/bin/llama-server", "/usr/local/bin/llama-server"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static var bundledFrameworks: String? {
        let path = Bundle.main.bundlePath + "/Contents/Frameworks"
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return exists && isDir.boolValue ? path : nil
    }

    /// Point the baked plugin path at the bundled Frameworks via a symlink.
    /// Idempotent; safe to call before every dictation (in case /tmp was cleared).
    static func ensureBackendsLinked() {
        guard let frameworks = bundledFrameworks else { return }
        let fm = FileManager.default
        if let dest = try? fm.destinationOfSymbolicLink(atPath: backendsLinkPath), dest == frameworks {
            return
        }
        try? fm.removeItem(atPath: backendsLinkPath)
        try? fm.createSymbolicLink(atPath: backendsLinkPath, withDestinationPath: frameworks)
    }

    static func resolved(configured: String) -> String {
        let override = configured.expandingTildeInPath
        if !override.isEmpty, FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        if let bundled = bundledPath {
            return bundled
        }
        for candidate in ["/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        // Nothing found — return the override (if any) so the error names it,
        // otherwise the conventional path so the message is recognizable.
        return override.isEmpty ? "/opt/homebrew/bin/whisper-cli" : override
    }
}
