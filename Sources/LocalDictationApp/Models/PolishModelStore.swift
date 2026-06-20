import Foundation

/// A downloadable LLM (gguf) for the optional polish pass, run by llama-server.
/// Mirrors `WhisperModel` so the polish picker can reuse the same manager UI.
struct PolishModel: Identifiable, Hashable, DownloadableModel {
    let id: String
    let displayName: String
    let filename: String
    let sizeBytes: Int64
    let sha256: String      // pinned digest; verified after download
    let url: URL
    let note: String?       // e.g. "Recommended"
    let detail: String      // one-line "fast · best for cleanup" descriptor

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

enum PolishModelCatalog {
    /// Curated polish models. Qwen 2.5-3B is the recommended default — it's the
    /// smallest that reliably follows the cleanup/corrector prompt and stops
    /// cleanly. Gemma 3 4B is offered as an alternative (it over-corrects more in
    /// Corrector mode; fine for the other modes).
    static let all: [PolishModel] = [
        PolishModel(
            id: "qwen2.5-3b",
            displayName: "Qwen 2.5 3B Instruct",
            filename: "Qwen2.5-3B-Instruct-Q4_K_M.gguf",
            sizeBytes: 1_929_903_264,
            sha256: "9c9f56a391a3abbd5b89d0245bf6106081bcc3173119d4229235dd9d23253f94",
            url: URL(string: "https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf")!,
            note: "Recommended",
            detail: "Fast · best-tested for cleanup & correction"
        ),
        PolishModel(
            id: "gemma-3-4b",
            displayName: "Gemma 3 4B Instruct",
            filename: "gemma-3-4b-it-Q4_K_M.gguf",
            sizeBytes: 2_489_757_856,
            sha256: "882e8d2db44dc554fb0ea5077cb7e4bc49e7342a1f0da57901c0802ea21a0863",
            url: URL(string: "https://huggingface.co/ggml-org/gemma-3-4b-it-GGUF/resolve/main/gemma-3-4b-it-Q4_K_M.gguf")!,
            note: nil,
            detail: "Newer knowledge · over-corrects more in Corrector mode"
        ),
    ]
}

/// The whisper `ModelStore`'s polish counterpart — same download/verify/select
/// machinery (inherited from `CatalogModelStore`), over the polish catalog and
/// the `polishModelPath` setting, plus a few helpers for the General-tab status.
@MainActor
final class PolishModelStore: CatalogModelStore {
    init() {
        super.init(catalog: PolishModelCatalog.all, activePathKey: AppSettingsKeys.polishModelPath)
    }

    /// The active model matched to the catalog (nil if a custom gguf is configured).
    var activeModel: PolishModel? { PolishModelCatalog.all.first { $0.filename == activeFilename } }

    /// Whether the configured polish model file actually exists (catalog or custom).
    var activeModelInstalled: Bool {
        let path = AppSettingsSnapshot.current.polishModelPath.expandingTildeInPath
        return (fileSize(path) ?? 0) > 100_000_000  // any real gguf is far larger
    }

    /// Display name for the active model — catalog name, else the file name.
    var activeModelName: String {
        activeModel?.displayName
            ?? (AppSettingsSnapshot.current.polishModelPath.expandingTildeInPath as NSString).lastPathComponent
    }
}
