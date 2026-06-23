# Context-Substitution Feature — Code Map

> Synthesized from 6 subsystem reader passes (2026-06-23). All file:line references and code quotes are verbatim from those reads — no inferred paths.

---

## 1. End-to-End Pipeline Today

### 1.1 Full data flow with hook point

```
Audio (WAV)
  │
  ▼
TranscriptionEngine.transcribe(audioFile:)
  │  WhisperServerEngine (HTTP) or whisper-CLI subprocess
  │  → raw: String
  │
  ▼
WhisperTranscriptParser.strippedForInsertion(raw)
  │  strips [BLANK_AUDIO] / (music) / *whispers* / ♪
  │
  ▼  [if settings.cleanUpTranscript]
TranscriptCleaner.clean(text, options:)
  │  filler removal (um/uh/hmm), spacing, capitalization
  │
  ▼  [if wantsCorrection || commandMode]
preCorrect(text) → (prePolish: String, segmentA: [Edit])
  ├─ MishearingCorrections.applyTracked(to:suppressing:)
  └─ CommandModeCorrections.applyTracked(to:appClass:precedingText:suppressing:)
  │   ← Segment A edits produced here; coordinate space = prePolish
  │   ← prePolish saved as CorrectionRecord.prePolish
  │
  ▼  ← ★ CONTEXT-SUBSTITUTION HOOK POINT (see §1.2) ★
  │
  ▼  [if settings.polishWithAI]
polisher.polish(insertText) → String
  │  LlamaPolishEngine → POST /v1/chat/completions on llamaManager port
  │  guarded by TranscriptPolisher.preservesContentWords()
  │  → correctedTranscript (shown in overlay/history)
  │
  ▼  [if settings.useTextReplacements]
postProcess(text) → (inserted: String, segmentB: [Edit])
  └─ TextReplacements.applyTracked   ← Segment B edits
  │   ← segmentB coordinate space = inserted (final)
  │
  ▼
inserter.insert(final)
  ClipboardInserter or KeystrokeInserter
  optionally wrapped in CaretAwareInserter (smart spacing/case)
  │
  ▼
Done-card overlay  →  ⌃⌥Z opens ReviewPanel
```

Pipeline runner: `DictationWorkflow.finishRecording()` — `DictationWorkflow.swift:147`

Result tuple: `DictationWorkflow.TranscriptEdits = (raw, prePolish, final, segmentA, segmentB)` — `DictationWorkflow.swift:46`

### 1.2 Precise hook point

**Best slot: new `contextCorrect` stage between `preCorrect` and `polisher`.**

Code site in `DictationWorkflow.swift`:
```swift
// lines 185–197 (current preCorrect → polisher block):
if let preCorrect {
    let (corrected, edits) = preCorrect(insertText)
    insertText = corrected
    segmentA = edits
}
prePolish = insertText     // ← prePolish snapshotted here

// ★ NEW: contextCorrect runs here, folds edits into segmentA
if let contextCorrect {
    let (corrected, edits) = contextCorrect(insertText)
    insertText = corrected
    segmentA = EditFold.combine(segmentA, edits)
}

if let polisher {
    insertText = await polisher.polish(insertText)   // lines 195–197
}
```

Three alternative placements and their trade-offs:

| Slot | When to use | Trade-off |
|---|---|---|
| New `contextCorrect` param in `DictationWorkflow.init` (between `preCorrect` and `polisher`) | **Recommended.** Edits are tracked in segmentA; chips appear in ReviewPanel automatically; review panel's caret-space verification works before polish shifts offsets. | Requires `DictationWorkflow.init` signature change + `AppModel.makeWorkflow` wiring |
| Replace/extend the existing `polisher` slot | Reuses the existing `TextPolishing?` param; no signature change needed | `preservesContentWords` guard at `TranscriptPolisher.swift:119` **will always reject** word substitutions. Must use a custom conformer that bypasses or replaces the guard. `TextPolishing.polish(_:)` only receives the transcript, not context — capture context at init time. |
| New stage after `polisher` and before `postProcess` | Edits live in the same coordinate space as `inserted` → `maybeReinsert` range check works without rebasing | Context not guaranteed to survive polish rewriting; two LLM calls sequential |

---

## 2. Reusable Infrastructure

### 2.1 llama-server warmup path

**`ResidentServerManager`** — `ResidentServerManager.swift`

```swift
// Config for the llama subprocess:
static var llama: Config  // line 41
// Args: -m <model> --host 127.0.0.1 --port <port> -c 2048 -ngl 99 --no-webui
// Health: GET /health → HTTP 200
```

Key methods:
- `func ensureRunning(modelPath: String, executablePath: String)` — line 86. No-op if same model already running.
- `func awaitReady(timeout: TimeInterval) async -> URL?` — line 72. Polls up to timeout; returns `baseURL` or nil.
- `var baseURL: URL?` — line 64. Non-nil only when `isReady && port > 0`.

**`AppModel.warmUpPolishServer`** — `AppModel.swift:207`
```swift
private func warmUpPolishServer(settings: AppSettingsSnapshot) {
    guard settings.polishWithAI else { llamaManager.stop(); return }
    let model = settings.polishModelPath.expandingTildeInPath
    guard FileManager.default.fileExists(atPath: model),
          let server = WhisperLocator.resolvedLlamaServer() else { return }
    llamaManager.ensureRunning(modelPath: model, executablePath: server)
}
```
`llamaManager` is a single `ResidentServerManager` (`@MainActor @Observable`). The same process + port is reused for any number of POSTs with different system prompts — the context-substitution pass needs no second process.

**`ServerBackedPolisher`** — `AppModel.swift:728` (private)
```swift
private struct ServerBackedPolisher: TextPolishing {
    let serverManager: ResidentServerManager
    let serverWait: TimeInterval
    func polish(_ text: String) async -> String
    // calls serverManager.awaitReady(timeout: serverWait), then LlamaPolishEngine
}
```
`serverWait: 30` — cold-load of a 4B GGUF can stall 15–25s; the overlay shows "Transcribing…" during this window.

**`WhisperLocator.resolvedLlamaServer()`** — `WhisperLocator.swift`
Finds bundled `Contents/Helpers/llama-server`, falls back to Homebrew.

**Gating note:** `warmUpPolishServer` gates on `settings.polishWithAI`. A context-substitution toggle that reuses `llamaManager` is automatically gated — if polish is off, the server never starts and `awaitReady` returns nil immediately, so the pass self-disables. If substitution must run independently of polish, either add a second `ResidentServerManager` or decouple the warm-up from `polishWithAI`.

### 2.2 PolishModelStore catalog shape

**`PolishModel`** — `PolishModelStore.swift:5`
```swift
struct PolishModel: Identifiable, Hashable, DownloadableModel {
    let id: String
    let displayName: String
    let filename: String
    let sizeBytes: Int64
    let sha256: String
    let url: URL
    let note: String?
    let detail: String
}
```

**`PolishModelCatalog.all`** — `PolishModelStore.swift:27–38`
Currently one entry:
```swift
PolishModel(
    id: "qwen3.5-4b",
    displayName: "Qwen 3.5 4B",
    filename: "Qwen_Qwen3.5-4B-Q4_K_M.gguf",
    sizeBytes: 3_013_027_808,
    sha256: "13c16f426047e2de38cd075bdade4a7bcbc8c774384876f677740cda65f8a983",
    url: URL(string: "https://huggingface.co/bartowski/Qwen_Qwen3.5-4B-GGUF/resolve/main/Qwen_Qwen3.5-4B-Q4_K_M.gguf")!,
    note: "Recommended",
    detail: "Current-gen · sharp intent · thinking auto-disabled for faithful polish"
)
```

Adding an entry to `PolishModelCatalog.all` is sufficient to make it appear in `PolishModelManagerView` with Download/Use/Active controls — no store subclass change needed. `PolishModelManagerView` iterates `PolishModelCatalog.all` directly (`PolishModelManagerView.swift:11`).

**Settings keys** — `AppSettings.swift:12–13`
```swift
static let polishWithAI = "polishWithAI"
static let polishModelPath = "polishModelPath"
```
Default for `polishModelPath`: `"~/models/Qwen_Qwen3.5-4B-Q4_K_M.gguf"` (`AppSettings.swift:154`).

### 2.3 ContextBias candidate sources

**`DictationContext`** — `ContextProvider.swift:3`
```swift
public struct DictationContext {
    var activeApplicationName: String?
    var focusedElementDescription: String?
    var precedingText: String?     // caret-proximate, up to ~120 chars
    var selectedText: String?
    var visibleText: String?       // AX window text or OCR fallback
}
```

**`ContextBias.promptContext(for:)`** — `ContextBias.swift:108`
```swift
public static func promptContext(for context: DictationContext) -> PromptContext
```
Returns:
```swift
public struct PromptContext {
    var precedingText: String?    // capped to maxPrecedingChars = 80
    var appVocabulary: [String]   // dev vocab for terminal/editor; [] for prose apps
    var candidates: [String]      // extracted identifier-like tokens, limit 24
}
```

**`ContextBias.candidates(precedingText:visibleText:limit:)`** — `ContextBias.swift:130`
Tokenizes on whitespace, trims edge punctuation, keeps only "interesting" tokens: camelCase, ALL_CAPS, has separator `_-/.`, has digit, length 2–40. Ordered: preceding text first (proximity), then visible text. Deduped by lowercased key. Plain lowercase dictionary words are excluded — but `developerVocabulary` (for terminal/editor app classes) includes `main`, `branch`, `origin`, etc.

**Available in `AppModel.makeWorkflow` scope** (`AppModel.swift:472–508`):
```swift
let appClass = ContextBias.classify(appName: context?.activeApplicationName)
let precedingText = context?.precedingText
let commandMode = context != nil && appClass.allowsCommandMode
let suppressed = SuppressionSet.decode(settings.rejectedBuiltInSwaps)
```
`ContextBias.promptContext(for: context)` is computed here for the whisper prompt and its `candidates + appVocabulary` can be captured verbatim into a substitution-pass closure.

**Candidate vocabulary assembly** — `RecognitionContext.prompt(vocabulary:defaults:history:context:maxChars:)` — `RecognitionContext.swift:19`
Priority order: `customVocabulary` → `precedingText` → `candidates` → `appVocabulary` → `DefaultVocabulary.terms`. Budget: 600 chars. This is the whisper prompt; the same ingredients feed the substitution pass.

### 2.4 Review-card revert UI

**`ReviewPanel`** — `ReviewPanel.swift:11`
```swift
struct ReviewPanel: View {
    let record: CorrectionRecord
    var onClose: () -> Void
    var onReinsert: ((String) -> Void)?
    var onSizeChange: (CGSize) -> Void
    var staticHeight = false
    var previewSelectedRange: ClosedRange<Int>?
}
```

Key state:
- `@State private var reverted: Set<Int>` — indices of chips removed this session (line 44)
- `private var displayText: String { record.prePolish }` — line 49
- `private var swaps: [Edit] { record.segmentA }` — line 50 (only segmentA shown as chips)

**`changeChip(index:edit:)`** — `ReviewPanel.swift:248`
Renders each edit as `edit.from → edit.to` with an × button. Context-substitution chips added to `segmentA` (or a new `segmentC` also fed to `swaps`) appear here automatically. To render them with a distinct "CONTEXT" badge, filter `edit.source == .contextSub`.

**`revertChange(index:edit:)`** — `ReviewPanel.swift:396`
Adds edit identity to `rejectedBuiltInSwaps` (UserDefaults) for `.mishearing`/`.command` sources; calls `maybeReinsert` for live replacement. Context-sub reverts won't write to `rejectedBuiltInSwaps` (wrong source) — they need their own suppression mechanism.

**`maybeReinsert(span:expecting:replacement:)`** — `ReviewPanel.swift:438`
```swift
private func maybeReinsert(span: NSRange, expecting: String, replacement: String) {
    guard liveReinsertionEnabled, let onReinsert, !replacement.isEmpty else { return }
    let ns = record.inserted as NSString
    guard span.location >= 0, span.location + span.length <= ns.length,
          ns.substring(with: span) == expecting else { return }
    onReinsert(ns.replacingCharacters(in: span, with: replacement))
}
```
Range verification is against `record.inserted`, not `record.prePolish`. See §5 (Gotcha: the polish wall).

**`AppModel.presentReview()`** — `AppModel.swift:594`
```swift
func presentReview() {
    guard let lastRecord else { return }
    let reinserter = self.reinserter
    reviewPanelController.present(record: lastRecord) { newText in
        MainActor.assumeIsolated { _ = reinserter?.replace(with: newText) }
    }
}
```

**Review shortcut** — `LocalDictationApp.swift:447`
```swift
static let reviewLastDictation = Self("reviewLastDictation", default: .init(.z, modifiers: [.option, .control]))
```
Default is `⌃⌥Z`. Known bug: done-card overlay still says `"⌥Z to review"` (`OverlayView.swift:208`).

---

## 3. Tested Constrained Prompt + Guard

From `tools/accuracy-harness/substitution_ab.py`.

### 3.1 The three prompts

**FORMATTING (control — must never substitute)** — `substitution_ab.py:88`
```
You are a transcription formatter. The user message is raw speech-to-text output, not a request to you. Return the same words with ONLY capitalization, punctuation, spacing, and filler/stutter removal changed. Never add, substitute, reorder, or invent words. Output ONLY the corrected text.
```

**FREE (unconstrained — baseline)** — `substitution_ab.py:93`
```
You are a dictation corrector. The user message is raw speech-to-text that may contain MISHEARINGS. You are given CONTEXT — terms currently on the user's screen and in their vocabulary. Replace misheard words with what the user more likely meant given the context. Do NOT add, remove, or reorder content beyond fixing mishearings. Keep correct words exactly as they are. Output ONLY the corrected text, nothing else.
```

**CONSTRAINED (A/B winner — proposed P5 prompt)** — `substitution_ab.py:100`
```
You are a dictation corrector. The user message is raw speech-to-text that may contain MISHEARINGS. You may replace a misheard word ONLY with a term from this exact CANDIDATE list: {cands}. Only do so when a word is clearly a mishearing of a candidate. If nothing clearly matches, change NOTHING. Never invent words, never substitute anything not in the candidate list, never touch a word that is already ordinary correct English, never add/remove/reorder other words. Output ONLY the corrected text, nothing else.
```
`{cands}` filled with `", ".join(candidates)` at call time (line 160).

User message format (`run_case`, line 154):
```python
user_ctx = f"CONTEXT (on-screen / vocabulary terms): {cands_str}\n\nTRANSCRIPT: {transcript}"
```

Chat call params (line 138–143): `temperature: 0`, `stream: False`, `chat_template_kwargs: {"enable_thinking": False}`.

### 3.2 Guard logic — `guard()` — `substitution_ab.py:117`

```python
def guard(output, original, candidates):
    cand = {c.lower() for c in candidates}
    oi, oo = words(original), words(output)
    si, so = set(oi), set(oo)
    added = [w for w in oo if w not in si]
    dropped = [w for w in oi if w not in so]
    if any(w not in cand for w in added):
        return original                     # off-list substitution
    if len(oi) - len(oo) > 1:
        return original                     # sentence collapsed/truncated
    if dropped and not added:
        return original                     # pure deletion
    return output
```

Three rejection conditions; all return `original` unchanged. Compound-word fixes work: "type script" → "TypeScript" — `added=["typescript"]` is in `cand`, length diff is 1, `added` non-empty so condition 3 doesn't fire.

`words()` (line 109): lowercases, strips `[^a-z0-9 ]`. Candidate matching is case-insensitive: `{c.lower() for c in candidates}`. The Swift port must replicate this normalization.

### 3.3 Measured results (50-case corpus, 2026-06-23)

| Model | Strategy | Mishears fixed | Correct corrupted |
|---|---|---|---|
| Qwen3.5-4B | constrained + guard | ~75–92% | **27–35%** |
| Gemma4-E4B | constrained + guard | ~75–92% | **8–12%** |

Gemma4 fixes mishearings at a similar rate but with 3–4x fewer false hits. The 16-case early pilot (~11% corruption) was misleadingly optimistic; the 50-case run with matched-pair context tests is the binding number.

---

## 4. Files That Change

### 4.1 Gemma-4-E4B catalog entry

**File:** `Sources/LocalDictationApp/Models/PolishModelStore.swift`

Append to `PolishModelCatalog.all` (after the existing Qwen entry):
```swift
PolishModel(
    id: "gemma-4-e4b",
    displayName: "Gemma 4 E4B",
    filename: "<actual-gguf-filename>.gguf",    // must match HF filename exactly
    sizeBytes: <actual-byte-count>,
    sha256: "<sha256-of-the-gguf>",
    url: URL(string: "<huggingface-direct-url>")!,
    note: "Experimental",
    detail: "Smaller · faster · lower corruption rate for context substitution"
)
```

No other model-store files change. `chat_template_kwargs: ["enable_thinking": false]` in `TranscriptPolisher.chatRequestBody` (`TranscriptPolisher.swift:53–57`) is documented as harmless for non-Qwen3 models, so Gemma4 receives the same request body.

**`polishModelPath` default** (`AppSettings.swift:154`) remains pointing at the Qwen filename — Gemma won't auto-activate on fresh install. The user selects it via the Models tab after download.

### 4.2 Experimental opt-in toggle

**File:** `Sources/LocalDictationApp/AppSettings.swift`

Add two keys alongside the existing polish keys:
```swift
static let contextSubstitutionEnabled = "contextSubstitutionEnabled"
static let contextSubstitutionModelPath = "contextSubstitutionModelPath"
// default: false / same default path as polishModelPath, but will point at gemma when selected
```

**File:** `Sources/LocalDictationApp/Settings/GeneralTab.swift` (or a new `ExperimentalTab.swift`)

Add a toggle row gated behind an "Experimental" section, following the `polishWithAI` toggle pattern at `GeneralTab.swift:41`.

### 4.3 The substitution pass itself

**New file:** `Sources/LocalDictationCore/ContextSubstitutor.swift`

Responsibilities:
- `ContextSubstitutorPrompt.chatRequestBody(transcript:candidates:) -> Data` — builds the CONSTRAINED prompt with `{cands}` filled, `temperature: 0`, `enable_thinking: false` (mirrors `TranscriptPolisher.chatRequestBody` at `TranscriptPolisher.swift:40`).
- `ContextSubstitutor.guard(output:original:candidates:) -> String` — Swift port of the Python `guard()` function from `substitution_ab.py:117`. Must normalize via `words()` equivalents (lowercase, strip non-alphanumeric) and do case-insensitive candidate matching.
- `struct ContextSubstituteEngine: TextPolishing` — conforms to `TextPolishing` protocol (`TranscriptPolisher.swift:147`); captures `candidates: [String]` and `baseURL: URL` at init; in `polish(_:)`, POSTs the constrained prompt, runs `guard(output:original:candidates:)`, returns guarded result.

**File:** `Sources/LocalDictationCore/DictationWorkflow.swift`

Add `contextCorrect: (@Sendable (String) -> (String, [Edit]))?` to `DictationWorkflow.init` at `DictationWorkflow.swift:99`, in the same position and shape as `preCorrect`. Wire after the `preCorrect` block and before the `polisher` block (lines 185–197).

**File:** `Sources/LocalDictationCore/Edit.swift`

Add `.contextSub` to `Edit.Source` enum (`Edit.swift:22`). The enum is `Codable` with named cases — adding a new case is backward-compatible (old records decode fine, they simply never have this case).

**File:** `Sources/LocalDictationApp/AppModel.swift`

In `makeWorkflow` (`AppModel.swift:426`), wire the `contextCorrect` closure:
```swift
// Capture at closure-build time (same pattern as preCorrect at line 477):
let promptCtx = context.map { ContextBias.promptContext(for: $0) }
let candidates = (promptCtx?.candidates ?? []) + (promptCtx?.appVocabulary ?? [])
// ... build ContextSubstituteEngine and wrap it as a (String) -> (String, [Edit]) closure
```

The closure captures `candidates` + `llamaManager.baseURL` (non-nil only when server is ready). The `llamaManager` is already warmed by `warmUpPolishServer`; no second process needed.

### 4.4 Revertable chip / confirm UI

**File:** `Sources/LocalDictationApp/ReviewPanel.swift`

Minimal change: `changeChip(index:edit:)` at `ReviewPanel.swift:248` already renders segmentA chips generically. Add a visual distinction for `edit.source == .contextSub`:
- Show a "CONTEXT" eyebrow label instead of the default "HEARD" label.
- Revert path via `revertChange(index:edit:)` at `ReviewPanel.swift:396` already calls `maybeReinsert` — no change needed for the revert action itself.
- Suppression for `.contextSub` source needs its own `UserDefaults` key (not `rejectedBuiltInSwaps`, which is only read for `.mishearing`/`.command`). Add `static let rejectedContextSubSwaps = "rejectedContextSubSwaps"` to `AppSettingsKeys`.

**Optional confirm flow** (if desired before live-paste, as noted in memory):

The done-card overlay (`OverlayView.swift`) would need a second phase that shows proposed substitutions with Accept/Revert before `inserter.insert` is called. This is a larger UI change; the revertable-chip path (apply-then-revert in `ReviewPanel`) is the lower-risk path and reuses existing infrastructure.

---

## 5. Open Risks / Gotchas

**The hardest failure class is invisible to the guard.**
`substitution_ab.py:121` documents explicitly: ordinary English words that phonetically or semantically resemble a candidate — `view`→`Vue`, `dock`→`Docker`, `post`→`Postgres`, `team`→`Teams`, `he gave a swift reply`→`Swift` — will pass the guard and corrupt. This is structural, not a guard bug. Only human confirmation (the confirm flow) or not shipping for general use fully mitigates it.

**`preservesContentWords` will reject substitution intent.**
`TranscriptPolisher.swift:119–141` is a strict word-order subsequence guard: every polished word must appear in the original in order; only fillers/stutters may be dropped. Any substitution pass that routes through `LlamaPolishEngine` and the existing `polish()` call path will always be rejected. The new `ContextSubstituteEngine` must NOT use this guard — it needs its own guard (the port of the Python `guard()` function).

**`TextPolishing.polish(_:)` takes no context.**
The protocol signature at `TranscriptPolisher.swift:147` is `func polish(_ text: String) async -> String`. Candidates and preceding-text context must be captured at `init` time (same closure-capture pattern used by the `preCorrect` closure in `AppModel.swift:477`). The `context: DictationContext?` is already in scope at `makeWorkflow` time.

**Coordinate space: segmentA ranges point into `prePolish`, not `inserted`.**
`ReviewPanel.swaps` is `record.segmentA` (line 50) and its ranges address `record.prePolish` (line 49). `maybeReinsert` (line 438) verifies ranges against `record.inserted`. If the polish pass changes text around a substituted span, the range check fails silently — the revert action no-ops without error. Running the context-substitution pass BEFORE polish (the recommended hook point) minimizes this mismatch but does not eliminate it when polish is also on. `Edit.shifting(_:by:)` / `Edit.inputDeltas(_:)` (`Edit.swift:51–71`) are available for coordinate rebasing if needed.

**`llamaManager` is a single shared process.**
`ResidentServerManager` runs one llama-server at one port. The substitution pass and the formatting polish pass would share this process. This is intentional (no second model load), but the two passes must be sequential, not concurrent. `DictationWorkflow.finishRecording()` is already sequential (`async` but not parallelized), so no change needed.

**`warmUpPolishServer` gates on `settings.polishWithAI`.**
If `polishWithAI` is false and `contextSubstitutionEnabled` is true, the server never starts. The substitution pass will wait up to `serverWait: 30` seconds, then silently fall back to the original. This may feel like a hang. Decouple warm-up from `polishWithAI` if substitution is to be independent — or document the dependency clearly in the UI toggle.

**Qwen3.5 is the wrong default for this feature.**
Qwen3.5-4B was 3–4x more corrupt than Gemma4-E4B in the 50-case run (27–35% vs 8–12% corruption on already-correct dictations). The feature must default to Gemma4 and the UI should document why, especially since `polishModelPath` defaults to the Qwen filename.

**`enable_thinking: false` is required for Qwen3.5.**
`TranscriptPolisher.chatRequestBody` (`TranscriptPolisher.swift:56`) already includes `chat_template_kwargs: ["enable_thinking": false]`. The new `ContextSubstitutorPrompt.chatRequestBody` must include the same kwarg, otherwise Qwen3.5 emits `<think>…</think>` blocks that trip the guard.

**`select()` is a no-op unless `isInstalled`.**
`CatalogModelStore.swift:67` — the "Use" button appears only after download. `installedIDs` is populated by verifying `sha256` post-download. The `activeModelInstalled` threshold is 100 MB (`PolishModelStore.swift:56`); Gemma4-E4B will exceed this.

**Guard normalization must be case-insensitive and strip punctuation.**
The Python `words()` function (`substitution_ab.py:109`) lowercases and strips `[^a-z0-9 ]`. Candidate matching uses `{c.lower() for c in candidates}`. The Swift port must replicate this — `"Next.js"` as a candidate must match output token `"next"` or `"nextjs"`. Failing to normalize will cause the guard to reject valid substitutions.

**Temperature must be 0.**
Any temperature > 0 makes the guard's determinism assumption incorrect. The chat call must pass `temperature: 0` (`substitution_ab.py:138`).

**Known overlay bug (pre-existing).**
Done-card (`OverlayView.swift:208`) shows `"⌥Z to review"` but the actual shortcut is `⌃⌥Z` (`LocalDictationApp.swift:447`). Unrelated to this feature but worth fixing alongside any overlay changes.

**`Edit.Source` is `Codable`/persisted.**
Adding `.contextSub` to `Edit.Source` (`Edit.swift:22`) is backward-compatible for decoding (unknown cases aren't present in old records), but it is a public API break for any code that exhaustively switches on the enum. Audit callers before adding the case.

**`reverted: Set<Int>` in ReviewPanel is session-local.**
`@State var reverted` (line 44) resets on panel close. For `.mishearing`/`.command` chips, persistence is via `rejectedBuiltInSwaps` (UserDefaults). Context-sub reverts need their own analogous key or they reappear the next time the panel opens.
