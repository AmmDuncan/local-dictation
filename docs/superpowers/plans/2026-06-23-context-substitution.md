# Context Substitution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an experimental, opt-in pass that swaps misheard tech terms toward on-screen candidate terms, held in a countdown overlay with per-word toggles so the user confirms before the text is typed.

**Architecture:** A pure Core module (`ContextSubstitution`) does the constrained-prompt build, the deterministic guard (ported from `tools/accuracy-harness/substitution_ab.py`), the diff→swaps, and the apply. `DictationWorkflow` gains one async stage that calls an injected closure between `preCorrect` and the polisher. The App layer builds that closure: it runs `ContextSubstituteEngine` (HTTP to the resident llama-server), presents the new `reviewSubstitution` overlay phase via a `SubstitutionConfirming` impl, applies the accepted subset, and feeds accepted targets into the vocab learn loop. One shared resident model (catalog: E2B recommended + Qwen; E4B dropped).

**Tech Stack:** Swift 5.x, SwiftPM, SwiftUI/AppKit (macOS), hand-rolled test harness (`LocalDictationCoreTestRunner`), llama-server (OpenAI-compatible `/v1/chat/completions`).

## Global Constraints

- **Test framework:** hand-rolled. Add tests as `private func test…() throws` (or `async throws`) in `Sources/LocalDictationCoreTestRunner/main.swift`; register with `await suite.run("name", testFn)` in `main()`; assert with `try expect(<Bool>, "message")`. Run the whole suite: `swift run LocalDictationCoreTestRunner` (from `/Users/ammielyawson/work/tools/local-dictation-ctxsub`). There is no `--filter`; "verify it fails/passes" means run the whole suite and read the PASS/FAIL line for the new test.
- **Only `LocalDictationCore` is unit-testable** via that runner (it `import`s only `LocalDictationCore`). App-layer changes are verified with `swift build` + a manual smoke note.
- **Branch:** `feat/context-substitution` only. **Never push or merge any branch** unless the user explicitly asks.
- **`guard` is a reserved word** — name the guard function `guardOutput`.
- **Coordinate currency is UTF-16 `NSRange`** (matches `Edit.location/length` and `OverlayState.swappedRanges`).
- **Substitution model is shared with Polish** via the existing `polishModelPath`; do NOT add a separate model-path setting.
- **Request invariants** (match the validated A/B): `temperature: 0`, `chat_template_kwargs: ["enable_thinking": false]`.
- Commit after every task with the message shown in its final step.
- Run `swift build` green before every commit on App-layer tasks.

---

### Task 1: Add `.contextSub` to `Edit.Source`

**Files:**
- Modify: `Sources/LocalDictationCore/Edit.swift:23-25`
- Test: `Sources/LocalDictationCoreTestRunner/main.swift`

**Interfaces:**
- Produces: `Edit.Source.contextSub` — used by Tasks 4, 7, 15.

- [ ] **Step 1: Write the failing test** — add to `main.swift`:

```swift
private func testEditSourceContextSubRoundTrips() throws {
    let edit = Edit(location: 3, length: 6, from: "versal", to: "Vercel", source: .contextSub)
    let data = try JSONEncoder().encode(edit)
    let decoded = try JSONDecoder().decode(Edit.self, from: data)
    try expect(decoded.source == .contextSub, "contextSub source must round-trip through Codable")
}
```

- [ ] **Step 2: Register it** — add to `main()` near the other `suite.run` lines:

```swift
await suite.run("Edit.Source.contextSub round-trips", testEditSourceContextSubRoundTrips)
```

- [ ] **Step 3: Run to verify it fails**

Run: `swift run LocalDictationCoreTestRunner`
Expected: compile error or FAIL — `.contextSub` not a member of `Edit.Source`.

- [ ] **Step 4: Add the case** — edit `Edit.swift:23-25` so the enum reads:

```swift
public enum Source: String, Codable, Sendable {
    case strip, cleanup, mishearing, command, replacement, contextSub
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `swift run LocalDictationCoreTestRunner`
Expected: `PASS Edit.Source.contextSub round-trips`.

- [ ] **Step 6: Commit**

```bash
git add Sources/LocalDictationCore/Edit.swift Sources/LocalDictationCoreTestRunner/main.swift
git commit -m "feat(core): add Edit.Source.contextSub"
```

---

### Task 2: `ContextSubstitution.words` + `guardOutput` (port of the Python guard)

**Files:**
- Create: `Sources/LocalDictationCore/ContextSubstitution.swift`
- Test: `Sources/LocalDictationCoreTestRunner/main.swift`

**Interfaces:**
- Produces:
  - `enum ContextSubstitution`
  - `static func words(_ s: String) -> [String]` (lowercased, `[^a-z0-9 ]` stripped, split on spaces)
  - `static func guardOutput(_ output: String, original: String, candidates: [String]) -> String` — returns `output` if it passes all three guard conditions, else `original`.

- [ ] **Step 1: Write the failing tests** — add to `main.swift`:

```swift
private func testGuardAcceptsValidSwap() throws {
    let out = ContextSubstitution.guardOutput("deploy it to Vercel", original: "deploy it to versal", candidates: ["Vercel"])
    try expect(out == "deploy it to Vercel", "valid single candidate swap must pass")
}
private func testGuardAcceptsCompoundFix() throws {
    let out = ContextSubstitution.guardOutput("write it in TypeScript", original: "write it in type script", candidates: ["TypeScript"])
    try expect(out == "write it in TypeScript", "type script -> TypeScript (2->1) must pass")
}
private func testGuardRejectsOffList() throws {
    let out = ContextSubstitution.guardOutput("let's use Docker", original: "let's use cuban eats", candidates: ["Kubernetes"])
    try expect(out == "let's use cuban eats", "swapping in a non-candidate must reject to original")
}
private func testGuardRejectsCollapse() throws {
    let out = ContextSubstitution.guardOutput("Vercel", original: "deploy it to versal", candidates: ["Vercel"])
    try expect(out == "deploy it to versal", "dropping >1 word (collapse) must reject")
}
private func testGuardRejectsPureDeletion() throws {
    let out = ContextSubstitution.guardOutput("deploy it to", original: "deploy it to versal", candidates: ["Vercel"])
    try expect(out == "deploy it to versal", "dropping content with nothing added must reject")
}
private func testGuardCaseInsensitiveCandidate() throws {
    let out = ContextSubstitution.guardOutput("ping me on Slack", original: "ping me on slock", candidates: ["slack"])
    try expect(out == "ping me on Slack", "candidate match is case-insensitive")
}
```

- [ ] **Step 2: Register them** — add to `main()`:

```swift
await suite.run("guard accepts valid swap", testGuardAcceptsValidSwap)
await suite.run("guard accepts compound fix", testGuardAcceptsCompoundFix)
await suite.run("guard rejects off-list", testGuardRejectsOffList)
await suite.run("guard rejects collapse", testGuardRejectsCollapse)
await suite.run("guard rejects pure deletion", testGuardRejectsPureDeletion)
await suite.run("guard candidate is case-insensitive", testGuardCaseInsensitiveCandidate)
```

- [ ] **Step 3: Run to verify they fail**

Run: `swift run LocalDictationCoreTestRunner`
Expected: compile error — `ContextSubstitution` undefined.

- [ ] **Step 4: Create `ContextSubstitution.swift`**

```swift
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
```

- [ ] **Step 5: Run to verify they pass**

Run: `swift run LocalDictationCoreTestRunner`
Expected: all six `guard …` tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/LocalDictationCore/ContextSubstitution.swift Sources/LocalDictationCoreTestRunner/main.swift
git commit -m "feat(core): ContextSubstitution.words + guardOutput (port of P5 guard)"
```

---

### Task 3: `ProposedSwap` + `diffSwaps`

**Files:**
- Modify: `Sources/LocalDictationCore/ContextSubstitution.swift`
- Test: `Sources/LocalDictationCoreTestRunner/main.swift`

**Interfaces:**
- Produces:
  - `struct ProposedSwap: Equatable, Sendable { let range: NSRange; let from: String; let to: String }`
  - `static func diffSwaps(original: String, guarded: String) -> [ProposedSwap]` — one entry per contiguous changed token-run; `range` is the UTF-16 span in `original`; `from` is the original substring; `to` is the guarded replacement. Empty when texts are token-equal (case-insensitively).

- [ ] **Step 1: Write the failing tests** — add to `main.swift`:

```swift
private func testDiffSingleSwap() throws {
    let swaps = ContextSubstitution.diffSwaps(original: "deploy it to versal", guarded: "deploy it to Vercel")
    try expect(swaps.count == 1, "one swap expected")
    try expect(swaps[0].from == "versal" && swaps[0].to == "Vercel", "from/to text")
    let ns = "deploy it to versal" as NSString
    try expect(ns.substring(with: swaps[0].range) == "versal", "range must address the original word")
}
private func testDiffCompoundSwap() throws {
    let swaps = ContextSubstitution.diffSwaps(original: "write it in type script", guarded: "write it in TypeScript")
    try expect(swaps.count == 1, "compound is one swap")
    try expect(swaps[0].from == "type script" && swaps[0].to == "TypeScript", "2->1 compound from/to")
}
private func testDiffTwoSwaps() throws {
    let swaps = ContextSubstitution.diffSwaps(
        original: "deploy it to versal then spin up cuban eats",
        guarded:  "deploy it to Vercel then spin up Kubernetes")
    try expect(swaps.count == 2, "two independent swaps must stay separate")
    try expect(swaps[0].to == "Vercel" && swaps[1].to == "Kubernetes", "ordered targets")
}
private func testDiffNoChange() throws {
    let swaps = ContextSubstitution.diffSwaps(original: "the dock was full of boats", guarded: "the dock was full of boats")
    try expect(swaps.isEmpty, "identical text yields no swaps")
}
private func testDiffIgnoresCaseOnlyTokens() throws {
    let swaps = ContextSubstitution.diffSwaps(original: "deploy it to versal", guarded: "Deploy it to Vercel")
    try expect(swaps.count == 1 && swaps[0].to == "Vercel", "case-only differences are not swaps")
}
```

- [ ] **Step 2: Register them** — add to `main()`:

```swift
await suite.run("diff single swap", testDiffSingleSwap)
await suite.run("diff compound swap", testDiffCompoundSwap)
await suite.run("diff two swaps", testDiffTwoSwaps)
await suite.run("diff no change", testDiffNoChange)
await suite.run("diff ignores case-only tokens", testDiffIgnoresCaseOnlyTokens)
```

- [ ] **Step 3: Run to verify they fail**

Run: `swift run LocalDictationCoreTestRunner`
Expected: compile error — `ProposedSwap` / `diffSwaps` undefined.

- [ ] **Step 4: Implement** — append to `ContextSubstitution.swift` (add `ProposedSwap` at file top-level and these statics inside the enum):

```swift
public struct ProposedSwap: Equatable, Sendable {
    public let range: NSRange   // UTF-16 span in the working (pre-polish) text
    public let from: String     // original words, e.g. "cuban eats"
    public let to: String       // candidate target, e.g. "Kubernetes"
    public init(range: NSRange, from: String, to: String) {
        self.range = range; self.from = from; self.to = to
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
            while i < n, CharacterSet.whitespacesAndNewlines.contains(ns.character(at: i).unicodeScalar) { i += 1 }
            guard i < n else { break }
            let start = i
            while i < n, !CharacterSet.whitespacesAndNewlines.contains(ns.character(at: i).unicodeScalar) { i += 1 }
            let range = NSRange(location: start, length: i - start)
            tokens.append(Token(text: ns.substring(with: range), range: range))
        }
        return tokens
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
            let (a, b) = found ?? (ot.count - i, gt.count - j)  // no resync -> rest is one swap
            swaps.append(makeSwap(ot, gt, i, a, j, b, originalNS))
            i += max(a, 0); j += max(b, 0)
            if a == 0 && b == 0 { break }  // safety; shouldn't happen
        }
        if i < ot.count || j < gt.count {  // trailing mismatch
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
        } else {  // pure insertion: zero-length range at the current token
            let loc = i < ot.count ? ot[i].range.location : originalNS.length
            range = NSRange(location: loc, length: 0)
        }
        let from = range.length > 0 ? originalNS.substring(with: range) : ""
        let to = (j..<(j + b)).map { gt[$0].text }.joined(separator: " ")
        return ProposedSwap(range: range, from: from, to: to)
    }
}
```

> Note: `ns.character(at:).unicodeScalar` — if the compiler rejects the `UInt16`→`UnicodeScalar` access, replace the whitespace check with comparing against `unichar(32)`, `9`, `10`, `13`. Keep the tests green.

- [ ] **Step 5: Run to verify they pass**

Run: `swift run LocalDictationCoreTestRunner`
Expected: all five `diff …` tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/LocalDictationCore/ContextSubstitution.swift Sources/LocalDictationCoreTestRunner/main.swift
git commit -m "feat(core): ProposedSwap + diffSwaps token alignment"
```

---

### Task 4: `apply` (swaps → corrected text + Edits)

**Files:**
- Modify: `Sources/LocalDictationCore/ContextSubstitution.swift`
- Test: `Sources/LocalDictationCoreTestRunner/main.swift`

**Interfaces:**
- Produces: `static func apply(_ swaps: [ProposedSwap], to text: String) -> (String, [Edit])` — edits are in the OUTPUT coordinate space (so `EditFold.combine` can fold them), `source: .contextSub`.

- [ ] **Step 1: Write the failing tests**

```swift
private func testApplySingle() throws {
    let original = "deploy it to versal"
    let swaps = ContextSubstitution.diffSwaps(original: original, guarded: "deploy it to Vercel")
    let (out, edits) = ContextSubstitution.apply(swaps, to: original)
    try expect(out == "deploy it to Vercel", "applied text")
    try expect(edits.count == 1 && edits[0].source == .contextSub, "one contextSub edit")
    let ns = out as NSString
    try expect(ns.substring(with: edits[0].range) == "Vercel", "edit range addresses 'to' in OUTPUT space")
}
private func testApplyTwoSwapsOffsets() throws {
    let original = "deploy it to versal then spin up cuban eats"
    let swaps = ContextSubstitution.diffSwaps(original: original, guarded: "deploy it to Vercel then spin up Kubernetes")
    let (out, edits) = ContextSubstitution.apply(swaps, to: original)
    try expect(out == "deploy it to Vercel then spin up Kubernetes", "both applied")
    let ns = out as NSString
    try expect(ns.substring(with: edits[0].range) == "Vercel", "first edit range valid post-shift")
    try expect(ns.substring(with: edits[1].range) == "Kubernetes", "second edit range valid post-shift")
}
private func testApplyEmpty() throws {
    let (out, edits) = ContextSubstitution.apply([], to: "unchanged")
    try expect(out == "unchanged" && edits.isEmpty, "no swaps -> no change")
}
```

- [ ] **Step 2: Register**

```swift
await suite.run("apply single swap", testApplySingle)
await suite.run("apply two swaps offsets", testApplyTwoSwapsOffsets)
await suite.run("apply empty", testApplyEmpty)
```

- [ ] **Step 3: Run to verify they fail**

Run: `swift run LocalDictationCoreTestRunner`
Expected: compile error — `apply` undefined.

- [ ] **Step 4: Implement** — append inside the `extension ContextSubstitution`:

```swift
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
```

- [ ] **Step 5: Run to verify they pass**

Run: `swift run LocalDictationCoreTestRunner`
Expected: all three `apply …` tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/LocalDictationCore/ContextSubstitution.swift Sources/LocalDictationCoreTestRunner/main.swift
git commit -m "feat(core): ContextSubstitution.apply -> text + contextSub edits"
```

---

### Task 5: Constrained prompt + request body + response parse

**Files:**
- Modify: `Sources/LocalDictationCore/ContextSubstitution.swift`
- Test: `Sources/LocalDictationCoreTestRunner/main.swift`

**Interfaces:**
- Produces:
  - `static func systemPrompt(candidates: [String]) -> String` (the CONSTRAINED prompt, `{cands}` filled).
  - `static func chatRequestBody(transcript: String, candidates: [String]) -> Data`
  - `static func parseContent(_ data: Data) -> String?`

- [ ] **Step 1: Write the failing tests**

```swift
private func testRequestBodyShape() throws {
    let data = ContextSubstitution.chatRequestBody(transcript: "deploy it to versal", candidates: ["Vercel", "Netlify"])
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    try expect((json["temperature"] as? Double) == 0, "temperature must be 0")
    let kwargs = json["chat_template_kwargs"] as? [String: Any]
    try expect((kwargs?["enable_thinking"] as? Bool) == false, "thinking disabled")
    let messages = json["messages"] as! [[String: String]]
    try expect(messages.first?["role"] == "system", "first message is system")
    try expect(messages.first!["content"]!.contains("Vercel, Netlify"), "system prompt lists candidates")
    try expect(messages.last?["role"] == "user", "last message is user")
    try expect(messages.last!["content"]!.contains("deploy it to versal"), "user carries the transcript")
}
private func testParseContent() throws {
    let payload = #"{"choices":[{"message":{"content":"deploy it to Vercel"}}]}"#.data(using: .utf8)!
    try expect(ContextSubstitution.parseContent(payload) == "deploy it to Vercel", "parses choices[0].message.content")
}
```

- [ ] **Step 2: Register**

```swift
await suite.run("substitution request body shape", testRequestBodyShape)
await suite.run("substitution parseContent", testParseContent)
```

- [ ] **Step 3: Run to verify they fail**

Run: `swift run LocalDictationCoreTestRunner`
Expected: compile error — symbols undefined.

- [ ] **Step 4: Implement** — append inside the `extension ContextSubstitution`:

```swift
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
```

- [ ] **Step 5: Run to verify they pass**

Run: `swift run LocalDictationCoreTestRunner`
Expected: both tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/LocalDictationCore/ContextSubstitution.swift Sources/LocalDictationCoreTestRunner/main.swift
git commit -m "feat(core): constrained prompt + request body + response parse"
```

---

### Task 6: `ContextSubstituteEngine` + confirmer protocol/decision types

**Files:**
- Modify: `Sources/LocalDictationCore/ContextSubstitution.swift`

**Interfaces:**
- Consumes: `chatRequestBody`, `parseContent`, `guardOutput`, `diffSwaps` (Tasks 2–5).
- Produces:
  - `struct ContextSubstituteEngine: Sendable { init(baseURL: URL, candidates: [String]); func proposals(for text: String) async -> [ProposedSwap] }`
  - `enum SubstitutionDecision: Equatable, Sendable { case keepOriginal; case apply([ProposedSwap]) }`
  - `protocol SubstitutionConfirming: Sendable { func confirm(text: String, swaps: [ProposedSwap], countdown: TimeInterval) async -> SubstitutionDecision }`

*(No unit test — the HTTP path needs a live server; the pure helpers it calls are covered by Tasks 2–5. Verified by `swift build`.)*

- [ ] **Step 1: Implement** — append to `ContextSubstitution.swift`:

```swift
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
```

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/LocalDictationCore/ContextSubstitution.swift
git commit -m "feat(core): ContextSubstituteEngine + SubstitutionConfirming protocol"
```

---

### Task 7: Wire the async substitution stage into `DictationWorkflow`

**Files:**
- Modify: `Sources/LocalDictationCore/DictationWorkflow.swift` (init :99-115, stored props ~:91, finishRecording :184-191)
- Test: `Sources/LocalDictationCoreTestRunner/main.swift`

**Interfaces:**
- Consumes: `EditFold.combine`, `Edit`.
- Produces: new init param `contextSubstitute: (@Sendable (String) async -> (String, [Edit]))? = nil`; its edits are folded into `segmentA` before the `prePolish` snapshot.

- [ ] **Step 1: Write the failing test** — this verifies the workflow calls the stage and folds its edits. It exercises `finishRecording` via the existing mic-less pipeline path. If a lighter seam exists in `main.swift` for workflow tests, follow it; otherwise add a focused test of the fold using a stub closure as below. (Use the existing recorder-override pipeline test as the template — search `recorderOverride` usages in `main.swift`.)

```swift
private func testContextSubstituteFoldsIntoSegmentA() async throws {
    // A stub stage that swaps "versal" -> "Vercel" and reports the edit.
    let stage: @Sendable (String) async -> (String, [Edit]) = { text in
        ContextSubstitution.apply(
            ContextSubstitution.diffSwaps(original: text, guarded: text.replacingOccurrences(of: "versal", with: "Vercel")),
            to: text)
    }
    let (out, edits) = await stage("deploy it to versal")
    try expect(out == "deploy it to Vercel", "stage applies the swap")
    let folded = EditFold.combine([[], edits])
    try expect(folded.count == 1 && folded[0].source == .contextSub, "edits fold into segmentA space")
}
```

> This is a focused fold test (the full `finishRecording` integration with the real engine + confirmer is verified manually in Task 13). It guards the contract that Task 7's wiring relies on.

- [ ] **Step 2: Register**

```swift
await suite.run("contextSubstitute folds into segmentA", testContextSubstituteFoldsIntoSegmentA)
```

- [ ] **Step 3: Run to verify it passes already** (pure fold over existing APIs)

Run: `swift run LocalDictationCoreTestRunner`
Expected: PASS (this test only depends on Tasks 3–4 + `EditFold`).

- [ ] **Step 4: Add the stored property** — after `DictationWorkflow.swift:91`:

```swift
    private let contextSubstitute: (@Sendable (String) async -> (String, [Edit]))?
```

- [ ] **Step 5: Add the init parameter + assignment** — in `init` (:99-115), add the parameter after `preCorrect` and assign it:

```swift
        preCorrect: (@Sendable (String) -> (String, [Edit]))? = nil,
        contextSubstitute: (@Sendable (String) async -> (String, [Edit]))? = nil,
        polisher: TextPolishing? = nil,
```
```swift
        self.preCorrect = preCorrect
        self.contextSubstitute = contextSubstitute
        self.polisher = polisher
```

- [ ] **Step 6: Wire the call** — in `finishRecording`, between the `preCorrect` block (ends :189) and `let prePolish = insertText`:

```swift
            if let preCorrect {
                let (corrected, edits) = preCorrect(insertText)
                insertText = corrected
                segmentA = edits
            }
            // Context substitution (async; may suspend for the confirm overlay).
            // Folds its edits into Segment A so they share the pre-polish space
            // and surface as CONTEXT chips in the review panel.
            if let contextSubstitute {
                let (corrected, edits) = await contextSubstitute(insertText)
                insertText = corrected
                segmentA = EditFold.combine([segmentA, edits])
            }
            let prePolish = insertText
```

- [ ] **Step 7: Verify build + suite**

Run: `swift build && swift run LocalDictationCoreTestRunner`
Expected: builds; all tests including the new one PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/LocalDictationCore/DictationWorkflow.swift Sources/LocalDictationCoreTestRunner/main.swift
git commit -m "feat(core): async contextSubstitute stage in DictationWorkflow"
```

---

### Task 8: Catalog — add Gemma 4 E2B (recommended), drop E4B, demote Qwen note

**Files:**
- Modify: `Sources/LocalDictationApp/Models/PolishModelStore.swift:27-38`

*(App layer — verified by `swift build` + Models-tab smoke.)*

- [ ] **Step 1: Edit `PolishModelCatalog.all`** — set the E2B entry as recommended, keep Qwen (note demoted), ensure NO E4B entry exists:

```swift
PolishModel(
    id: "gemma-4-e2b",
    displayName: "Gemma 4 E2B",
    filename: "google_gemma-4-E2B-it-Q4_K_M.gguf",
    sizeBytes: 3_462_678_272,
    sha256: "b5310340b3a23d31655d7119d100d5df1b2d8ee17b3ca8b0a23ad7e9eb5fa705",
    url: URL(string: "https://huggingface.co/bartowski/google_gemma-4-E2B-it-GGUF/resolve/main/google_gemma-4-E2B-it-Q4_K_M.gguf")!,
    note: "Recommended",
    detail: "Safest · best accuracy · fewest false swaps for context substitution"
),
PolishModel(
    id: "qwen3.5-4b",
    displayName: "Qwen 3.5 4B",
    filename: "Qwen_Qwen3.5-4B-Q4_K_M.gguf",
    sizeBytes: 3_013_027_808,
    sha256: "13c16f426047e2de38cd075bdade4a7bcbc8c774384876f677740cda65f8a983",
    url: URL(string: "https://huggingface.co/bartowski/Qwen_Qwen3.5-4B-GGUF/resolve/main/Qwen_Qwen3.5-4B-Q4_K_M.gguf")!,
    note: nil,
    detail: "Smallest download · more false corrections"
)
```

> Verify the `PolishModel` field order/labels against the struct (`PolishModelStore.swift:5`) and that the file resolves `filename == URL basename` like Qwen.

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/LocalDictationApp/Models/PolishModelStore.swift
git commit -m "feat(models): add Gemma 4 E2B (recommended), drop E4B from catalog"
```

---

### Task 9: Settings keys/defaults/snapshot for the experimental toggle

**Files:**
- Modify: `Sources/LocalDictationApp/AppSettings.swift` (keys :4-27, snapshot fields ~:42-43, `.current` ~:77-79, `Defaults` ~:153-155, `registerDefaults` ~:104)

*(App layer — verified by `swift build`.)*

- [ ] **Step 1: Add keys** — in `AppSettingsKeys`:

```swift
    static let contextSubstitutionEnabled = "contextSubstitutionEnabled"
    static let contextSubstitutionCountdown = "contextSubstitutionCountdown"
    static let rejectedContextSubSwaps = "rejectedContextSubSwaps"
```

- [ ] **Step 2: Add snapshot fields** — near `polishWithAI`/`polishModelPath`:

```swift
    var contextSubstitutionEnabled: Bool
    var contextSubstitutionCountdown: Double
    var rejectedContextSubSwaps: String
```

- [ ] **Step 3: Populate `.current`** — near the polish lines:

```swift
            contextSubstitutionEnabled: defaults.object(forKey: AppSettingsKeys.contextSubstitutionEnabled) as? Bool ?? Defaults.contextSubstitutionEnabled,
            contextSubstitutionCountdown: defaults.object(forKey: AppSettingsKeys.contextSubstitutionCountdown) as? Double ?? Defaults.contextSubstitutionCountdown,
            rejectedContextSubSwaps: defaults.string(forKey: AppSettingsKeys.rejectedContextSubSwaps) ?? Defaults.rejectedContextSubSwaps,
```

- [ ] **Step 4: Add defaults** — in `Defaults`:

```swift
        static let contextSubstitutionEnabled = false  // experimental: constrained LLM swap with countdown confirm
        static let contextSubstitutionCountdown: Double = 5.0
        static let rejectedContextSubSwaps = ""
```

- [ ] **Step 5: Register defaults** — in `registerDefaults`:

```swift
            AppSettingsKeys.contextSubstitutionEnabled: Defaults.contextSubstitutionEnabled,
            AppSettingsKeys.contextSubstitutionCountdown: Defaults.contextSubstitutionCountdown,
            AppSettingsKeys.rejectedContextSubSwaps: Defaults.rejectedContextSubSwaps,
```

- [ ] **Step 6: Verify build + commit**

```bash
swift build
git add Sources/LocalDictationApp/AppSettings.swift
git commit -m "feat(settings): context-substitution keys, defaults, snapshot"
```

---

### Task 10: Decouple `warmUpPolishServer` from `polishWithAI`

**Files:**
- Modify: `Sources/LocalDictationApp/AppModel.swift:207-218`

- [ ] **Step 1: Edit `warmUpPolishServer`** so it warms when either feature is on:

```swift
    /// Start (or stop) the resident llama-server for the optional LLM passes
    /// (formatting polish and/or experimental context substitution). Both share
    /// one resident model (settings.polishModelPath).
    private func warmUpPolishServer(settings: AppSettingsSnapshot) {
        guard settings.polishWithAI || settings.contextSubstitutionEnabled else {
            llamaManager.stop()
            return
        }
        let model = settings.polishModelPath.expandingTildeInPath
        guard FileManager.default.fileExists(atPath: model),
              let server = WhisperLocator.resolvedLlamaServer() else {
            return
        }
        llamaManager.ensureRunning(modelPath: model, executablePath: server)
    }
```

- [ ] **Step 2: Verify build + commit**

```bash
swift build
git add Sources/LocalDictationApp/AppModel.swift
git commit -m "feat(app): warm resident server for context substitution too"
```

---

### Task 11: `reviewSubstitution` overlay phase + countdown/toggle UI + confirmer impl

**Files:**
- Modify: `Sources/LocalDictationApp/OverlayController.swift` (DictationPhase :6-12, OverlayState :15-27, present API :63-108, cardHeight :49-57)
- Modify: `Sources/LocalDictationApp/OverlayView.swift` (new phase body)
- Create: `Sources/LocalDictationApp/SubstitutionConfirmer.swift`

*(App/UI — verified by `swift build` + manual smoke in Task 13. This is the largest UI task.)*

- [ ] **Step 1: Extend `DictationPhase`** (`OverlayController.swift:6-12`):

```swift
enum DictationPhase: Equatable {
    case listening
    case transcribing
    case reviewSubstitution
    case done
    case error
    case cancelled
}
```

- [ ] **Step 2: Add overlay state for the review phase** — on `OverlayState`:

```swift
    /// Proposed swaps for the .reviewSubstitution phase, with per-swap accepted flag.
    var pendingSwaps: [PendingSwap] = []
    var countdownTotal: TimeInterval = 5
    var countdownRemaining: TimeInterval = 5

    struct PendingSwap: Identifiable, Equatable {
        let id: Int            // 1-based index = the number key
        let from: String
        let to: String
        var accepted: Bool = true
    }
```

- [ ] **Step 3: Add `cardHeight` case** (:49-57): `case .reviewSubstitution: 260`.

- [ ] **Step 4: Add the present method** — on `OverlayController`:

```swift
func showReviewSubstitution(swaps: [OverlayState.PendingSwap], countdown: TimeInterval) {
    stopLevelUpdates()
    state.pendingSwaps = swaps
    state.countdownTotal = countdown
    state.countdownRemaining = countdown
    present(phase: .reviewSubstitution, title: "Review swaps before typing", detail: "")
}
```

- [ ] **Step 5: Add the SwiftUI body** in `OverlayView.swift` — a `reviewSubstitutionBody` modeled on `doneBody`, reusing the glass card/halo/accent bar already in `body`. Render the quote with emerald-underlined accepted swaps (extend the existing `doneAttributed` approach), a numbered legend of `state.pendingSwaps` (✓ applied / ↩ kept original per `accepted`), a countdown ring driven by `state.countdownRemaining / state.countdownTotal`, and an `↵ Apply now` `SignalButtonStyle` capsule. Wire the case in `body(for:)`:

```swift
case .reviewSubstitution: reviewSubstitutionBody
```

> Match the mockup (easel #1): header icon tile (sparkles), `On-device` pill, quote box (`ink.opacity(0.05)`), legend rows with `numkey` badges, countdown ring, apply capsule. Keep all sizes/colors from `Brand`.

- [ ] **Step 6: Create `SubstitutionConfirmer.swift`** — the `SubstitutionConfirming` impl that drives the overlay and resolves via a continuation:

```swift
import Foundation
import LocalDictationCore

@MainActor
final class SubstitutionConfirmer: SubstitutionConfirming {
    private let overlay: OverlayController
    private var timerTask: Task<Void, Never>?

    init(overlay: OverlayController) { self.overlay = overlay }

    nonisolated func confirm(text: String, swaps: [ProposedSwap], countdown: TimeInterval) async -> SubstitutionDecision {
        await MainActor.run { presentAndAwait(text: text, swaps: swaps, countdown: countdown) }
        // presentAndAwait returns the decision via the continuation below.
        return await withCheckedContinuation { cont in
            Task { @MainActor in self.pending = cont; self.armResolution(swaps: swaps, countdown: countdown) }
        }
    }

    // Implementation detail: store the continuation, tick the countdown
    // (updating overlay.state.countdownRemaining), map number keys to toggle
    // overlay.state.pendingSwaps[i].accepted, ↵ -> resolve(.apply(accepted)),
    // esc -> resolve(.keepOriginal), timeout -> resolve(.apply(accepted)).
    // Resolve exactly once; cancel the timer; hide the overlay.
}
```

> The number-key / ↵ / esc handling reuses the app's existing global key handling for the overlay (search how `.error`/`.done` cards capture keys, or add a local `NSEvent` monitor while `.reviewSubstitution` is showing). The continuation must resolve exactly once. On resolve, build `[ProposedSwap]` from the still-`accepted` `pendingSwaps` (match by `id` to the original `swaps`).

- [ ] **Step 7: Verify build**

Run: `swift build`
Expected: builds clean (UI behavior verified in Task 13).

- [ ] **Step 8: Commit**

```bash
git add Sources/LocalDictationApp/OverlayController.swift Sources/LocalDictationApp/OverlayView.swift Sources/LocalDictationApp/SubstitutionConfirmer.swift
git commit -m "feat(ui): reviewSubstitution overlay phase + countdown/toggle confirmer"
```

---

### Task 12: Wire the stage in `AppModel.makeWorkflow` + learn loop

**Files:**
- Modify: `Sources/LocalDictationApp/AppModel.swift:426-508` (makeWorkflow), add a stored `substitutionConfirmer`

*(App layer — verified by `swift build` + manual smoke in Task 13.)*

- [ ] **Step 1: Add a stored confirmer** on `AppModel` (near `overlayController`):

```swift
    private lazy var substitutionConfirmer = SubstitutionConfirmer(overlay: overlayController)
```

- [ ] **Step 2: Build the `contextSubstitute` closure in `makeWorkflow`** — after the `preCorrect` block, before `return DictationWorkflow(...)`:

```swift
        // Experimental context substitution: a constrained LLM swap toward
        // on-screen candidates, held in the countdown overlay for confirmation.
        // Shares the resident polish model. Reuses the SAME candidates whisper
        // is biased with (ContextBias), so swaps only target present terms.
        let ctxSubEnabled = settings.contextSubstitutionEnabled
        let candidates: [String] = context
            .map { ContextBias.promptContext(for: $0) }
            .map { $0.candidates + $0.appVocabulary } ?? []
        let countdown = settings.contextSubstitutionCountdown
        let confirmer = substitutionConfirmer
        let manager = llamaManager
        let contextSubstitute: (@Sendable (String) async -> (String, [Edit]))? = (ctxSubEnabled && !candidates.isEmpty)
            ? { @Sendable text in
                guard let baseURL = await manager.awaitReady(timeout: 30) else { return (text, []) }
                let engine = ContextSubstituteEngine(baseURL: baseURL, candidates: candidates)
                let swaps = await engine.proposals(for: text)
                guard !swaps.isEmpty else { return (text, []) }
                let decision = await confirmer.confirm(text: text, swaps: swaps, countdown: countdown)
                switch decision {
                case .keepOriginal:
                    return (text, [])
                case .apply(let accepted):
                    guard !accepted.isEmpty else { return (text, []) }
                    let (corrected, edits) = ContextSubstitution.apply(accepted, to: text)
                    await MainActor.run { self.learnAcceptedTargets(accepted.map(\.to)) }
                    return (corrected, edits)
                }
            }
            : nil
```

- [ ] **Step 3: Pass it to the workflow** — add `contextSubstitute: contextSubstitute,` to the `DictationWorkflow(...)` call (after `preCorrect:`).

- [ ] **Step 4: Add the learn-loop helper** on `AppModel`:

```swift
    /// Persist accepted swap targets to custom vocabulary so whisper biases
    /// toward them next time (the virtuous cycle). De-duped by the helper.
    private func learnAcceptedTargets(_ targets: [String]) {
        var vocab = UserDefaults.standard.string(forKey: AppSettingsKeys.customVocabulary) ?? ""
        for t in targets { vocab = CustomVocabulary.appending(t, to: vocab) }
        UserDefaults.standard.set(vocab, forKey: AppSettingsKeys.customVocabulary)
    }
```

- [ ] **Step 5: Verify build**

Run: `swift build`
Expected: builds clean. (Resolve any `@Sendable`/actor-capture errors by capturing locals as shown — never capture `self` inside the `@Sendable` closure except via the `MainActor.run` hop.)

- [ ] **Step 6: Commit**

```bash
git add Sources/LocalDictationApp/AppModel.swift
git commit -m "feat(app): wire context-substitution stage + accepted-swap learn loop"
```

---

### Task 13: Experimental toggle + countdown slider in Settings

**Files:**
- Modify: `Sources/LocalDictationApp/Settings/GeneralTab.swift` (bindings + a new section), and wherever `GeneralTab` is constructed (`SettingsView.swift`)

*(App/UI — verified by `swift build` + manual smoke.)*

- [ ] **Step 1: Add bindings** to `GeneralTab`:

```swift
    @Binding var contextSubstitutionEnabled: Bool
    @Binding var contextSubstitutionCountdown: Double
```

- [ ] **Step 2: Add the UI** — in an "Experimental" `Section` (mirror the `polishWithAI` Toggle pattern at :41-48):

```swift
Toggle(isOn: $contextSubstitutionEnabled) {
    ExperimentalLabel("Context substitution")
}
.help("Fix misheard tech terms using what's on your screen. Each swap is held in the overlay with a countdown — you confirm or undo before it's typed. Uses your selected AI model (Models tab). On-device.")
if contextSubstitutionEnabled {
    HStack {
        Text("Countdown")
        Slider(value: $contextSubstitutionCountdown, in: 2...10, step: 0.5)
        Text("\(contextSubstitutionCountdown, specifier: "%.1f")s").monospacedDigit()
    }
}
```

- [ ] **Step 3: Pass the bindings** where `GeneralTab(...)` is instantiated in `SettingsView.swift`, following the existing `polishWithAI:` binding wiring (e.g. `contextSubstitutionEnabled: $settings.contextSubstitutionEnabled` or the `@AppStorage` pattern used there).

- [ ] **Step 4: Verify build + commit**

```bash
swift build
git add Sources/LocalDictationApp/Settings/GeneralTab.swift Sources/LocalDictationApp/SettingsView.swift
git commit -m "feat(settings): context-substitution experimental toggle + countdown slider"
```

---

### Task 14: Review panel — CONTEXT chip + suppression

**Files:**
- Modify: `Sources/LocalDictationApp/ReviewPanel.swift` (chip render ~:248, revert ~:396)

*(App/UI — verified by `swift build` + manual smoke.)*

- [ ] **Step 1: Distinguish `.contextSub` chips** — in `changeChip(index:edit:)`, show a `CONTEXT` eyebrow (emerald) when `edit.source == .contextSub`, vs the existing `HEARD` label for `.mishearing`/`.command`. Keep the `from → to` body and × identical.

- [ ] **Step 2: Suppress reverted context swaps** — in `revertChange(index:edit:)`, when `edit.source == .contextSub`, persist to `AppSettingsKeys.rejectedContextSubSwaps` (mirror how `.mishearing`/`.command` write `rejectedBuiltInSwaps`), not `rejectedBuiltInSwaps`.

- [ ] **Step 3: Verify build + commit**

```bash
swift build
git add Sources/LocalDictationApp/ReviewPanel.swift
git commit -m "feat(review): CONTEXT chip + context-sub revert suppression"
```

---

### Task 15: Fix the pre-existing done-card review-hint bug

**Files:**
- Modify: `Sources/LocalDictationApp/OverlayView.swift:208`

- [ ] **Step 1: Correct the shortcut text** — the done card says `"⌥Z to review"` but the actual shortcut is `⌃⌥Z` (`LocalDictationApp.swift:447`). Change the literal at `OverlayView.swift:208`:

```swift
Text("⌃⌥Z to review")
```

- [ ] **Step 2: Verify build + commit**

```bash
swift build
git add Sources/LocalDictationApp/OverlayView.swift
git commit -m "fix(ui): done-card review hint says correct shortcut (⌃⌥Z)"
```

---

### Task 16: Full-suite + manual smoke + final build

**Files:** none (verification)

- [ ] **Step 1: Run the full Core suite**

Run: `swift run LocalDictationCoreTestRunner`
Expected: `All N tests passed.` (includes every test from Tasks 1–7).

- [ ] **Step 2: Release build**

Run: `swift build -c release`
Expected: builds clean.

- [ ] **Step 3: Regression — re-run the substitution harness against E2B** (guards against prompt drift):

Run: `cd tools/accuracy-harness && python3 substitution_ab.py --models ~/models/gemma-4-E2B-it-Q4_K_M.gguf`
Expected: constrained ≈ 19/24 fixed, ≈ 2/26 corrupted (matches the design's E2B numbers).

- [ ] **Step 4: Manual smoke (signed build per project convention)** — verify, with `Context substitution` ON and the E2B model selected:
  1. Dictate a sentence with a clear mishearing of an on-screen term → overlay holds, shows the swap + countdown.
  2. Let it time out → swap applies; press a number key → that swap reverts; press `↵` → applies immediately; press `esc` → original pastes.
  3. Dictate a sentence with NO candidate mishearing → no overlay, instant paste (unchanged).
  4. Accept a swap → confirm its target appears in custom vocabulary (Learn/General tab).
  5. `⌃⌥Z` → review panel shows the accepted swaps as CONTEXT chips; × reverts one.
  6. Toggle the feature OFF → behaves exactly like today.

- [ ] **Step 5: Report** results to the user (test count, build status, harness numbers, smoke outcomes). Do NOT push/merge.

---

## Self-Review

**Spec coverage:** decisions a/a′ (countdown + per-word toggle) → Tasks 11/12; b (separate toggle) → Tasks 9/13; c (ContextBias candidates) → Task 12; d (constrained prompt + guard) → Tasks 2/5/6; e (E2B default, drop E4B) → Task 8; f (learn loop) → Task 12. Pipeline hook → Task 7. CONTEXT chip → Task 14. warmUp decouple → Task 10. Hint bug → Task 15. ✓ all covered.

**Placeholder scan:** Core tasks (1–7) carry complete code + tests. App/UI tasks (8–15) carry complete new code and exact edit targets; the genuinely UI-bound behaviors (key handling in Task 11, binding wiring in Task 13) name the existing pattern to follow and are gated by `swift build` + Task 16's manual smoke — acceptable because the hand-rolled Core runner cannot unit-test SwiftUI/AppKit.

**Type consistency:** `ContextSubstitution.{words,guardOutput,diffSwaps,apply,systemPrompt,chatRequestBody,parseContent}`, `ProposedSwap{range,from,to}`, `SubstitutionDecision{keepOriginal,apply}`, `SubstitutionConfirming.confirm(text:swaps:countdown:)`, `ContextSubstituteEngine.proposals(for:)`, `DictationWorkflow.contextSubstitute`, `Edit.Source.contextSub`, settings keys `contextSubstitutionEnabled/contextSubstitutionCountdown/rejectedContextSubSwaps` — names consistent across all tasks.
