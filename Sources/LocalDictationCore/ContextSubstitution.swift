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
        // Multiset diff (not set membership): a duplicated word like "it it"
        // must register as an addition even though "it" already appears, so a
        // repetition hallucination is caught rather than silently accepted.
        var freq: [String: Int] = [:]
        for w in oi { freq[w, default: 0] += 1 }
        for w in oo { freq[w, default: 0] -= 1 }
        let added = freq.compactMap { $0.value < 0 ? $0.key : nil }   // present in output beyond original
        let droppedReal = freq.contains { $0.value > 0 }              // an original word vanished
        if added.contains(where: { !cand.contains($0) }) { return original }   // off-list or hallucinated dup
        if oi.count - oo.count > 1 { return original }                          // collapse / truncation
        if oo.count - oi.count > 1 { return original }                          // unbounded expansion
        if droppedReal && added.isEmpty { return original }                     // pure deletion
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
        if c == 32 || c == 9 || c == 10 || c == 13 { return true }
        guard let scalar = Unicode.Scalar(c) else { return false }
        return Character(scalar).isWhitespace   // U+00A0, U+2009, U+2003, … as LLMs emit
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
            if a == 0 && b == 0 { break }  // defensive: guarantee forward progress (unreachable today)
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

    /// The A/B-validated CONSTRAINED system prompt (substitution_ab.py:100), {cands} filled.
    public static func systemPrompt(candidates: [String]) -> String {
        let cands = candidates.joined(separator: ", ")
        return "You are a dictation corrector. The user message is raw speech-to-text that may contain MISHEARINGS. "
            + "You may replace a misheard word ONLY with a term from this exact CANDIDATE list: \(cands). "
            + "Only do so when a word is clearly a mishearing of a candidate. If nothing clearly matches, change NOTHING. "
            + "Never invent words, never substitute anything not in the candidate list, never touch a word that is already "
            + "ordinary correct English, never add/remove/reorder other words. Output ONLY the corrected text, nothing else."
    }

    public static func chatRequestBody(transcript: String, candidates: [String]) -> Data {
        let cands = candidates.joined(separator: ", ")
        let user = "CONTEXT (on-screen / vocabulary terms): \(cands)\n\nTRANSCRIPT: \(transcript)"
        let payload: [String: Any] = [
            "messages": [
                ["role": "system", "content": systemPrompt(candidates: candidates)],
                ["role": "user", "content": user],
            ],
            "temperature": 0,
            "stream": false,
            "chat_template_kwargs": ["enable_thinking": false],
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    public static func parseContent(_ data: Data) -> String? {
        struct Response: Decodable { struct Choice: Decodable { struct Message: Decodable { let content: String }; let message: Message }; let choices: [Choice] }
        return (try? JSONDecoder().decode(Response.self, from: data))?.choices.first?.message.content
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

public enum SubstitutionDecision: Equatable, Sendable {
    case keepOriginal
    case apply([ProposedSwap])   // the subset still toggled on (may be all)
}

/// Presents the proposed swaps and resolves the user's decision (timeout =
/// apply current toggle state, Accept = apply now, esc = keepOriginal).
public protocol SubstitutionConfirming: Sendable {
    func confirm(text: String, swaps: [ProposedSwap], countdown: TimeInterval) async -> SubstitutionDecision
}

/// Runs the constrained pass against the resident llama-server and returns the
/// guarded, diffed swaps. Empty on any failure or when nothing survives the guard.
public struct ContextSubstituteEngine: Sendable {
    let baseURL: URL
    let candidates: [String]
    let timeoutSeconds: TimeInterval

    public init(baseURL: URL, candidates: [String], timeoutSeconds: TimeInterval = 20) {
        self.baseURL = baseURL
        self.candidates = candidates
        self.timeoutSeconds = timeoutSeconds
    }

    public func proposals(for text: String) async -> [ProposedSwap] {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, !candidates.isEmpty else { return [] }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = ContextSubstitution.chatRequestBody(transcript: text, candidates: candidates)
        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            let raw = ContextSubstitution.parseContent(data)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
        else { return [] }
        let guarded = ContextSubstitution.guardOutput(raw, original: text, candidates: candidates)
        guard guarded != text else { return [] }
        return ContextSubstitution.diffSwaps(original: text, guarded: guarded)
    }
}
