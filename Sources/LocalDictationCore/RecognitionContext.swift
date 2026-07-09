import Foundation

/// Builds the whisper context prompt that biases recognition toward trustworthy,
/// non-self-reinforcing sources: the user's custom vocabulary and the live caret/
/// visible context. Whisper leans toward terms it has "seen" in the prompt, so
/// recurring names/jargon are mis-heard less. The `history` argument exists for
/// completeness but the app deliberately feeds none — biasing from raw past
/// transcripts is a feedback loop (a bad transcript poisons the next), so curated
/// vocabulary + current on-screen context (which can't accumulate pollution) are
/// the only sources fed.
///
/// Pure + bounded: whisper only uses a limited prompt context, so the result is
/// capped — vocabulary first (most valuable), then the live context.
public enum RecognitionContext {
    /// Default cap. Whisper's prompt context is ~224 tokens; ~600 characters
    /// stays comfortably inside it while leaving room for the audio.
    public static let defaultMaxChars = 600

    /// The terms are framed as "Technical terms: {…}." rather than a bare comma
    /// dump: measured on the real-mic jargon set (prompt_framing_sweep,
    /// 2026-07-08) the framing cut jargon/names WER 0.243 → 0.183 — nearly the
    /// full large-v3 model-swap gain at zero cost — and clean prose improved.
    /// The header + period are budgeted so `maxChars` still bounds the result.
    static let framingPrefix = "Technical terms: "
    static let framingSuffix = "."

    public static func prompt(
        vocabulary: String,
        defaults: [String] = [],
        history: [String] = [],
        context: ContextBias.PromptContext? = nil,
        maxChars: Int = defaultMaxChars
    ) -> String {
        let vocab = vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)

        // Priority order within the bounded prompt, highest signal first so it
        // survives the cap: the user's own vocabulary, then the live context
        // (caret-proximate text → extracted candidates → app-class vocabulary),
        // then the built-in defaults, then recent history. `seen` (lowercased
        // words already represented) keeps later, lower-priority parts from
        // repeating a term an earlier part already carries.
        var parts: [String] = []
        var budget = maxChars - framingPrefix.count - framingSuffix.count
        var seen = Set<String>()
        if !vocab.isEmpty {
            parts.append(vocab)
            budget -= vocab.count + 1
            remember(vocab, in: &seen)
        }

        // Live context as DISCRETE TERMS only: identifier candidates extracted
        // from the caret/visible text, then the app-class vocabulary the canonical
        // mishearings live in.
        //
        // NOTE: the raw caret-preceding TEXT is deliberately NOT fed here. Whisper's
        // initial_prompt is "previous-text conditioning": feeding it free-form
        // running sentences makes the decoder skip content it thinks the prompt
        // already covered (early-half cutoff) or fall into a repetition loop
        // (duplicated sentences) — both reproduced from real recordings, both gone
        // once the prompt carries only discrete terms. Identifier candidates are
        // still extracted from that same caret/visible text by ContextBias, so the
        // useful on-screen vocabulary survives; only the harmful running prose is
        // dropped. See the whisper.cpp conditioning issues (#1017, #2286, #1507).
        if let context {
            budget = appendTerms(context.candidates, to: &parts, budget: budget, seen: &seen)
            budget = appendTerms(context.appVocabulary, to: &parts, budget: budget, seen: &seen)
        }

        // Built-in defaults — terms that fit and aren't already represented.
        budget = appendTerms(defaults, to: &parts, budget: budget, seen: &seen)

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

        let joined = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { return "" }
        return framingPrefix + joined + framingSuffix
    }

    /// Append the terms that fit `budget` and aren't already represented (every
    /// word already in `seen`), as one comma-joined part. Returns the new budget.
    private static func appendTerms(
        _ terms: [String], to parts: inout [String], budget: Int, seen: inout Set<String>
    ) -> Int {
        var budget = budget
        var kept: [String] = []
        for term in terms {
            let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            let words = wordsOf(t)
            if !words.isEmpty, words.allSatisfy(seen.contains) { continue }
            if t.count + 2 > budget { break }
            kept.append(t)
            budget -= t.count + 2
            for w in words { seen.insert(w) }
        }
        if !kept.isEmpty {
            parts.append(kept.joined(separator: ", "))
        }
        return budget
    }

    private static func remember(_ text: String, in seen: inout Set<String>) {
        for w in wordsOf(text) { seen.insert(w) }
    }

    private static func wordsOf(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }
}
