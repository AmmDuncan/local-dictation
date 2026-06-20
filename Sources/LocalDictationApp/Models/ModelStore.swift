import Foundation
import Observation

/// Tracks which catalog models are present on disk, downloads missing ones with
/// progress, and switches the active model. Downloads stream to a temporary file
/// and are atomically moved into place, so a partial download never reads as
/// installed.
@MainActor
@Observable
final class ModelStore {
    private(set) var installedIDs: Set<String> = []
    private(set) var progress: [String: Double] = [:]
    private(set) var errors: [String: String] = [:]

    /// Directory holding the ggml files — the folder of the configured model
    /// path (so the existing `~/models` default keeps working).
    let directory: URL

    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var observations: [String: NSKeyValueObservation] = [:]

    init() {
        let modelPath = AppSettingsSnapshot.current.modelPath.expandingTildeInPath
        let parent = (modelPath as NSString).deletingLastPathComponent
        let resolved = parent.isEmpty ? "~/models".expandingTildeInPath : parent
        directory = URL(fileURLWithPath: resolved)
        refresh()
    }

    var activeFilename: String {
        (AppSettingsSnapshot.current.modelPath.expandingTildeInPath as NSString).lastPathComponent
    }

    func isInstalled(_ model: WhisperModel) -> Bool { installedIDs.contains(model.id) }
    func isActive(_ model: WhisperModel) -> Bool { model.filename == activeFilename }
    func isDownloading(_ model: WhisperModel) -> Bool { progress[model.id] != nil }

    func refresh() {
        var present: Set<String> = []
        for model in ModelCatalog.all {
            let path = directory.appendingPathComponent(model.filename).path
            if let size = fileSize(path), Double(size) > Double(model.sizeBytes) * 0.5 {
                present.insert(model.id)
            }
        }
        installedIDs = present
    }

    func select(_ model: WhisperModel) {
        guard isInstalled(model) else { return }
        let path = directory.appendingPathComponent(model.filename).path
        UserDefaults.standard.set(path, forKey: AppSettingsKeys.modelPath)
    }

    func download(_ model: WhisperModel) {
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

    func cancel(_ model: WhisperModel) {
        tasks[model.id]?.cancel()
        cleanup(model.id)
        progress[model.id] = nil
    }

    private func finish(_ model: WhisperModel, tempURL: URL?, response: URLResponse?, error: Error?, destination: URL) {
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

    /// Streams the downloaded file through SHA-256 off the main thread; deletes
    /// it and surfaces an error if it doesn't match the pinned digest.
    private func verifyChecksum(_ model: WhisperModel, at url: URL) {
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
