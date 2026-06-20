import Foundation

/// Builds the whisper context prompt that biases recognition toward the user's
/// own words — their custom vocabulary plus a rolling window of recent
/// transcripts. Whisper leans toward terms it has "seen" in the prompt, so
/// recurring names/jargon (and words you say often) are mis-heard less.
///
/// Pure + bounded: whisper only uses a limited prompt context, so the result is
/// capped — vocabulary first (most valuable), then the most recent history.
public enum RecognitionContext {
    /// Default cap. Whisper's prompt context is ~224 tokens; ~600 characters
    /// stays comfortably inside it while leaving room for the audio.
    public static let defaultMaxChars = 600

    public static func prompt(
        vocabulary: String,
        history: [String],
        maxChars: Int = defaultMaxChars
    ) -> String {
        let vocab = vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)

        // Vocabulary is the highest-value signal — keep it whole if it fits.
        var parts: [String] = []
        var budget = maxChars
        if !vocab.isEmpty {
            parts.append(vocab)
            budget -= vocab.count + 1
        }

        // Add recent history newest-first until the budget runs out, then restore
        // chronological order so it reads as natural preceding context.
        var kept: [String] = []
        for entry in history.reversed() {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.count + 1 > budget { break }
            kept.append(trimmed)
            budget -= trimmed.count + 1
        }
        parts.append(contentsOf: kept.reversed())

        return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Append a new transcript to the rolling history, dropping the oldest beyond
    /// `maxEntries`. Blank entries are ignored.
    public static func appendingHistory(
        _ transcript: String,
        to history: [String],
        maxEntries: Int = 12
    ) -> [String] {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return history }
        var updated = history
        updated.append(trimmed)
        if updated.count > maxEntries {
            updated.removeFirst(updated.count - maxEntries)
        }
        return updated
    }
}
