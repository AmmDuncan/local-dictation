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
    /// Curated polish models. Gemma 4 E2B is recommended for context substitution
    /// (fewest false swaps in A/B harness). Qwen 3.5-4B is smaller and still solid
    /// for plain polish. NOTE: Qwen3-family is hybrid-thinking — its `<think>` blocks
    /// would pollute the polish + trip the faithfulness guard, so the request body
    /// disables thinking (see `TranscriptPolisher.chatRequestBody`).
    static let all: [PolishModel] = [
        PolishModel(
            id: "gemma-4-e2b",
            displayName: "Gemma 4 E2B",
            // Local filename (saved under this regardless of the URL basename). The
            // bartowski source is `google_…`; we drop the prefix for a cleaner name.
            filename: "gemma-4-E2B-it-Q4_K_M.gguf",
            sizeBytes: 3_462_678_272,
            sha256: "b5310340b3a23d31655d7119d100d5df1b2d8ee17b3ca8b0a23ad7e9eb5fa705",
            url: URL(string: "https://huggingface.co/bartowski/google_gemma-4-E2B-it-GGUF/resolve/main/google_gemma-4-E2B-it-Q4_K_M.gguf")!,
            note: "Recommended",
            detail: "Safest · best accuracy · fewest false swaps for context substitution"
        ),
        PolishModel(
            id: "qwen3.5-4b",
            displayName: "Qwen 3.5 4B",
            filename: "Qwen_Qwen3.5-4B-Q4_K_M.gguf",
            sizeBytes: 3_013_027_808,
            sha256: "13c16f426047e2de38cd075bdade4a7bcbc8c774384876f677740cda65f8a983",
            url: URL(string: "https://huggingface.co/bartowski/Qwen_Qwen3.5-4B-GGUF/resolve/main/Qwen_Qwen3.5-4B-Q4_K_M.gguf")!,
            note: nil,
            detail: "Smallest download · more false corrections"
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
