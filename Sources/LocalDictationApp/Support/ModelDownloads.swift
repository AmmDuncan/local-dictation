import CryptoKit
import Foundation

/// Shared helpers for model downloads (whisper + polish): streamed SHA-256
/// verification and user-friendly URLSession error messages.
enum ModelDownloads {
    /// Streams the file through SHA-256 off the main thread and compares to the
    /// pinned digest. Off-main so a multi-GB file doesn't block the UI.
    static func checksumMatches(url: URL, expected: String) async -> Bool {
        await Task.detached(priority: .utility) {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            return digest == expected.lowercased()
        }.value
    }

    static func friendlyMessage(for error: NSError) -> String {
        switch error.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            "No internet connection. Connect and try again."
        case NSURLErrorTimedOut:
            "The download timed out. Please try again."
        default:
            "Download failed. Please try again."
        }
    }
}
