import AppKit
import Foundation
import LocalDictationCore

/// Rolling buffer of recent dictation recordings for troubleshooting.
/// Off by default; enabled via Settings → "Keep recent recordings for troubleshooting".
/// Caps at 10 files and auto-deletes anything older than 7 days. All ops are
/// best-effort — errors are silently swallowed so they never interrupt the audio path.
enum RecentRecordings {
    private static let maxCount = 10
    private static let maxAgeDays: Double = 7

    private static var storageDir: URL {
        let base = NSHomeDirectory() + "/Library/Application Support/dev.ammiel.local-dictation/recent-recordings"
        try? FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        return URL(fileURLWithPath: base)
    }

    /// Copy `wavURL` into the rolling buffer with a timestamped filename, then prune.
    /// Call this on the audio path — errors are swallowed, never thrown.
    static func archive(_ wavURL: URL) {
        let fm = FileManager.default
        let dir = storageDir

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dest = dir.appendingPathComponent("rec-\(timestamp).wav")

        try? fm.copyItem(at: wavURL, to: dest)
        pruneIfNeeded(in: dir, fm: fm)
    }

    /// Open the storage directory in Finder, creating it first if needed.
    static func revealInFinder() {
        let dir = storageDir  // creates the dir as a side effect
        NSWorkspace.shared.open(dir)
    }

    /// Pure function: given a sorted list of existing filenames and a keep count,
    /// returns the filenames that should be deleted. Oldest entries (sort-first) are
    /// pruned first. Enables unit testing without touching the filesystem.
    static func namesToPrune(existing: [String], keepCount: Int) -> [String] {
        RecentRecordingsPrune.namesToPrune(existing: existing, keepCount: keepCount)
    }

    // MARK: - Private

    private static func pruneIfNeeded(in dir: URL, fm: FileManager) {
        guard let contents = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        let wavs = contents.filter { $0.hasSuffix(".wav") }.sorted()

        // Prune by count.
        for name in RecentRecordingsPrune.namesToPrune(existing: wavs, keepCount: maxCount) {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }

        // Prune by age.
        let cutoff = Date().addingTimeInterval(-maxAgeDays * 86_400)
        for name in wavs {
            let url = dir.appendingPathComponent(name)
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let modified = attrs[.modificationDate] as? Date,
               modified < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }
}
