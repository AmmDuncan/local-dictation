import Foundation

/// Deterministic, strictly meaning-preserving cleanup of a finished transcript
/// before it's typed. It only removes obvious disfluencies (um, uh, …),
/// normalizes spacing/punctuation, and fixes sentence capitalization — it never
/// rewords, reorders, drops content, or guesses at misheard words. (Those need
/// VAD, prompt-biasing, or an opt-in LLM pass — not deterministic rules.)
///
/// Runs after `WhisperTranscriptParser.strippedForInsertion` in the insertion
/// pipeline; the overlay still shows the raw transcript.
public enum TranscriptCleaner {
    public struct Options: Sendable, Equatable {
        public var removeFillers: Bool
        public var fixCapitalization: Bool

        public init(removeFillers: Bool = true, fixCapitalization: Bool = true) {
            self.removeFillers = removeFillers
            self.fixCapitalization = fixCapitalization
        }
    }

    public static func clean(_ text: String, options: Options = Options()) -> String {
        var result = text
        if options.removeFillers {
            result = removingFillers(result)
        }
        result = normalizingSpacingAndPunctuation(result)
        if options.fixCapitalization {
            result = fixingCapitalization(result)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Conservative disfluency set whisper commonly emits as words: um/umm, uh/uhh,
    // uhm, erm, hmm. Matched whole-word + case-insensitive, with an optional
    // trailing comma so "Um, hello" → "hello". Deliberately excludes ambiguous
    // tokens like "mm" (millimetres), "ah", and bare "er" to avoid eating content.
    private static let fillerRegex = try? NSRegularExpression(
        pattern: #"\b(?:u+m+|u+h+|uhm|erm|hmm+)\b,?"#,
        options: [.caseInsensitive]
    )

    private static func removingFillers(_ text: String) -> String {
        guard let regex = fillerRegex else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private static func normalizingSpacingAndPunctuation(_ text: String) -> String {
        var s = text
        // Drop spaces before punctuation: "word ," → "word,"
        s = s.replacingOccurrences(of: #" +([,.;:!?])"#, with: "$1", options: .regularExpression)
        // Collapse runs of spaces/tabs (newlines preserved).
        s = s.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        // Ensure a single space after sentence punctuation when a letter follows.
        s = s.replacingOccurrences(of: #"([,.;:!?])([A-Za-z])"#, with: "$1 $2", options: .regularExpression)
        return s
    }

    private static func fixingCapitalization(_ text: String) -> String {
        var chars = Array(text)
        var capitalizeNext = true
        for i in chars.indices {
            let c = chars[i]
            if capitalizeNext, c.isLetter {
                chars[i] = Character(c.uppercased())
                capitalizeNext = false
            } else if c == "." || c == "!" || c == "?" || c == "\n" {
                capitalizeNext = true
            } else if c.isLetter || c.isNumber {
                capitalizeNext = false
            }
            // Spaces/commas leave `capitalizeNext` untouched.
        }
        // Standalone first-person "i" → "I" (also "i'm", "i'll" via the boundary).
        return String(chars).replacingOccurrences(
            of: #"\bi\b"#, with: "I", options: .regularExpression
        )
    }
}
