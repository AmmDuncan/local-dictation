import Foundation

/// Pure helpers for the recent-recordings rolling buffer. Kept in Core so they
/// can be unit-tested without pulling in AppKit.
public enum RecentRecordingsPrune {
    /// Given a sorted list of existing filenames and a keep count, returns the
    /// filenames that should be deleted. Oldest entries (sorted first) are pruned.
    public static func namesToPrune(existing: [String], keepCount: Int) -> [String] {
        guard existing.count > keepCount else { return [] }
        return Array(existing.prefix(existing.count - keepCount))
    }
}
