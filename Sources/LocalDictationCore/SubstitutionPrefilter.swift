import Foundation

/// Decides whether the context-substitution LLM call is worth making for a
/// transcript. The call costs ~0.9s on long dictations and its only job is
/// snapping mishearings onto vocabulary candidates — when nothing in the
/// transcript even resembles a candidate, skipping it saves the latency AND
/// removes an opportunity for the LLM to corrupt correct words.
///
/// Recall-oriented by design: a false "call" is just today's behavior; a false
/// "skip" loses a fix. Thresholds were grid-searched against the
/// substitution_ab.py cases (100% recall on in-scope mishears, ~61% skip rate
/// on realistic prose). Candidates shorter than 5 squashed characters (git,
/// main, npm…) are out of scope — short homophones can't be caught by string
/// similarity and belong to the deterministic correction layers.
public enum SubstitutionPrefilter {
    static let singleWordSimilarity = 0.45
    static let multiWordSimilarity = 0.5
    static let singleSkeletonSimilarity = 0.55
    static let multiSkeletonSimilarity = 0.60
    /// A window that spells a real English word is almost never a mishearing —
    /// unless it matches a candidate this closely.
    static let dictionaryOverride = 0.70
    static let minimumCandidateLength = 5
    /// Skeleton comparisons on very short strings are noise ("wnd" ~ "tlwnd");
    /// both sides must be at least this long for the skeleton path to count.
    static let minimumSkeletonLength = 4

    private struct Term {
        let squashed: String
        let skeleton: String
    }

    /// Loads the system word list off the critical path; without this the first
    /// dictation pays the read+parse synchronously inside `worthCalling`.
    public static func prewarm() {
        _ = EnglishDictionary.contains("")
    }

    /// True when some transcript window sounds enough like a candidate that the
    /// substitution LLM might have work to do.
    public static func worthCalling(transcript: String, candidates: [String]) -> Bool {
        let terms: [Term] = candidates.compactMap {
            let squashed = squash($0)
            guard squashed.count >= minimumCandidateLength else { return nil }
            return Term(squashed: squashed, skeleton: skeleton(squashed))
        }
        guard !terms.isEmpty else { return false }

        // Same tokenizer as ContextSubstitution so the gate and the engine
        // always agree on what a "word" is.
        let words = ContextSubstitution.words(transcript)
        for n in 1...3 {
            guard words.count >= n else { break }
            for start in 0...(words.count - n) {
                let window = squash(words[start..<(start + n)].joined())
                guard !window.isEmpty else { continue }
                if terms.contains(where: { matches(window: window, term: $0, wordCount: n) }) {
                    return true
                }
            }
        }
        return false
    }

    /// The certified match rule for one (window, candidate) pair. The skeleton
    /// similarity is a second Levenshtein pass, so it is only computed when the
    /// squashed comparison alone can't decide.
    private static func matches(window: String, term: Term, wordCount: Int) -> Bool {
        let ratio = Double(window.count) / Double(term.squashed.count)
        guard (0.5...2.0).contains(ratio) else { return false }

        let simFloor = wordCount == 1 ? singleWordSimilarity : multiWordSimilarity
        let skelFloor = wordCount == 1 ? singleSkeletonSimilarity : multiSkeletonSimilarity
        let squashedSim = similarity(window, term.squashed)
        let isRealWord = EnglishDictionary.contains(window)

        if squashedSim >= simFloor && !isRealWord {
            return true
        }

        let windowSkeleton = skeleton(window)
        let skeletonUsable = windowSkeleton.count >= minimumSkeletonLength
            && term.skeleton.count >= minimumSkeletonLength
        let skeletonSim = skeletonUsable ? similarity(windowSkeleton, term.skeleton) : 0

        guard squashedSim >= simFloor || skeletonSim >= skelFloor else { return false }
        return !isRealWord || max(squashedSim, skeletonSim) >= dictionaryOverride
    }

    /// Lowercase alphanumerics only ("git hub!" -> "github").
    static func squash(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// Consonant skeleton: squashed form with vowels dropped ("versal" -> "vrsl").
    static func skeleton(_ squashed: String) -> String {
        squashed.filter { !"aeiou".contains($0) }
    }

    /// Normalized Levenshtein similarity in 0...1.
    static func similarity(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let aChars = Array(a), bChars = Array(b)
        var previous = Array(0...bChars.count)
        for (i, ca) in aChars.enumerated() {
            var current = [i + 1]
            for (j, cb) in bChars.enumerated() {
                current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + (ca == cb ? 0 : 1)))
            }
            previous = current
        }
        return 1 - Double(previous[bChars.count]) / Double(max(aChars.count, bChars.count))
    }
}

/// The system word list, loaded once (see `SubstitutionPrefilter.prewarm`).
/// Missing file (non-macOS or stripped system) degrades gracefully: nothing is
/// dictionary-blocked, so the prefilter only becomes more permissive (more LLM
/// calls, never fewer fixes).
enum EnglishDictionary {
    private static let words: Set<String> = {
        guard let contents = try? String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8) else {
            return []
        }
        return Set(contents.split(separator: "\n").compactMap {
            let word = $0.trimmingCharacters(in: .whitespaces).lowercased()
            return word.count > 1 ? word : nil
        })
    }()

    static func contains(_ word: String) -> Bool {
        words.contains(word)
    }
}
