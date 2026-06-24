import Foundation

/// The user's custom recognition-bias vocabulary: a newline-delimited list of terms
/// folded into whisper's `--prompt` (see `RecognitionContext.prompt`).
public enum CustomVocabulary {
    /// Append `term` to the list, skipping it when empty or already present
    /// (case-insensitive, whitespace-trimmed). Returns the list unchanged on a
    /// duplicate so re-teaching the same word can't bloat the bias prompt.
    public static func appending(_ term: String, to list: String) -> String {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return list }
        let existing = list
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard !existing.contains(trimmed.lowercased()) else { return list }
        return list.isEmpty ? trimmed : list + "\n" + trimmed
    }

    /// Split the freeform list into discrete terms — one per line or comma —
    /// trimmed, empties dropped. Used where the list is consumed as an allow-list
    /// of distinct terms (e.g. context-substitution candidates), as opposed to the
    /// whisper bias prompt where the whole string is fed verbatim.
    public static func terms(_ list: String) -> [String] {
        list.split(whereSeparator: { $0.isNewline || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
