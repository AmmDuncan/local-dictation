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
        applyTracked(to: text).0
    }

    /// Like `apply`, but also returns one `.mishearing` `Edit` per substitution
    /// (ranges in the output string) — both the rule-driven swaps and the separate
    /// `clot` correction. The `rules` run first (via the shared tracking engine),
    /// then `correctClot` on their result; the rule edits are rebased through the
    /// clot pass so all ranges land in the final output space.
    public static func applyTracked(to text: String, suppressing: Set<String> = []) -> (String, [Edit]) {
        let activeRules = rules.filter { rule in
            guard let id = RuleDerivation.suppressionIdentity(source: .mishearing, from: rule.pattern, to: rule.replacement) else { return true }
            return !suppressing.contains(id)
        }
        var (result, edits) = TextReplacements.applyTracked(activeRules, to: text, source: .mishearing)
        let clotSuppressed = RuleDerivation.suppressionIdentity(source: .mishearing, from: "clot", to: "Claude")
            .map(suppressing.contains) ?? false
        if !clotSuppressed {
            let (clotResult, clotEdits, clotDeltas) = correctClotTracked(in: result)
            edits = Edit.shifting(edits, by: clotDeltas)
            edits.append(contentsOf: clotEdits)
            result = clotResult
        }
        return (result, edits)
    }

    /// Matches a whole-word "clot" that is NOT the genuine medical phrase "blood
    /// clot" (negative lookbehind). Compiled once; nil only if the pattern is
    /// somehow invalid, in which case `correctClot` leaves the text untouched.
    private static let clotRegex = try? NSRegularExpression(
        pattern: #"(?<!\bblood )\bclot\b"#, options: [.caseInsensitive]
    )

    /// "clot" -> "Claude" everywhere EXCEPT "blood clot". In developer dictation a
    /// bare "clot" is virtually always a misheard "Claude"; "clots" / "clotting" /
    /// "clotted" are left alone by the whole-word boundary. Returns the corrected
    /// string, one `.mishearing` `Edit` per match (range in the output), and the
    /// per-match length deltas (so a caller can rebase edits made before this pass).
    private static func correctClotTracked(
        in text: String
    ) -> (String, [Edit], [(at: Int, delta: Int)]) {
        guard let clotRegex else { return (text, [], []) }
        let matches = clotRegex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        let replacements = matches.map { (range: $0.range, to: "Claude") }
        return EditTracking.rebuild(text, replacements: replacements, source: .mishearing)
    }
}
