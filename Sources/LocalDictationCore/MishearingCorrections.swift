import Foundation

/// Built-in, deterministic corrections for high-confidence speech-to-text
/// mishearings of names/terms Whisper reliably gets wrong. Applied as whole-word,
/// case-insensitive replacements BEFORE the LLM polish so the small polish model
/// (which only tidies formatting) never sees the mishearing at all.
///
/// Why this exists: relying on the 3B polish model to fix mishearings is
/// unreliable — given "clot" with a busy vocabulary it grabs an unrelated listed
/// term (observed: "clot" -> "VAD", "Claude Code" -> "Vibe Coding"). A tiny
/// curated, deterministic map makes the common cases exact and frees the model to
/// do only what it is good at: capitalization, punctuation, and fillers.
///
/// Deliberately tight: only mishearings that are essentially never the intended
/// word in this app's (developer / AI) usage. The user's own `TextReplacements`
/// run AFTER polish and can extend or override these.
public enum MishearingCorrections {
    /// Whole-word mishearing -> canonical term. Order matters: multi-word phrases
    /// come before their single-word constituents. Matching/casing is handled by
    /// `TextReplacements` (case-insensitive match, replacement casing kept).
    /// "clot" is handled separately (see `apply`) so the genuine medical phrase
    /// "blood clot" can be spared.
    public static let rules: [TextReplacements.Rule] = [
        .init(pattern: "cloud code", replacement: "Claude Code"),
        .init(pattern: "claud", replacement: "Claude"),
        .init(pattern: "clawd", replacement: "Claude"),
    ]

    /// Apply the built-in corrections to `text`.
    public static func apply(to text: String) -> String {
        correctClot(in: TextReplacements.apply(rules, to: text))
    }

    /// Matches a whole-word "clot" that is NOT the genuine medical phrase "blood
    /// clot" (negative lookbehind). Compiled once; nil only if the pattern is
    /// somehow invalid, in which case `correctClot` leaves the text untouched.
    private static let clotRegex = try? NSRegularExpression(
        pattern: #"(?<!\bblood )\bclot\b"#, options: [.caseInsensitive]
    )

    /// "clot" -> "Claude" everywhere EXCEPT "blood clot". In developer dictation a
    /// bare "clot" is virtually always a misheard "Claude"; "clots" / "clotting" /
    /// "clotted" are left alone by the whole-word boundary.
    private static func correctClot(in text: String) -> String {
        guard let clotRegex else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return clotRegex.stringByReplacingMatches(in: text, range: range, withTemplate: "Claude")
    }
}
