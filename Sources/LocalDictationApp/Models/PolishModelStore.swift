import Foundation
import Observation

/// The single LLM used for the optional polish pass. Pinned like the whisper
/// models so a corrupted/tampered download is rejected.
enum PolishModel {
    static let filename = "Qwen2.5-3B-Instruct-Q4_K_M.gguf"
    static let displayName = "Qwen 2.5 3B Instruct (Q4_K_M)"
    static let sizeBytes: Int64 = 1_929_903_264
    static let sha256 = "9c9f56a391a3abbd5b89d0245bf6106081bcc3173119d4229235dd9d23253f94"
    static let url = URL(string: "https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf")!

    static var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

/// Downloads + verifies the single polish model into the configured location
/// (default ~/models). Mirrors `ModelStore`'s download → verify → atomic-move
/// flow for one fixed model; shares the checksum/error helpers via
/// `ModelDownloads`. (A generic file-downloader is the natural next dedup.)
@MainActor
@Observable
final class PolishModelStore {
    private(set) var isInstalled = false
    private(set) var progress: Double?  // nil = not downloading
    private(set) var error: String?

    let destination: URL

    private var task: URLSessionDownloadTask?
    private var observation: NSKeyValueObservation?

    init() {
        let path = AppSettingsSnapshot.current.polishModelPath.expandingTildeInPath
        destination = URL(fileURLWithPath: path)
        refresh()
    }

    func refresh() {
        if let size = fileSize(destination.path), Double(size) > Double(PolishModel.sizeBytes) * 0.5 {
            isInstalled = true
        } else {
            isInstalled = false
        }
    }

    func download() {
        guard task == nil else { return }
        error = nil
        progress = 0
        try? FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        let downloadTask = URLSession.shared.downloadTask(with: PolishModel.url) { [weak self] tempURL, response, error in
            Task { @MainActor in
                self?.finish(tempURL: tempURL, response: response, error: error)
            }
        }
        observation = downloadTask.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in self?.progress = fraction }
        }
        task = downloadTask
        downloadTask.resume()
    }

    func cancel() {
        task?.cancel()
        cleanup()
        progress = nil
    }

    private func finish(tempURL: URL?, response: URLResponse?, error downloadError: Error?) {
        defer {
            cleanup()
            progress = nil
        }

        if let downloadError = downloadError as NSError? {
            if downloadError.code == NSURLErrorCancelled { return }
            error = ModelDownloads.friendlyMessage(for: downloadError)
            return
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            error = "Couldn't reach the download server (HTTP \(http.statusCode)). Check your connection and try again."
            return
        }
        guard let tempURL else {
            error = "Download didn't complete. Please try again."
            return
        }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
        } catch {
            self.error = "Couldn't save the model. Please try again."
            return
        }
        refresh()
        verifyChecksum()
    }

    private func verifyChecksum() {
        Task { @MainActor in
            let matches = await ModelDownloads.checksumMatches(url: destination, expected: PolishModel.sha256)
            guard !matches else { return }
            try? FileManager.default.removeItem(at: destination)
            error = "Integrity check failed — the download was corrupted or tampered with. Please try again."
            refresh()
        }
    }

    private func cleanup() {
        observation?.invalidate()
        observation = nil
        task = nil
    }

    private func fileSize(_ path: String) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64
    }
}
