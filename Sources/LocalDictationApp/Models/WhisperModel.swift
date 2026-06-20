import Foundation

/// A downloadable whisper.cpp ggml model. `sizeBytes` is the published f16 size,
/// used both for the UI and to sanity‑check a file on disk is fully downloaded.
struct WhisperModel: Identifiable, Hashable, DownloadableModel {
    let id: String
    let displayName: String
    let filename: String
    let sizeBytes: Int64
    let sha256: String     // pinned digest; verified after download
    let url: URL
    let language: String   // "English" or "Multilingual"
    let speed: String
    let accuracy: String
    let note: String?      // e.g. "Recommended"

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

enum ModelCatalog {
    /// Curated for an Apple-silicon dictation tool (see model research, 2026).
    /// large-v3-turbo is the recommended single model for both the live preview
    /// and the final pass on capable hardware.
    static let all: [WhisperModel] = [
        WhisperModel(
            id: "large-v3-turbo",
            displayName: "Large v3 Turbo",
            filename: "ggml-large-v3-turbo.bin",
            sizeBytes: 1_624_555_275,
            sha256: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!,
            language: "Multilingual",
            speed: "Fast",
            accuracy: "Best",
            note: "Recommended"
        ),
        WhisperModel(
            id: "large-v3-turbo-q5_0",
            displayName: "Large v3 Turbo (quantized)",
            filename: "ggml-large-v3-turbo-q5_0.bin",
            sizeBytes: 574_041_195,
            sha256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin")!,
            language: "Multilingual",
            speed: "Faster",
            accuracy: "Best",
            note: "Lighter"
        ),
        WhisperModel(
            id: "medium.en",
            displayName: "Medium",
            filename: "ggml-medium.en.bin",
            sizeBytes: 1_533_774_781,
            sha256: "cc37e93478338ec7700281a7ac30a10128929eb8f427dda2e865faa8f6da4356",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin")!,
            language: "English",
            speed: "Medium",
            accuracy: "High",
            note: nil
        ),
        WhisperModel(
            id: "small.en",
            displayName: "Small",
            filename: "ggml-small.en.bin",
            sizeBytes: 487_601_967,
            sha256: "c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin")!,
            language: "English",
            speed: "Fast",
            accuracy: "Good",
            note: nil
        ),
        WhisperModel(
            id: "base.en",
            displayName: "Base",
            filename: "ggml-base.en.bin",
            sizeBytes: 147_964_211,
            sha256: "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")!,
            language: "English",
            speed: "Faster",
            accuracy: "Basic",
            note: nil
        ),
        WhisperModel(
            id: "tiny.en",
            displayName: "Tiny",
            filename: "ggml-tiny.en.bin",
            sizeBytes: 77_704_715,
            sha256: "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin")!,
            language: "English",
            speed: "Fastest",
            accuracy: "Lowest",
            note: nil
        )
    ]
}
