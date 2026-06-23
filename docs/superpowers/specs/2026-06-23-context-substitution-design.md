# Context Substitution — Design Spec

**Date:** 2026-06-23
**Branch:** `feat/context-substitution` (worktree `~/work/tools/local-dictation-ctxsub`, off `feat/accuracy-tuning-and-harness` @ `e75a0d0`)
**Status:** Approved design → ready for implementation plan
**Reference:** [`context-substitution-code-map.md`](../context-substitution-code-map.md) — verbatim file:line integration points

---

## 1. Goal

An **experimental, opt-in, off-by-default** pass that fixes context mishearings in dictation by swapping a misheard word for a term already present in the user's context (e.g. `versal`→`Vercel`, `cuban eats`→`Kubernetes`), **constrained** to an allow-list of candidate terms and **held in an overlay with a countdown** so the user confirms or undoes each swap before it is typed.

### Why experimental + human-confirmed

The 50-case mic-free A/B (`tools/accuracy-harness/substitution_ab.py`, 2026-06-23) measured the binding tradeoff. The constrained strategy fixes 75–92% of mishearings but corrupts already-correct dictations whose words *resemble* a candidate (`team`→`Teams`, `dock`→`docker`, `view`→`Vue`). This lookalike class is **structurally invisible to the guard** — only human confirmation mitigates it. Measured corruption (constrained + guard, 50 cases):

| Model | Size | Mishears fixed | Already-correct corrupted |
|---|---|---|---|
| **Gemma 4 E2B** (Q4_K_M) | 3.46 GB | 19/24 (79%) | **2/26 (7.7%)** |
| Gemma 4 E4B (q4_0) | 4.8 GB | 18/24 (75%) | 3/26 (11.5%) |
| Qwen 3.5 4B (Q4_K_M) | 2.8 GB | 19/24 (79%) | 7/26 (26.9%) |

**E2B is the chosen default** — it dominates E4B (smaller, safer, more fixes) and is ~3.5× safer than Qwen. (Caveat: E2B tested at Q4_K_M vs E4B at q4_0 — the quant may contribute, but E2B-Q4_K_M is the shippable file and wins on size+safety regardless.)

---

## 2. Decision log (settled with user)

| # | Decision | Choice |
|---|---|---|
| a | **Confirm-flow mechanism** | **Hold-in-overlay + auto-accept countdown.** Text is NOT typed while a swap is pending. Overlay shows the proposed final text + a countdown (default 5s). Do-nothing → auto-applies current state on timeout; `↵` Accept → applies immediately; `esc` → keep all original. |
| a′ | **Reject path** | **Per-word toggle.** Each swap is an independently toggleable chip; number keys (`1`/`2`/…) flip individual swaps; auto-apply/Accept apply whatever is currently toggled on. |
| b | **Toggle structure** | **Separate experimental toggle** (`contextSubstitutionEnabled`), independent of "Polish with AI". Runs its own constrained pass. |
| c | **Candidate source** | **Reuse existing `ContextBias` candidates** — AX visible terms + custom vocabulary + caret/preceding text. No new permissions. (OCR stays out of scope.) |
| d | **Prompt** | The **A/B-validated CONSTRAINED prompt + deterministic guard**, ported verbatim from `substitution_ab.py`. `temperature: 0`, `enable_thinking: false`. |
| e | **Model catalog** | **E2B (recommended/default) + Qwen (smallest); drop E4B.** Each with a benefit description. |
| f | **Learn loop** | **Accepted swaps persist their target term to custom vocabulary** (reuse `CustomVocabulary.appending`), so whisper biases toward it next time. Rejections do NOT learn. |

---

## 3. Architecture

### 3.1 Shared model (resolves the two-model question)

There is **one resident llama model**, selected from `PolishModelCatalog` via the existing `polishModelPath` setting. **Both** the formatting-polish pass and the new constrained-substitution pass POST to the *same* `ResidentServerManager` process with *different system prompts* (per code-map §2.1 — one process, many prompts). **No separate substitution model-path setting is added.** Enabling substitution does not load a second model; it adds a second POST against the resident model. We change the catalog's *recommendation* to E2B; the user picks the shared model in the Models tab.

### 3.2 Pipeline hook

New substitution stage in `DictationWorkflow.finishRecording()` between `preCorrect` and the polisher (code-map §1.2, `DictationWorkflow.swift:185–197`). Unlike a pure transform, the stage is **async and may suspend** for the confirm overlay:

```
preCorrect → ★ contextSubstitute (compute proposals) ★
           → [if proposals non-empty] await confirm overlay (countdown + per-word toggle)
           → apply accepted swaps → fold edits into segmentA → learn-loop accepted targets
           → polisher → postProcess → insert → done card
```

If **zero** proposals: skip the overlay entirely — insert immediately, exactly as today (the common-case no-friction path).

### 3.3 New core types (`Sources/LocalDictationCore/`)

```swift
// One proposed swap, ranges in the current (prePolish) coordinate space.
struct ProposedSwap: Equatable, Sendable {
    let range: Range<String.Index>   // span in the working text
    let original: String             // e.g. "cuban eats"
    let target: String               // candidate, e.g. "Kubernetes"
}

// What the substitution stage produces from the working text + captured candidates.
struct SubstitutionProposal: Sendable {
    let swaps: [ProposedSwap]        // empty == nothing to confirm
    let guardedText: String          // post-guard full text (== original if guard rejected all)
}

// The user's decision after the overlay resolves.
enum SubstitutionDecision: Sendable {
    case applyAll([ProposedSwap])
    case applySome([ProposedSwap])   // the subset still toggled on
    case keepOriginal
}
```

### 3.4 The constrained pass — `ContextSubstitutor`

New file `Sources/LocalDictationCore/ContextSubstitutor.swift`. Three responsibilities, all ported verbatim from `substitution_ab.py`:

1. **Prompt** (`substitution_ab.py:100`): the CONSTRAINED system prompt with `{cands}` filled by `", ".join(candidates)`; user message `CONTEXT (on-screen / vocabulary terms): {cands}\n\nTRANSCRIPT: {transcript}`. Request body mirrors `TranscriptPolisher.chatRequestBody` (`temperature: 0`, `chat_template_kwargs: {enable_thinking: false}`).
2. **Guard** (Swift port of `substitution_ab.py:117`) — the three rejection conditions: (a) any added word not in the candidate set → reject; (b) `len(original) - len(output) > 1` → reject (collapse/truncation); (c) words dropped with nothing added → reject. Normalization must replicate `words()` (lowercase, strip `[^a-z0-9 ]`); candidate matching case-insensitive. **Must NOT use `TranscriptPolisher.preservesContentWords`** (code-map §5 — that guard rejects all substitutions by design).
3. **Diff → swaps**: tokenize original vs guarded output; each contiguous changed span becomes one `ProposedSwap` with its character range. The guard guarantees added words are candidates, so spans are clean.

Candidates captured at workflow-build time from `ContextBias.promptContext(for: context).candidates + .appVocabulary` (code-map §2.3, `AppModel.swift:472–508`).

### 3.5 The confirm overlay (the new interactive piece)

Injected protocol so `DictationWorkflow` stays testable:

```swift
protocol SubstitutionConfirming: Sendable {
    /// Presents the countdown overlay; resolves on timeout (current state),
    /// Accept (current state), or esc (keepOriginal).
    func confirm(text: String, swaps: [ProposedSwap], countdown: TimeInterval) async -> SubstitutionDecision
}
```

- **Tests** inject a deterministic confirmer (auto-apply-all / auto-keep / toggle-#2-off) — no UI, no timing.
- **App** provides a real confirmer backed by `OverlayController`: a new overlay phase `reviewSubstitution(swaps:countdown:)` rendered by `OverlayView`. Drives the countdown timer, per-word toggle state, number-key + `↵` + `esc` handling, and fulfills the async continuation.

New `OverlayView` phase extends the existing emerald-glass HUD (`OverlayView.swift`): reuses the glass card (radius 26), the 3px signal accent bar, the breathing halo, the `On-device` pill, and the existing emerald swap-underline (`doneAttributed`). Adds: numbered swap chips, a swap legend/toggle list, a depleting countdown ring, and an `↵ Apply now` `SignalButtonStyle` capsule. (Mockup: easel push #1, 5 specimens.)

### 3.6 Model catalog + settings

- **`PolishModelStore.swift`** — add the **E2B** entry to `PolishModelCatalog.all` and mark it `note: "Recommended"`; demote/remove the Qwen `"Recommended"` note; **drop E4B** (never add it). E2B entry:
  - `id: "gemma-4-e2b"`, `displayName: "Gemma 4 E2B"`, `filename: "google_gemma-4-E2B-it-Q4_K_M.gguf"` — **filename must match the URL basename** (the downloader saves under it; verify against how the Qwen entry resolves, where `filename` == URL basename). The local A/B copy at `~/models/gemma-4-E2B-it-Q4_K_M.gguf` was renamed and is unrelated to what the app downloads.
  - `sizeBytes: 3_462_678_272`, `sha256: "b5310340b3a23d31655d7119d100d5df1b2d8ee17b3ca8b0a23ad7e9eb5fa705"`
  - `url: https://huggingface.co/bartowski/google_gemma-4-E2B-it-GGUF/resolve/main/google_gemma-4-E2B-it-Q4_K_M.gguf`
  - `note: "Recommended"`, `detail: "Safest · best accuracy · fewest false swaps for context substitution"`
  - Qwen entry keeps its real fields; `detail` → "Smallest download · more false corrections".
- **`AppSettings.swift`** — add keys: `contextSubstitutionEnabled` (Bool, default `false`), `contextSubstitutionCountdown` (Double, default `5.0`), `rejectedContextSubSwaps` (suppression set for `.contextSub` reverts — its own key, NOT `rejectedBuiltInSwaps`; code-map §4.4).
- **`GeneralTab.swift`** (or a new `ExperimentalTab.swift`) — an "Experimental" section: the `Context substitution` toggle (pattern of the `polishWithAI` row, `GeneralTab.swift:41`) and the countdown slider. **Model selection is NOT duplicated here** — the AI model lives in the existing Models tab (`PolishModelManagerView`, shared with Polish). The experimental section surfaces a *compact, read-only* reference of the active model + an inline Download CTA when it isn't installed (the picker shown in mockup #4 maps to this Models-tab selection, surfaced compactly — not a second editable picker).
- **`AppModel.warmUpPolishServer`** (`AppModel.swift:207`) — **decouple from `polishWithAI`**: warm the server when `polishWithAI || contextSubstitutionEnabled`, loading the shared `polishModelPath`. (Code-map §5 gotcha: otherwise substitution silently hangs `serverWait: 30` then falls back.)

### 3.7 Learn loop

On `SubstitutionDecision`, for each accepted `ProposedSwap`, append `.target` to custom vocabulary via the existing `CustomVocabulary.appending(_:to:)` helper (on this branch). This biases whisper's `--prompt` next time → fewer future mishears of that term. Rejections are not persisted to vocab.

### 3.8 `Edit.Source`

Add `.contextSub` to `Edit.Source` (`Edit.swift:22`). Codable-backward-compatible (code-map §5). Audit exhaustive switches before adding. `ReviewPanel.changeChip` (`ReviewPanel.swift:248`) renders `.contextSub` edits with a **CONTEXT** eyebrow (vs the neutral **HEARD** for `.mishearing`/`.command`); revert via the existing `revertChange`/`maybeReinsert`, persisting to `rejectedContextSubSwaps`.

---

## 4. Views (approved — easel #1)

1. **Countdown overlay** — held text with emerald-underlined numbered swaps, swap legend, countdown ring, `↵ Apply now`, `esc · keep all original`.
2. **Per-word toggle** — a swap reverted to the user's raw word (dotted/dimmed), countdown still running; only accepted swaps feed the learn loop.
3. **No-swap done card** — unchanged instant path.
4. **Settings** — experimental toggle + E2B-recommended/Qwen model picker + countdown slider.
5. **⌃⌥Z review** — emerald **CONTEXT** chips distinct from neutral **HEARD** chips.

---

## 5. Edge cases & risks

- **Lookalike corruption (structural).** `team`→`Teams`, `dock`→`docker`. Caught by the human in the overlay; this is the entire reason for the confirm flow. Not a guard bug.
- **Auto-submitting fields.** Because text is *held* until accept/timeout, a wrong swap can never be auto-*sent* before the user sees it (the key advantage of hold-before-insert over apply-then-revert).
- **Latency.** The substitution POST adds one LLM call before the overlay. The overlay's countdown subsumes model latency (text appears in the overlay as soon as the guard returns). Accept shortcut short-circuits the wait.
- **Coordinate space.** Running before polish keeps swap ranges in `prePolish` space (code-map §5). `EditFold.combine` folds substitution edits into `segmentA`; `Edit.shifting`/`inputDeltas` available if polish later shifts offsets.
- **Single resident process.** Polish + substitution passes are sequential (they already are in `finishRecording`); they share one model load.
- **Timeout default = auto-apply.** If the user looks away, a wrong swap still lands after the countdown. Accepted tradeoff (no confirm-fatigue); the overlay draws the eye. A future "timeout → keep original" preference is possible but out of scope.

---

## 6. Testing

- **Guard unit tests** (`LocalDictationCore` tests): port the `substitution_ab.py` cases — every CONSTRAINED case's guard outcome must match the Python `guard()` (off-list reject, collapse reject, pure-deletion reject, compound-fix pass like `type script`→`TypeScript`). Pure logic, no network.
- **Diff→swaps tests**: original/guarded pairs → expected `[ProposedSwap]` ranges.
- **Workflow tests**: inject a deterministic `SubstitutionConfirming` (apply-all / keep-original / toggle-subset) → assert final inserted text + `segmentA` edits + learn-loop calls. No UI/timer.
- **Confirm view-model tests**: countdown state machine — timeout applies current toggle state; number key flips one; `↵` applies now; `esc` keeps original.
- **Regression**: the existing `substitution_ab.py` harness re-runs against the shipped prompt to guard against prompt drift.

---

## 7. Out of scope (v1)

OCR candidate source; per-swap rejection-learning; "timeout → keep original" preference; merging substitution into the formatting-polish prompt; bundling models in the app.

---

## 8. Verification & branch plan

- Build on `feat/context-substitution` only. **No push/merge** of any branch unless the user asks.
- Unit/integration tests green; manual smoke on a signed build per project convention.
- Fix the pre-existing done-card hint bug (`OverlayView.swift:208` says `⌥Z`, actual `⌃⌥Z`, `LocalDictationApp.swift:447`) while touching the overlay.
