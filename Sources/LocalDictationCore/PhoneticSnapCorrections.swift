import Foundation

/// Deterministic phonetic vocabulary snapping: a 1–3-word window of the
/// transcript is replaced with a curated vocabulary term when it both SOUNDS
/// like the term (Metaphone-code similarity) and roughly SPELLS like it
/// ("superbees" -> "Supabase", "LungChain" -> "LangChain").
///
/// Guards, each load-bearing in the measured A/B (69 real-mic clips + the 50
/// substitution_ab traps: 9 fixes, 0 corruptions):
/// - targets come ONLY from the vocabulary list (and need ≥4 alphanumerics);
/// - a term already present anywhere in the transcript is never placed again;
/// - a window made only of real English words is never touched (kills the
///   measured "open" -> "OpenAI" false swap and its multi-word cousin "long
///   chain" -> "LangChain" — real-word homophones belong to the mishearing map
///   and command mode, not this pass).
public enum PhoneticSnapCorrections {
    /// Metaphone-code similarity floor (normalized Levenshtein on the codes).
    static let phoneticSimilarity = 0.80
    /// Spelling similarity floor, rapidfuzz `fuzz.ratio` scale 0-100.
    static let orthographicSimilarity = 55.0
    /// Vocabulary terms shorter than this (squashed) can't be matched reliably.
    static let minimumTermLength = 4

    private struct Term {
        let text: String
        let key: String
        let squashed: String
    }

    /// Apply snapping and return the corrected text plus one `.mishearing`
    /// `Edit` per swap (ranges in the output string).
    public static func applyTracked(
        to text: String,
        vocabulary: [String],
        suppressing: Set<String> = []
    ) -> (String, [Edit]) {
        let lowercased = text.lowercased()
        let terms: [Term] = vocabulary.compactMap { term in
            let squashed = SubstitutionPrefilter.squash(term)
            guard squashed.count >= minimumTermLength else { return nil }
            // Already said correctly somewhere: never place the term again.
            guard !lowercased.contains(term.lowercased()) else { return nil }
            return Term(text: term, key: Metaphone.key(term), squashed: squashed)
        }
        guard !terms.isEmpty else { return (text, []) }

        let vocabularySurfaces = Set(vocabulary.map { $0.lowercased() })
        let tokens = ContextSubstitution.tokenize(text).map(\.range)
        var replacements: [(range: NSRange, to: String)] = []
        var i = 0
        while i < tokens.count {
            guard let match = bestMatch(
                at: i, tokens: tokens, in: text, terms: terms, vocabularySurfaces: vocabularySurfaces
            ) else {
                i += 1
                continue
            }
            let core = coreRange(of: match.windowRange, in: text)
            let heard = (text as NSString).substring(with: core)
            let identity = RuleDerivation.suppressionIdentity(source: .mishearing, from: heard, to: match.term)
            if identity.map(suppressing.contains) ?? false {
                i += match.wordCount // consume the rejected window whole; no sub-window re-fires
                continue
            }
            replacements.append((range: core, to: match.term))
            i += match.wordCount
        }

        let (corrected, edits, _) = EditTracking.rebuild(text, replacements: replacements, source: .mishearing)
        return (corrected, edits)
    }

    /// Convenience: corrected text only.
    public static func apply(to text: String, vocabulary: [String]) -> String {
        applyTracked(to: text, vocabulary: vocabulary).0
    }

    private struct Match {
        let term: String
        let wordCount: Int
        let windowRange: NSRange
        let score: Double
    }

    /// The best (term, window-size) pair starting at token `start`, or nil.
    /// Wider windows are scanned first and a hit at a given width stops the
    /// scan of narrower ones, mirroring the measured Python prototype.
    private static func bestMatch(
        at start: Int,
        tokens: [NSRange],
        in text: String,
        terms: [Term],
        vocabularySurfaces: Set<String>
    ) -> Match? {
        var best: Match?
        for n in stride(from: 3, through: 1, by: -1) {
            guard start + n <= tokens.count else { continue }
            let windowRange = NSUnionRange(tokens[start], tokens[start + n - 1])
            let window = (text as NSString).substring(with: windowRange)
            let squashedWindow = SubstitutionPrefilter.squash(window)
            guard !squashedWindow.isEmpty, !vocabularySurfaces.contains(window.lowercased()) else { continue }
            let windowWords = window.lowercased().split(whereSeparator: \.isWhitespace)
                .map { $0.filter { ("a"..."z").contains($0) } }
                .filter { !$0.isEmpty }
            if windowWords.allSatisfy(EnglishDictionary.contains) {
                continue // windows made only of real English words are never snapped
            }
            let windowKey = Metaphone.key(window)
            for term in terms {
                let phonetic = SubstitutionPrefilter.similarity(windowKey, term.key)
                guard phonetic >= phoneticSimilarity else { continue }
                let spelling = SubstitutionPrefilter.indelRatio(squashedWindow, term.squashed)
                guard spelling >= orthographicSimilarity else { continue }
                let score = phonetic + spelling / 100
                if best == nil || score > best!.score || (score == best!.score && n > best!.wordCount) {
                    best = Match(term: term.text, wordCount: n, windowRange: windowRange, score: score)
                }
            }
            if let best, best.wordCount == n { break }
        }
        return best
    }

    /// `range` narrowed past any leading/trailing punctuation, so a swap keeps
    /// the punctuation the user dictated ("superbees," -> "Supabase,").
    private static func coreRange(of range: NSRange, in text: String) -> NSRange {
        let window = (text as NSString).substring(with: range)
        let chars = Array(window.utf16)
        var lead = 0
        var trail = 0
        func isWordChar(_ unit: unichar) -> Bool {
            Character(UnicodeScalar(unit) ?? " ").isLetter || Character(UnicodeScalar(unit) ?? " ").isNumber
        }
        while lead < chars.count && !isWordChar(chars[lead]) { lead += 1 }
        while trail < chars.count - lead && !isWordChar(chars[chars.count - 1 - trail]) { trail += 1 }
        return NSRange(location: range.location + lead, length: range.length - lead - trail)
    }

}
