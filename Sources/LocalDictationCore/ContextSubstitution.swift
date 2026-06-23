import Foundation

public struct ProposedSwap: Equatable, Sendable {
    public let range: NSRange   // UTF-16 span in the working (pre-polish) text
    public let from: String     // original words, e.g. "cuban eats"
    public let to: String       // candidate target, e.g. "Kubernetes"
    public init(range: NSRange, from: String, to: String) {
        self.range = range; self.from = from; self.to = to
    }
}

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

extension ContextSubstitution {
    private struct Token { let text: String; let range: NSRange }

    /// Whitespace-delimited tokens with their UTF-16 ranges in `s`.
    private static func tokenize(_ s: String) -> [Token] {
        let ns = s as NSString
        var tokens: [Token] = []
        var i = 0
        let n = ns.length
        while i < n {
            while i < n, isWhitespace(ns.character(at: i)) { i += 1 }
            guard i < n else { break }
            let start = i
            while i < n, !isWhitespace(ns.character(at: i)) { i += 1 }
            let range = NSRange(location: start, length: i - start)
            tokens.append(Token(text: ns.substring(with: range), range: range))
        }
        return tokens
    }

    private static func isWhitespace(_ c: unichar) -> Bool {
        c == 32 || c == 9 || c == 10 || c == 13
    }

    private static func norm(_ t: String) -> String { words(t).joined(separator: " ") }

    /// Two-pointer token alignment (guard forbids reordering, so matches are in
    /// order). On a mismatch, find the minimal-distance resync and emit the
    /// intervening original-run -> guarded-run as one swap; matching tokens
    /// between two swaps keep them separate.
    public static func diffSwaps(original: String, guarded: String) -> [ProposedSwap] {
        let ot = tokenize(original)
        let gt = tokenize(guarded)
        let originalNS = original as NSString
        var swaps: [ProposedSwap] = []
        var i = 0, j = 0
        let maxLook = 8
        while i < ot.count && j < gt.count {
            if norm(ot[i].text) == norm(gt[j].text) { i += 1; j += 1; continue }
            var found: (a: Int, b: Int)? = nil
            search: for total in 1...maxLook {
                for a in 0...total {
                    let b = total - a
                    guard i + a < ot.count, j + b < gt.count else { continue }
                    if norm(ot[i + a].text) == norm(gt[j + b].text) { found = (a, b); break search }
                }
            }
            let (a, b) = found ?? (ot.count - i, gt.count - j)
            swaps.append(makeSwap(ot, gt, i, a, j, b, originalNS))
            i += max(a, 0); j += max(b, 0)
            if a == 0 && b == 0 { break }
        }
        if i < ot.count || j < gt.count {
            swaps.append(makeSwap(ot, gt, i, ot.count - i, j, gt.count - j, originalNS))
        }
        return swaps
    }

    private static func makeSwap(_ ot: [Token], _ gt: [Token], _ i: Int, _ a: Int,
                                 _ j: Int, _ b: Int, _ originalNS: NSString) -> ProposedSwap {
        let range: NSRange
        if a > 0 {
            let start = ot[i].range.location
            let end = ot[i + a - 1].range.location + ot[i + a - 1].range.length
            range = NSRange(location: start, length: end - start)
        } else {
            let loc = i < ot.count ? ot[i].range.location : originalNS.length
            range = NSRange(location: loc, length: 0)
        }
        let from = range.length > 0 ? originalNS.substring(with: range) : ""
        let to = (j..<(j + b)).map { gt[$0].text }.joined(separator: " ")
        return ProposedSwap(range: range, from: from, to: to)
    }

    /// Apply a subset of proposed swaps to `text`, returning the corrected string
    /// and one `Edit` per swap in OUTPUT coordinate space (suitable for `EditFold.combine`).
    public static func apply(_ swaps: [ProposedSwap], to text: String) -> (String, [Edit]) {
        guard !swaps.isEmpty else { return (text, []) }
        let sorted = swaps.sorted { $0.range.location < $1.range.location }
        let ns = NSMutableString(string: text)
        var edits: [Edit] = []
        var delta = 0
        for swap in sorted {
            let newLocation = swap.range.location + delta
            let toLen = (swap.to as NSString).length
            ns.replaceCharacters(in: NSRange(location: newLocation, length: swap.range.length), with: swap.to)
            edits.append(Edit(location: newLocation, length: toLen, from: swap.from, to: swap.to, source: .contextSub))
            delta += toLen - swap.range.length
        }
        return (ns as String, edits)
    }
}
