import Foundation
import Observation

/// A downloadable LLM (gguf) for the optional polish pass, run by llama-server.
/// Mirrors `WhisperModel` so the polish picker can reuse the same manager UI.
struct PolishModel: Identifiable, Hashable {
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
    /// cleanly. (Gemma 3 4B is added once verified to behave the same way.)
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

/// Tracks which polish models are present, downloads missing ones with progress,
/// and switches the active one (by writing `polishModelPath`). Mirrors
/// `ModelStore`; downloads stream to a temp file and atomically move into place.
@MainActor
@Observable
final class PolishModelStore {
    private(set) var installedIDs: Set<String> = []
    private(set) var progress: [String: Double] = [:]
    private(set) var errors: [String: String] = [:]

    /// Directory holding the gguf files — the folder of the configured polish
    /// model path (so the existing `~/models` default keeps working).
    let directory: URL

    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var observations: [String: NSKeyValueObservation] = [:]

    init() {
        let path = AppSettingsSnapshot.current.polishModelPath.expandingTildeInPath
        let parent = (path as NSString).deletingLastPathComponent
        let resolved = parent.isEmpty ? "~/models".expandingTildeInPath : parent
        directory = URL(fileURLWithPath: resolved)
        refresh()
    }

    var activeFilename: String {
        (AppSettingsSnapshot.current.polishModelPath.expandingTildeInPath as NSString).lastPathComponent
    }

    func isInstalled(_ model: PolishModel) -> Bool { installedIDs.contains(model.id) }
    func isActive(_ model: PolishModel) -> Bool { model.filename == activeFilename }
    func isDownloading(_ model: PolishModel) -> Bool { progress[model.id] != nil }

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

    func refresh() {
        var present: Set<String> = []
        for model in PolishModelCatalog.all {
            let path = directory.appendingPathComponent(model.filename).path
            if let size = fileSize(path), Double(size) > Double(model.sizeBytes) * 0.5 {
                present.insert(model.id)
            }
        }
        installedIDs = present
    }

    func select(_ model: PolishModel) {
        guard isInstalled(model) else { return }
        let path = directory.appendingPathComponent(model.filename).path
        UserDefaults.standard.set(path, forKey: AppSettingsKeys.polishModelPath)
    }

    func download(_ model: PolishModel) {
        guard tasks[model.id] == nil else { return }
        errors[model.id] = nil
        progress[model.id] = 0
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = directory.appendingPathComponent(model.filename)
        let task = URLSession.shared.downloadTask(with: model.url) { [weak self] tempURL, response, error in
            Task { @MainActor in
                self?.finish(model, tempURL: tempURL, response: response, error: error, destination: destination)
            }
        }
        observations[model.id] = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in self?.progress[model.id] = fraction }
        }
        tasks[model.id] = task
        task.resume()
    }

    func cancel(_ model: PolishModel) {
        tasks[model.id]?.cancel()
        cleanup(model.id)
        progress[model.id] = nil
    }

    private func finish(_ model: PolishModel, tempURL: URL?, response: URLResponse?, error: Error?, destination: URL) {
        defer {
            cleanup(model.id)
            progress[model.id] = nil
        }

        if let error = error as NSError? {
            if error.code == NSURLErrorCancelled { return }
            errors[model.id] = ModelDownloads.friendlyMessage(for: error)
            return
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            errors[model.id] = "Couldn't reach the download server (HTTP \(http.statusCode)). Check your connection and try again."
            return
        }
        guard let tempURL else {
            errors[model.id] = "Download didn't complete. Please try again."
            return
        }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
        } catch {
            errors[model.id] = "Couldn't save the model. Please try again."
            return
        }
        refresh()
        verifyChecksum(model, at: destination)
    }

    private func verifyChecksum(_ model: PolishModel, at url: URL) {
        Task { @MainActor in
            let matches = await ModelDownloads.checksumMatches(url: url, expected: model.sha256)
            guard !matches else { return }
            try? FileManager.default.removeItem(at: url)
            errors[model.id] = "Integrity check failed — the download was corrupted or tampered with. Please try again."
            refresh()
        }
    }

    private func cleanup(_ id: String) {
        observations[id]?.invalidate()
        observations[id] = nil
        tasks[id] = nil
    }

    private func fileSize(_ path: String) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64
    }
}
