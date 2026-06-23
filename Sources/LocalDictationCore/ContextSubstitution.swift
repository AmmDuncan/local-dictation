import Foundation

/// Context-grounded substitution: a constrained LLM pass that swaps a misheard
/// word ONLY for a term in a candidate allow-list, with a deterministic guard
/// ported verbatim from tools/accuracy-harness/substitution_ab.py. The hard
/// failure class (an ordinary word that resembles a candidate: team->Teams,
/// dock->docker) is structurally invisible to the guard — human confirmation in
/// the countdown overlay is the real safety net.
public enum ContextSubstitution {
    /// Mirrors the Python `words()`: lowercase, strip everything but [a-z0-9 ],
    /// split on whitespace.
    public static func words(_ s: String) -> [String] {
        let lowered = s.lowercased()
        let cleaned = String(lowered.map { ch -> Character in
            (ch.isLetter && ch.isASCII) || (ch.isNumber && ch.isASCII) || ch == " " ? ch : " "
        })
        return cleaned.split(separator: " ").map(String.init)
    }

    /// Port of the Python `guard()`: returns `output` only if it (a) adds no word
    /// outside the candidate set, (b) does not collapse the sentence (len drop > 1),
    /// and (c) does not drop content with nothing added. Otherwise returns `original`.
    public static func guardOutput(_ output: String, original: String, candidates: [String]) -> String {
        let cand = Set(candidates.map { $0.lowercased() })
        let oi = words(original)
        let oo = words(output)
        let si = Set(oi)
        let so = Set(oo)
        let added = oo.filter { !si.contains($0) }
        let dropped = oi.filter { !so.contains($0) }
        if added.contains(where: { !cand.contains($0) }) { return original }   // off-list
        if oi.count - oo.count > 1 { return original }                          // collapse/truncate
        if !dropped.isEmpty && added.isEmpty { return original }                // pure deletion
        return output
    }
}
