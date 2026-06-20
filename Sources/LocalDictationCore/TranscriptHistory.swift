import Foundation

/// A persisted dictation result the user can browse, search, and re-copy. Audio
/// is never stored here — text only — so surfacing history stays on-brand for a
/// privacy-first tool.
public struct TranscriptRecord: Equatable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var text: String
    public var date: Date

    public init(id: UUID = UUID(), text: String, date: Date) {
        self.id = id
        self.text = text
        self.date = date
    }
}

/// Pure operations over the transcript-history list. Persistence (UserDefaults)
/// and the browse UI live in the app layer.
public enum TranscriptHistory {
    public static let defaultMaxEntries = 200

    /// Append a transcript (newest last), dropping the oldest beyond `maxEntries`.
    /// Blank text is ignored. `date` is injected so callers stay testable.
    public static func appending(
        _ text: String,
        to records: [TranscriptRecord],
        at date: Date,
        maxEntries: Int = defaultMaxEntries
    ) -> [TranscriptRecord] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return records }
        var updated = records
        updated.append(TranscriptRecord(text: trimmed, date: date))
        if updated.count > maxEntries {
            updated.removeFirst(updated.count - maxEntries)
        }
        return updated
    }

    /// Case-insensitive substring search, newest first. Empty query returns all
    /// (newest first).
    public static func search(_ records: [TranscriptRecord], query: String) -> [TranscriptRecord] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ordered = records.sorted { $0.date > $1.date }
        guard !q.isEmpty else { return ordered }
        return ordered.filter { $0.text.lowercased().contains(q) }
    }
}
