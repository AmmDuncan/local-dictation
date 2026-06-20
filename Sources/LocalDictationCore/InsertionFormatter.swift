import Foundation

/// Adjusts finished text for insertion at the caret, given the character
/// immediately before it. Mirrors what polished dictation tools do: continue a
/// sentence in lowercase, and add a single leading space so the new text doesn't
/// jam against the previous word. Purely deterministic — no model, no network.
///
/// `precedingCharacter == nil` means start-of-field or unknown context (no
/// accessibility read available), in which case the text is left untouched.
public enum InsertionFormatter {
    private static let sentenceEnders: Set<Character> = [".", "!", "?", "\n"]
    private static let openingPunctuation: Set<Character> = [",", ".", "!", "?", ";", ":", ")", "]", "}"]

    public static func format(_ text: String, precedingCharacter: Character?) -> String {
        guard !text.isEmpty, let prev = precedingCharacter else { return text }

        var result = text
        let afterSentenceEnd = sentenceEnders.contains(prev)

        // Mid-sentence continuation → lowercase the first word.
        if !afterSentenceEnd {
            result = lowercasingFirstWord(result)
        }

        // Ensure one separating space when butting up against a word character and
        // the text doesn't already begin with whitespace or attaching punctuation.
        let prevIsWhitespace = prev.isWhitespace
        if !prevIsWhitespace, let first = result.first,
           !first.isWhitespace, !openingPunctuation.contains(first) {
            result = " " + result
        }
        return result
    }

    /// Lowercases the first letter when it's safe — leaves a standalone "I",
    /// an acronym ("API"), and non-letters alone.
    private static func lowercasingFirstWord(_ text: String) -> String {
        var chars = Array(text)
        guard let i = chars.firstIndex(where: { $0.isLetter }) else { return text }
        let c = chars[i]
        guard c.isUppercase else { return text }

        let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
        // Standalone capital (e.g. "I") — leave it.
        guard let next, next.isLetter else { return text }
        // Acronym (next letter also uppercase) — leave it.
        if next.isUppercase { return text }

        chars[i] = Character(c.lowercased())
        return String(chars)
    }
}
