import Foundation
import Observation

/// A downloadable, checksum-pinned model file (whisper ggml or polish gguf).
/// Sendable so it can be captured in the download completion closure.
protocol DownloadableModel: Sendable {
    var id: String { get }
    var filename: String { get }
    var sizeBytes: Int64 { get }
    var sha256: String { get }
    var url: URL { get }
}

/// Shared store for a catalog of downloadable models: tracks which are present,
/// downloads missing ones with progress, verifies the pinned checksum, and
/// switches the active one by writing a settings key. `ModelStore` (whisper) and
/// `PolishModelStore` (polish) are thin subclasses differing only in catalog +
/// which settings key holds the active path. Downloads stream to a temp file and
/// atomically move into place, so a partial download never reads as installed.
@MainActor
@Observable
class CatalogModelStore {
    private(set) var installedIDs: Set<String> = []
    private(set) var progress: [String: Double] = [:]
    private(set) var errors: [String: String] = [:]

    /// Directory holding the model files — the folder of the configured active
    /// path (so the existing `~/models` default keeps working).
    let directory: URL

    let catalog: [any DownloadableModel]
    private let activePathKey: String

    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var observations: [String: NSKeyValueObservation] = [:]

    init(catalog: [any DownloadableModel], activePathKey: String, defaultDirectory: String = "~/models") {
        AppSettingsSnapshot.registerDefaults()
        self.catalog = catalog
        self.activePathKey = activePathKey
        let path = (UserDefaults.standard.string(forKey: activePathKey) ?? "").expandingTildeInPath
        let parent = (path as NSString).deletingLastPathComponent
        let resolved = parent.isEmpty ? defaultDirectory.expandingTildeInPath : parent
        directory = URL(fileURLWithPath: resolved)
        refresh()
    }

    var activeFilename: String {
        ((UserDefaults.standard.string(forKey: activePathKey) ?? "").expandingTildeInPath as NSString).lastPathComponent
    }

    func isInstalled(_ model: any DownloadableModel) -> Bool { installedIDs.contains(model.id) }
    func isActive(_ model: any DownloadableModel) -> Bool { model.filename == activeFilename }
    func isDownloading(_ model: any DownloadableModel) -> Bool { progress[model.id] != nil }

    func refresh() {
        var present: Set<String> = []
        for model in catalog {
            let path = directory.appendingPathComponent(model.filename).path
            if let size = fileSize(path), Double(size) > Double(model.sizeBytes) * 0.5 {
                present.insert(model.id)
            }
        }
        installedIDs = present
    }

    func select(_ model: any DownloadableModel) {
        guard isInstalled(model) else { return }
        let path = directory.appendingPathComponent(model.filename).path
        UserDefaults.standard.set(path, forKey: activePathKey)
    }

    func download(_ model: any DownloadableModel) {
        guard tasks[model.id] == nil else { return }
        errors[model.id] = nil
        progress[model.id] = 0
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let id = model.id
        let destination = directory.appendingPathComponent(model.filename)
        let task = URLSession.shared.downloadTask(with: model.url) { [weak self] tempURL, response, error in
            Task { @MainActor in
                self?.finish(model, tempURL: tempURL, response: response, error: error, destination: destination)
            }
        }
        observations[id] = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in self?.progress[id] = fraction }
        }
        tasks[id] = task
        task.resume()
    }

    func cancel(_ model: any DownloadableModel) {
        tasks[model.id]?.cancel()
        cleanup(model.id)
        progress[model.id] = nil
    }

    private func finish(_ model: any DownloadableModel, tempURL: URL?, response: URLResponse?, error: Error?, destination: URL) {
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

    /// Streams the downloaded file through SHA-256 off the main thread; deletes it
    /// and surfaces an error if it doesn't match the pinned digest.
    private func verifyChecksum(_ model: any DownloadableModel, at url: URL) {
        let expected = model.sha256
        let id = model.id
        Task { @MainActor in
            let matches = await ModelDownloads.checksumMatches(url: url, expected: expected)
            guard !matches else { return }
            try? FileManager.default.removeItem(at: url)
            errors[id] = "Integrity check failed — the download was corrupted or tampered with. Please try again."
            refresh()
        }
    }

    private func cleanup(_ id: String) {
        observations[id]?.invalidate()
        observations[id] = nil
        tasks[id] = nil
    }

    func fileSize(_ path: String) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64
    }
}
