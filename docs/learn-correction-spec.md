# Learn / Correction — Design Spec

**Status:** Implemented (P1–P5) on branch `feat/learn-corrections` (off `main` @ `cc017be`, v0.3.3 shipped) — 61 Core tests pass, `swift build` + `scripts/build-app.sh` green. The interactive UI (review-panel gestures) and the experimental AX live re-insertion need manual verification on a real mic + field. **Date:** 2026-06-21 · **Scope:** full build, all surfaces; live re-insertion experimental/default-OFF.

> **v1 scope notes (deviations from the design below, decided during build):**
> - `strip`/`cleanup` removals are **not** range-tracked — they aren't revertable swaps. Segment A = the `mishearing`/`command` substitution swaps (already in the pre-polish output space), so no multi-pass strip→cleanup→preCorrect fold is needed; `EditFold.combine` folds mishearing+command. Capitalization rework was dropped accordingly.
> - Tracked correctors are **additive variants** (`applyTracked`) with the string `apply`/`clean` delegating — not signature changes to existing callers (less churn, behavior unchanged).
> - `ReviewPanelController` (floating key panel) ships for Door #1; the Learn-tab (Door #2) opens the same `ReviewPanel` as a sheet. Span selection is **two-tap** (tap a word, tap another to extend) rather than drag.
> - Insert-target **capture** lives with re-insertion in P5 (where it's used), not P4.

## Overview & Goals

Dictation mis-hears words. The app already makes deterministic corrections —
`MishearingCorrections` (`clot → Claude`), `CommandModeCorrections`
(`push to me → push to main`) — but the user can neither **review/reject** a swap
the system made nor **teach** one it missed, in a way that persists and improves
future dictations. This feature adds an on-device "learn / correction" loop:
every utterance lands in a reviewable queue with the deterministic swaps
attributed, and the user can revert a bad swap or teach a missed one. Both
produce the same shape of rule (see *Edit → Rule derivation* for the rule shape),
which feeds back into the correction pipeline.

**Goals**

- Let the user **review** the deterministic swaps the system made (and reject the
  built-in ones it doesn't want) **without interrupting every dictation**.
- Let the user **teach** a correction the system missed, persisted and applied to
  future dictations via the existing `TextReplacements` path.
- Surface this through **two doors into one review panel** — a passive after-screen
  hint and a deferred Learn tab — so review is opt-in and at-leisure.
- Keep the correction logic **pure and testable in Core**; keep panel UI, overlay,
  hotkeys, and settings in the App layer. (Layer note: this is a *bias*, not an
  absolute — `KeystrokeInserter`/`ClipboardInserter` already live in Core and
  `import AppKit`. AX *reads* live in App today; this feature adds AX *writes*
  there too. See the layer-facts callout under *Live re-insertion*.)

## Non-goals

- **No cloud / network.** On-device only; the correction log never leaves the Mac,
  is never logged, exported, or sent anywhere. (Canonical statement of the
  on-device guarantee; referenced elsewhere, not restated.)
- **No polish-edit attribution in v1.** `TranscriptPolisher` is a free LLM rewrite
  that is not cleanly attributable token-by-token. v1 highlights ONLY the
  deterministic swaps (mishearing / command / replacement). A noisy word-diff of
  pre/post-polish is explicitly OUT. Polish also sits *in the middle* of the chain
  — see *Coordinate space* for why it splits attribution into two segments.
- **No guaranteed live re-insertion in every app.** It's experimental, default-OFF
  (full treatment in its own section), and silently no-ops where AX writes aren't
  honored (Terminal, some Electron/web).
- **Free full-sentence edit is secondary, not the primary path.** The primary
  interaction is "select a span, correct it". Full-sentence edit (word-diff the
  edit to derive candidate rules) is optional/secondary and not required for v1.

## UX

### Two doors, one panel

Both doors open the **same** review panel (build once). The panel is overlay-
independent — it is its own window, reachable whether or not the HUD is up.

#### Door #1 — "Quiet hint" (the after-screen)

Augment the existing post-insertion `.done` card (`OverlayController.showDone`,
the `.done` phase, currently shown ~2.4s then auto-hides — `AppModel.swift:348`,
`OverlayView.doneBody` `OverlayView.swift:247`):

- **Underline the words that were swapped** (driven by the attributed change-set,
  below — not reverse-engineered in the view). The highlight is a **flat emerald
  underline — not rounded** (canonical visual detail; see the panel highlight too).
  This requires a real `OverlayState` change — see the wiring note in
  *Component touch-points*.
- Show a **dim review-hotkey hint** (e.g. `⌥Z`).
- Stays **PASSIVE**. No focus steal, no interruption. The card keeps its current
  `ignoresMouseEvents`/`.nonactivatingPanel` behavior.
- Pressing the hotkey **while it's up** opens the review panel for the last
  utterance. Ignoring it lets the card fade — and the dictation **still lands in
  the Learn queue** for deferred review.

#### Door #2 — "Learn tab"

A new Settings tab (`SettingsTab.learn`, icon `brain`), overlay-independent,
reviewed at leisure. Two regions:

1. **Deferred review queue** — recent dictations, each with a **change count**.
   Tapping a row expands it into the review panel. Backed by `CorrectionLogStore`.
2. **Rule management** — **structured rows only** (decided). Each accumulated user
   rule (the `TextReplacements` the feature has appended) is its own row —
   `from → to` with a `yours` tag, **edit** and **delete** affordances, and an
   **+ Add correction** row — in the *same visual language* as the built-in rows
   below it, so the whole tab reads as one list. (No raw `find => replace` textarea
   in the Learn tab; that freeform editor stays in `AdvancedTab`. Teaching from the
   review panel naturally yields a row, not a text line.) Below the user rules, the
   **built-in** `MishearingCorrections` / `CommandModeCorrections` rules are shown
   as **toggle rows** (on/off — they can't be text-edited). Toggling a built-in off
   writes it to the new **suppression set** (the rejection layer). (Note: until P3
   wires the apply-path consult, these toggles persist but have no effect on the
   next dictation — see *Scope & phasing*.)

#### Hotkey

The app already uses `KeyboardShortcuts` (`KeyboardShortcuts.onKeyDown(for:
.holdToDictate)`, `AppModel.swift:51`; the `.Name` extension lives at
`LocalDictationApp.swift:389–392`, `.holdToDictate` at line 391). Add a new named
shortcut to that same extension, after `.holdToDictate`:

```swift
static let reviewLastDictation = Self("reviewLastDictation", default: .init(.z, modifiers: [.option]))
```

(Concrete default `⌥Z`; user-rebindable via a `KeyboardShortcuts.Recorder` in the
Learn tab.) Its handler opens the review panel for the last utterance. Gate the
handler so it no-ops when the review panel is already visible (avoids double-
instantiation).

### The review panel — "diff in context"

Chosen layout = **diff in context**. It shows the inserted sentence in context
with the deterministic swaps highlighted inline, and lets the user select any span
and correct it.

- Inserted sentence rendered as **tappable / draggable word tokens**. Swapped spans
  (from the change-set) are highlighted with a **flat emerald underline (not
  rounded)** — a straight rule under the span, never a rounded/curved one; plain
  words are not highlighted.
- A small **"heard → should be"** text field remains as a fallback for phrase
  teaching (when the gesture is awkward, e.g. a multi-word phrase).
- A toggle **"Also bias recognition toward this word"** → writes the term to
  `customVocabulary` (recognition bias) in addition to the rule.
- **Optional/secondary:** free full-sentence edit, word-diffed against the original
  to derive candidate rules. Marked secondary; not required for v1.

### The select-a-span gesture

One interaction model, one code path: **select a span, correct it.**

- **Tap one word** OR **drag across adjacent words** to select a **contiguous span**.
  A single word is just a span of length 1 — no separate "word mode" vs "phrase
  mode", same code path.
- **Tapping a HIGHLIGHTED span** (a swap the system made) → an inline editor offers
  *revert to original* or *change to something else*.
- **Tapping/dragging a PLAIN span** (words it got wrong but did not flag) → type the
  fix; the span **becomes a new highlight and a new rule**.

The rule produced is identical in shape whether reverting or teaching — see
*Edit → Rule derivation* for the exact mapping.

Inline correction uses an **inline popover text editor** anchored to the span, not
a floating panel (avoids drag-vs-popover ambiguity — see Risks).

## Architecture & data flow

The deterministic correctors are **not** called inside `DictationWorkflow`. The
workflow runs `strip` and `cleanup` itself, but receives `preCorrect` and
`postProcess` as opaque `@Sendable (String) -> String` closures
(`DictationWorkflow.swift:69,74`) that are **composed in `AppModel.makeWorkflow`**
(`AppModel.swift:423–442`). So there are **two plumbing paths**, not one linear
accumulation:

- `strip` + `cleanup` edits are **workflow-local** (the functions run inside
  `finishRecording`).
- `preCorrect` (= `MishearingCorrections` then optional `CommandModeCorrections`)
  and `postProcess` (= `TextReplacements`) edits arrive **through the closures** —
  the workflow sees only `String → String` unless the closure contract changes.

The load-bearing P1 refactor is therefore to **change the closure contract** so
the closures can carry their edits out. See *Thread it through the workflow*.

```
   AppModel.makeWorkflow builds these closures (App layer):
      preCorrect:  (String) -> (String, [Edit])     // Mishearing + optional Command
      postProcess: (String) -> (String, [Edit])     // TextReplacements

   DictationWorkflow.finishRecording (Core):
 raw ─strip─► s ─cleanup─► c ─preCorrect─► p ─polish─► (corrected = SNAPSHOT) ─postProcess─► insertText
   │          │            │               │           (opaque,                  │
   │          stripEdits   cleanEdits       preEdits    no edits)                 postEdits
   │          └─ workflow-local ─┘          └──── arrive via closures ────────────┘
   │
   └── raw transcript preserved (local today, line 144) ──┐
                                                          ▼
        SEGMENT A (raw → corrected): strip ∪ cleanup ∪ preEdits, internally foldable
        SEGMENT B (corrected → final): postEdits, internally foldable
        polish is the OPAQUE boundary between A and B — not crossable (see Coordinate space)

   Workflow exposes:
      lastTranscriptAndEdits: (raw, corrected, final, segmentA: [Edit], segmentB: [Edit])?

   App layer:
   AppModel.finishCurrent (AppModel.swift:315–351)
     ├──► CorrectionLogStore.append(CorrectionRecord{raw, corrected, final, segmentA, segmentB})
     ├──► OverlayController.showDone(text:, swappedRanges:)            [Door #1]
     └──► (hotkey) ReviewPanelController.present(record)              [both doors]
                                       │
       Learn tab row ─────────────────┘
                                       │
               ReviewPanel (SwiftUI: span gesture) ──► RuleDerivation (Core)
                                       │
       ┌───────────────────────────────┼───────────────────────────────┐
       ▼                                ▼                                ▼
 TextReplacements (append)     SuppressionSet (insert)         customVocabulary (append)
 user find-replace rule        reject a built-in swap          "also bias" → RecognitionContext
       │                                │
       └──── both consulted by the apply path on the NEXT dictation ────┘
                                       │
                        (optional, experimental) LiveReinsertion
                        AX select-verify-replace fixes THIS instance
```

**Why `final ≠ corrected` for text-replacement users.** `correctedTranscript` is
snapshotted at `DictationWorkflow.swift:173`, **before** `postProcess` runs
(`:176–178`). So a user with text-replacements enabled has expansions in the
inserted (`final`) text that are NOT in `corrected`. The record therefore holds
**both**: `corrected` (segment-A coordinate space, what the overlay/panel highlight
against for mishearing/command swaps) and `final` (what was actually inserted, the
target for any live re-insertion and the space `.replacement` edits live in). The
review panel renders whichever string the displayed segment belongs to; it never
tries to map a `.replacement` span back through `corrected`.

The apply path on the **next** dictation consults two new inputs before applying a
built-in swap: the **suppression set** (skip rejected built-ins) and the user
**`TextReplacements`** (already applied post-polish; teach just appends to it).

## Data model & stores

Three existing stores + one new set + a log.

| Store | Location | Layer | Written by |
|---|---|---|---|
| **`TextReplacements`** (user find-replace) | `Sources/LocalDictationCore/TextReplacements.swift`; string in `AppSettings` (`textReplacements`) | Core / settings | **TEACH** appends a rule. Applied AFTER polish, just before insertion. |
| **`customVocabulary`** (recognition bias) | `AppSettings` (`customVocabulary`), fed to `RecognitionContext` | settings | **"Also bias"** appends the term. |
| **Suppression set** (NEW) | `String` (JSON-encoded `[String]`) in `UserDefaults` under `rejectedBuiltInSwaps` | settings → consulted in Core apply path | **REJECT** of a built-in `MishearingCorrections`/`CommandModeCorrections` rule. |
| **Correction log / review queue** (NEW) | `CorrectionLogStore` (new file, App layer); record model in Core | App + Core | every dictation: `{raw, corrected, final, segmentA, segmentB}`. Feeds Door #2's queue. |

### Suppression set

A persisted set of built-in rule identities the user has rejected. The apply path
checks it **before** applying a built-in. This is how you reject a hardcoded swap.

Serialization is **decided** (no longer open): a JSON-encoded `[String]` stored as
a `String` under `AppSettingsKeys.rejectedBuiltInSwaps` (UserDefaults can't store
`Set<String>` directly; JSON is future-proof and mirrors the `textReplacements`
string pattern). In-memory it's a `Set<String>`; `SuppressionSet` encodes/decodes.

Built-in rules need a **stable identity string** so the set is durable across
restarts and rule-text changes. There is no identity field today, so add one:

- `MishearingCorrections.rules` and `CommandModeCorrections.branchRules` each get a
  parallel identity (e.g. extend `TextReplacements.Rule` with an optional
  `id: String?`, or keep a parallel `[(rule, id)]` map in each enum). Identities
  like `"mishearing:cloud-code"`, `"command:me→main"`.
- **`clot` is NOT in `MishearingCorrections.rules`** — it's a separate `correctClot`
  regex pass (`MishearingCorrections.swift:37–48`). Give it its own standalone
  identity `"mishearing:clot→Claude"` defined alongside `correctClot`, not derived
  from a `Rule`.

### Correction log / review queue

Mirror the proven `TranscriptHistoryStore` pattern
(`Sources/LocalDictationApp/TranscriptHistoryStore.swift`: enum, static
`load()`/`append(_:)`/`clear()`, `UserDefaults` key, `JSONEncode`/`Decode`, max-
200-entries overflow). New `CorrectionLogStore` enum, same shape.

Record model lives in **Core** (pure, Codable, testable) — extend
`Sources/LocalDictationCore/TranscriptHistory.swift` alongside `TranscriptRecord`:

```swift
struct CorrectionRecord: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let raw: String           // the raw whisper transcript (NEW — not persisted today)
    let corrected: String     // snapshot before postProcess (today's `correctedTranscript`)
    let final: String         // what was actually inserted (corrected + postProcess)
    let segmentA: [Edit]       // strip ∪ cleanup ∪ preCorrect, in raw→corrected space
    let segmentB: [Edit]       // postProcess (.replacement), in corrected→final space
}
```

`(segmentA.count + segmentB.count)` is the **change count** shown on each Learn-
queue row. Enforce a max-entries ceiling (like
`TranscriptHistory.defaultMaxEntries = 200`) to bound growth. This log stores
`raw + corrected + final` text (no audio) — a more sensitive audit trail than
`TranscriptHistory`; the Learn tab MUST expose **clear** (and ideally per-row
delete), and nothing here is exported.

### Settings keys (new)

Add two keys following the `textReplacements` / `customVocabulary` pattern. Line
numbers are **approximate** — match the existing pattern, not the exact line:

- Enum `AppSettingsKeys` (~`AppSettings.swift:23`, after `saveHistory`): add
  `rejectedBuiltInSwaps` and `liveReinsertionEnabled` constants.
- Struct `AppSettingsSnapshot` (~`:31–46`): add the two fields (after
  `textReplacements`).
- `AppSettingsSnapshot.current` reader (~`:73–78`): read both.
- `Defaults` enum (~`:130–158`): `rejectedBuiltInSwaps = ""`,
  `liveReinsertionEnabled = false`.
- `registerDefaults()` (~`:86–102`): register both.

Keys:

- `rejectedBuiltInSwaps: String` (default `""`) — the suppression set, JSON-encoded.
- `liveReinsertionEnabled: Bool` (default `false`) — experimental gate (below).
- (`correctionLogData` lives under `CorrectionLogStore`'s own UserDefaults key,
  not a snapshot field — same as `TranscriptHistoryStore`.)

## The change-set enabler ("attributable change-set")

This is the foundational, pure, testable Core refactor everything else hangs on.

### The Edit model

```swift
/// One deterministic substitution made by a correction pass.
/// `range` is in the coordinate space of that pass's INPUT string, in UTF-16
/// code units (NSRange / CFRange are UTF-16, NOT bytes).
struct Edit: Codable, Sendable, Equatable {
    let range: NSRange       // UTF-16 code units in the pass's input string
    let from: String
    let to: String
    let source: Source       // enum for forward-compat (assoc. values OK later)
    enum Source: String, Codable, Sendable {
        case strip, cleanup, mishearing, command, replacement
    }
}
typealias EditSet = [Edit]   // ordered by appearance
```

`Source` is an **enum** (not a raw string) so adding cases later isn't a breaking
change to the persisted `CorrectionRecord`. **Polish is intentionally absent** —
the LLM pass produces no `Edit`s (see Non-goals; if needed later, a single opaque
`source: .polish` marker, never a fabricated token diff).

### Signature decision (do this first)

All five instrumented functions return **unnamed** tuples `(String, [Edit])` —
Swift-stdlib-consistent (`String.split`, `Result` siblings use positional tuples),
and the persisted model already names the parts. The ASCII diagram's named labels
(`stripEdits`, etc.) are *narrative*, not the signature. ~15–20 call sites change;
pin the syntax here so they're updated uniformly:

```swift
func apply(...) -> (String, [Edit])     // not (result: String, edits: [Edit])
```

### Instrument the deterministic functions

Each deterministic correction function, today returning `String`, also returns its
`[Edit]`. All live in Core, all pure, all unit-testable:

| Function | File | Today | New return | Source |
|---|---|---|---|---|
| `TextReplacements.apply` | `TextReplacements.swift:42–58` | `String` | `(String, [Edit])` | `.replacement` |
| `MishearingCorrections.apply(to:)` | `MishearingCorrections.swift:30–32` | `String` | `(String, [Edit])` | `.mishearing` |
| `CommandModeCorrections.apply(to:appClass:precedingText:)` | `CommandModeCorrections.swift:48–59` | `String` | `(String, [Edit])` | `.command` |
| `TranscriptCleaner.clean` | `TranscriptCleaner.swift:22–32` | `String` | `(String, [Edit])` | `.cleanup` |
| `WhisperTranscriptParser.strippedForInsertion` | `TranscriptionEngine.swift:122–133` | `String` | `(String, [Edit])` | `.strip` |

`TextReplacements.apply` is the shared engine — instrument it once and the regex-
match ranges propagate to every caller. The implementation extracts
`NSRegularExpression` match ranges **before** each replacement and applies
replacements in **reverse-range order** (highest index first) to avoid downstream
range drift, or tracks a cumulative offset.

**`MishearingCorrections.apply` has TWO edit sources — instrumenting
`TextReplacements` alone misses one:**

1. `TextReplacements.apply(rules, to:)` — `.mishearing` edits from `rules`
   (`cloud code`, `claud`, `clawd`). Covered by the shared engine.
2. `correctClot(in:)` (`MishearingCorrections.swift:37–48`) — a **separate**
   `NSRegularExpression` with a negative lookbehind, NOT routed through
   `TextReplacements`. It needs **its own range tracking**: capture the match
   range before `stringByReplacingMatches`, emit one `.mishearing` edit with the
   `clot→Claude` identity. The compose order is `TextReplacements` first, then
   `correctClot` on its result — so `correctClot`'s ranges are in the
   post-`TextReplacements` space; record them in that space and fold within the
   function (see *Coordinate space*).

**`CommandModeCorrections.apply` keeps its real signature
`apply(to:appClass:precedingText:)`** and:

- Emits **empty** edits outside command context (the early `return transcript`
  when `isCommandContext` is false, `:54`).
- In context, emits `.command` edits from `TextReplacements.apply(branchRules, …)`
  (`me→main`, etc.) PLUS edits from `commandFormatting(_:)` (`:65–74`): the
  trailing-period strip and `Git → git`. These mutate text the user never spoke,
  so their `from`/`to` may not map to a heard word — model them as edits whose
  `range` is in the `commandFormatting` input space with `from` = the removed/
  changed text and `to` = its replacement (possibly empty for the period strip).

### Thread it through the workflow

This is P1's real work, not a gloss. The correctors are composed in
`AppModel.makeWorkflow` (`AppModel.swift:423–442`), so the **closure contract must
change** before any `EditSet` can be threaded.

1. **Change the closure types** on `DictationWorkflow` (`:69,74`) and its `init`
   (`:81,83`) from `(@Sendable (String) -> String)?` to
   `(@Sendable (String) -> (String, [Edit]))?` (or a tiny `CorrectionPass`
   protocol with `func run(_:) -> (String, [Edit])`).
2. **Build the edit-emitting closures in `AppModel.makeWorkflow`**: the
   `preCorrect` closure composes `MishearingCorrections.apply` then optional
   `CommandModeCorrections.apply`, concatenating both functions' `[Edit]` (mapping
   the command edits into the post-mishearing space); the `postProcess` closure
   wraps `TextReplacements.apply` and returns its `[Edit]`.
3. **In `finishRecording`** (`DictationWorkflow.swift:124–192`): the workflow runs
   `strip` (`:150`) and `cleanup` (`:152`) itself → collect `stripEdits` and
   `cleanEdits` directly (workflow-local). Call the new closures and collect their
   returned `(String, [Edit])`. Snapshot `corrected` at `:173` (unchanged). Polish
   (`:165–167`) emits nothing. Assemble:
   - `segmentA = stripEdits ∪ cleanEdits ∪ preEdits` (raw → corrected space)
   - `segmentB = postEdits` (corrected → final space)
4. **Preserve the raw transcript** (`:144`, today local and discarded).
5. **Expose a new lock-protected public property** alongside `lastTranscript`:
   ```swift
   var lastTranscriptAndEdits:
     (raw: String, corrected: String, final: String, segmentA: [Edit], segmentB: [Edit])?
   ```
   Lock access exactly like `lastTranscript` — `DictationWorkflow` is
   `@unchecked Sendable` with a lock-protected `_state`/`_lastTranscript`
   (`:40–60`). Add a `_lastTranscriptAndEdits` ivar + setter on the same lock.

`AppModel.finishCurrent` (`AppModel.swift:315–351`) reads `lastTranscriptAndEdits`
(replacing the bare `workflow.lastTranscript` read at `:338`), calls
`CorrectionLogStore.append`, passes the swapped spans to `showDone` (`:348`), and
arms the `.reviewLastDictation` hotkey.

### Coordinate space — TWO segments, polish is an opaque wall

A single `original → final` fold across the whole chain is **mathematically
impossible**: polish is an opaque LLM rewrite sitting *between* the pre-polish edits
(strip/cleanup/preCorrect) and the post-polish edits (`TextReplacements`). A
post-polish edit's range cannot be mapped back through the polish rewrite to the
raw transcript. So attribution is **two disjoint coordinate islands**:

- **Segment A — raw → corrected** (pre-polish): fold `strip → cleanup →
  preCorrect` into one `raw → corrected` map. Each step emits edits in *its input
  space*; fold by replaying in order, adjusting downstream ranges by the cumulative
  length delta of earlier edits (apply in reverse-range order within a step to
  avoid intra-step drift). This map lets the panel highlight a `corrected`-string
  span back to the raw heard text.
- **Segment B — corrected → final** (post-polish): fold `postProcess`
  (`TextReplacements`) into one `corrected → final` map.
- **Polish is the wall.** The review panel renders polish as "rewritten, not
  attributable" and never promises a cross-polish map. It highlights spans only
  *within* whichever segment the displayed string belongs to.

**Worked example (Segment A).** Raw = `"um clot is here."`

| Step | Input | Edit emitted (input-space NSRange) | Output |
|---|---|---|---|
| strip | `"um clot is here."` | `{loc 0, len 3}` `"um "→""` (`.strip`) | `"clot is here."` |
| mishearing (`correctClot`) | `"clot is here."` | `{loc 0, len 4}` `"clot"→"Claude"` (`.mishearing`) | `"Claude is here."` |
| cleanup (capitalization) | `"Claude is here."` | (none — already capitalized) | `"Claude is here."` |

Fold to `raw → corrected`: the strip removed 3 UTF-16 units at offset 0, so the
mishearing edit (offset 0 in the *stripped* string) maps to offset 3 in `raw`.
Final map: `raw[3..7] "clot"` → `corrected[0..6] "Claude"`. Length delta from the
swap is `+2` (4→6 units), recorded for any later fold within the segment. A
selected `corrected` span `"Claude"` resolves back to raw `"clot"` for the
revert/teach rule.

**UTF-16 / surrogate handling.** All ranges are UTF-16 code units (`NSRange`/
`CFRange`), never bytes. An astral-plane character (emoji, e.g. `"😀"`) is **two**
code units; range arithmetic must count code units, not `Character`s. Convert to/
from `String.Index` via `Range(nsRange, in: string)` so a surrogate pair is never
split. Test case: a swap immediately after an emoji must keep the emoji's two units
intact in the folded map.

**Capitalization needs a rework.** `TranscriptCleaner.fixingCapitalization`
(`TranscriptCleaner.swift:60`) mutates a char array in place with no range tracking.
Rework it into a span-accumulating variant that emits one `.cleanup` `Edit` per
consecutive run of changed characters (so a sentence-start lowercase→uppercase is
one edit, not N). This is the highest-friction part of the Core refactor; cover it
with the tests enumerated below.

### Edit → Rule derivation (Core)

A pure helper turns a panel gesture into a rule. **Both paths yield the identical
`(heard-text → corrected-text)` rule shape** — this is the canonical statement of
the rule shape. Given a selected span and whether it's a highlight (revert) or
plain (teach):

- **Revert highlight:** rule `(edit.to → edit.from)` + if
  `edit.source ∈ {mishearing, command}`, a suppression-set insert keyed by the
  built-in rule's identity (resolved from the edit's `from`/`to` + source via the
  identity map added above).
- **Teach plain span:** rule `(selectedOriginalText → typedFix)` appended to
  `TextReplacements`.

The derivation is pure and testable; the App layer just persists what it returns.

## Live re-insertion (experimental) — AX select-verify-replace

**The experimental, opt-in, default-OFF gate (`liveReinsertionEnabled`, default
`false`) is defined here** (referenced, not restated, elsewhere). Fixes the
**current** instance (the text already typed into the user's doc) at the moment the
review panel applies a correction. Learn-for-next-time needs **zero** re-insertion
— this is purely the in-the-moment bonus.

### Layer facts (the "Core has no AppKit" rule is not absolute)

The HID insertion this section depends on is in **Core**:
`KeystrokeInserter.swift` and `ClipboardInserter.swift` live in
`Sources/LocalDictationCore/` and both `import AppKit` (line 1). `postUnicode`
posts CGEvents via `.cghidEventTap` (`KeystrokeInserter.swift:59`). AX *reads*
(`CaretContext`, `AXSupport`) live in App. This feature adds AX *writes* in App.

Because the **insert site is in Core** but the **AX capture/guard is in App**, the
captured `AXUIElement` must cross the boundary. Concrete plan: an **App-layer
inserter wrapper** around the Core inserter — mirroring the existing
`CaretAwareInserter` (`AppModel.swift:654`, which wraps a Core `TextInserting`).
The wrapper captures the focused `AXUIElement` + the inserted string + its range
at insert time, hands them to the App-layer `SelectVerifyReplace`/footgun guard,
then delegates the actual keystroke posting to the wrapped Core inserter. The
captured element never has to live in Core.

### Approach — "select-verify-replace", NOT blind backspace

By the time the panel shows, the corrected text is already in the user's document.
We replace it atomically via AX, never by synthesizing backspaces/keystrokes:

1. **At insert time** — the App-layer wrapper captures the focused `AXUIElement` +
   the inserted string + its range. (This same element-capture is the **focus-
   target pin** — see the parked footgun below; unify them.)
2. **At re-insert time:**
   - `SET kAXSelectedTextRange` to the inserted text's range (selects it).
   - `READ BACK kAXSelectedText`, compare to what we inserted.
   - **Mismatch** (caret moved, user typed, view reflowed) → **ABORT, touch
     nothing**, fall back to learn-only.
   - **Match** → `SET kAXSelectedText = corrected string` (atomic replace, no
     synthesized keystrokes, no frontmost-app dependency).

### What exists vs what's new

The app already does the **READ** half: `CaretContext.focusedTextElement`
(`CaretContext.swift:106–123`: `kAXFocusedUIElementAttribute`, reads
`kAXSelectedTextRange` + `kAXValue` + parameterized substring via
`kAXStringForRangeParameterizedAttribute`, with secure-field gating). **It is
`private static` and returns only `(element: AXUIElement, caret: Int)` for internal
use** — so it is NOT a free reuse. Promote it from `private`, and either return the
`AXUIElement` to callers or add a sibling accessor that does. That is a real edit to
`CaretContext`, not a no-cost call.

`AXSupport.swift` today has **reads only** (`string`, `children`, `isSecure`,
`:12–37`). `isSecure` (`:33`) gates reads by *aborting* on a secure field. We add
the **symmetric writes**, with the **identical secure-field guard that aborts the
write** (a secure field is never written, exactly as it is never read):

- `AXSupport.setValue(element, attribute, value)` → wraps
  `AXUIElementSetAttributeValue`, returns `AXError`. **Guards on `isSecure`: if the
  element is secure, abort without writing** (no `setValue`, return a `.failure`
  / no-op result).
- `AXSupport.readTextInRange(element, start, length)` → wraps the parameterized
  read; `String?`, best-effort, same `isSecure` abort.
- A `SelectVerifyReplace` helper (App layer) holding the captured
  `(element, insertedText, range)`, running the select → read-back → compare →
  replace sequence, returning a result enum (`replaced`, `aborted(reason)`).

Match must be **UTF-16-unit exact** (NOT "byte-exact" — `CFRange`/`kAXSelectedText`
are UTF-16 code units) + a secondary check that the caret advanced by exactly
`insertedText`'s UTF-16 length, not a substring match (the inserted text may recur
in the field). Reuse the surrogate handling already in Core
`KeystrokeInserter.ChunkSplitter` (`KeystrokeInserter.swift:28–48`, verified: it
arrays `text.utf16` and never splits a high/low surrogate pair across a chunk
boundary). Surrogate example: inserting `"a😀b"` is 4 UTF-16 units (a=1, 😀=2,
b=1); the caret-advance check must expect 4, and a range that lands between the
surrogate halves must be rejected as a mismatch.

### Fallback

Where AX writes are unsupported — **Terminal** is AX-poor, some **Electron/web**
fields reject writes silently — the read-back catches it → **abort → learn-only**.
Robust where AX works, silent no-op where it doesn't. Wrap the verify in a timeout
so a hung AX call can't stall the main thread.

### Parked-but-related footgun (capture in P4; guard is an explicit follow-up)

Insertion posts CGEvents at HID level (`KeystrokeInserter.postUnicode`, tap
`.cghidEventTap`, `Sources/LocalDictationCore/KeystrokeInserter.swift:48–61`) so
text lands wherever focus is at PASTE time — **switching apps mid-transcribe sends
text to the wrong window.** The element-capture-at-insert above is the **same
mechanism** that pins the target. **Scope is now decided** (no longer an open
question):

- **P4 ships the capture** (the App-layer wrapper grabs the target element at
  insert time — needed for re-insertion anyway).
- **Using that captured element to *guard/redirect* the primary insertion
  (refuse/relocate if focus moved) is an explicit follow-up, OUT of v1.** P4 is
  independently shippable with capture-only; the guard does not gate this feature.

## Component / file touch-points

### Core (pure logic — instrument + new model/derivation)

| File | Change |
|---|---|
| `Sources/LocalDictationCore/TextReplacements.swift` | `apply` → `(String, [Edit])`; extract regex match ranges before replacing. Shared engine — instrument once. Add optional `id` to `Rule` (or a parallel identity map) for built-in suppression identities. |
| `Sources/LocalDictationCore/MishearingCorrections.swift` | `apply(to:)` → `(String, [Edit])`; thread `TextReplacements` edits AND a separate `correctClot` edit with its own range tracking. Add stable built-in identities; give `clot` its own standalone identity (`"mishearing:clot→Claude"`). |
| `Sources/LocalDictationCore/CommandModeCorrections.swift` | `apply(to:appClass:precedingText:)` → `(String, [Edit])` (keep the real signature); emit `branchRules` edits + `commandFormatting` mutations (period strip, `Git→git`) as edits; built-in identities; empty edits when not in command context. |
| `Sources/LocalDictationCore/TranscriptCleaner.swift` | `clean` → `(String, [Edit])` (`.cleanup`); rework `fixingCapitalization` (`:60`) into a span-accumulating variant emitting one edit per changed run. |
| `Sources/LocalDictationCore/TranscriptionEngine.swift` | `WhisperTranscriptParser.strippedForInsertion` → `(String, [Edit])` (`.strip`). |
| `Sources/LocalDictationCore/DictationWorkflow.swift` | Change `preCorrect`/`postProcess` closure types (`:69,74,81,83`) to `(String) -> (String, [Edit])`; thread strip/cleanup edits workflow-local; collect closure edits; preserve raw; expose lock-protected `lastTranscriptAndEdits` (segmentA/segmentB). |
| `Sources/LocalDictationCore/TranscriptHistory.swift` | Add `CorrectionRecord` (Codable/Sendable/Identifiable) alongside `TranscriptRecord`. |
| **NEW** `Sources/LocalDictationCore/Edit.swift` | `Edit` struct + `Edit.Source` enum + `EditSet` typealias. |
| **NEW** `Sources/LocalDictationCore/RuleDerivation.swift` | pure span-tap → rule (revert/teach) + suppression-set membership/identity helpers. |
| **NEW** `Sources/LocalDictationCore/SuppressionSet.swift` | JSON encode/decode the rejected-built-in set (`Set<String>` ↔ `String`); `isSuppressed(ruleIdentity:)` consulted by the apply path. |

### App (AX, overlay, panel, settings, hotkey)

| File | Change |
|---|---|
| `Sources/LocalDictationApp/AppModel.swift` | In `makeWorkflow` (`:423–442`): compose edit-emitting `preCorrect`/`postProcess` closures, aggregate edits. In `finishCurrent` (`:315–351`): read `lastTranscriptAndEdits` (replacing `:338`), append to `CorrectionLogStore`, pass swapped ranges to `showDone` (`:348`), arm `.reviewLastDictation`. Add the App-layer insert wrapper that captures the target element (footgun hook), mirroring `CaretAwareInserter` (`:654`). Add `.reviewLastDictation` `onKeyDown` handler near `:51`. |
| `Sources/LocalDictationApp/OverlayController.swift` | **Add to `OverlayState`** (`:16–24`) `var swappedRanges: [NSRange] = []` (or `var doneAttributed: AttributedString?`). Change `showDone(text:)` (`:71`) → `showDone(text:swappedRanges:)` and `present(…)` (`:106`) to thread it onto `state`. Card stays passive (no focus/mouse change). |
| `Sources/LocalDictationApp/OverlayView.swift` | `doneBody` (`:247`): underline swapped words from `state.swappedRanges` with a **flat (non-rounded) emerald underline** + dim "⌥Z to review" hint, rendered via `AttributedString` from the threaded ranges (not reverse-engineered). |
| `Sources/LocalDictationApp/CaretContext.swift` | Promote `focusedTextElement` (`:106`) from `private static`; surface the `AXUIElement` to callers (today returns only `(element, caret)` for internal use). |
| `Sources/LocalDictationApp/AXSupport.swift` | Add `setValue` (write wrapper) + `readTextInRange`; both **abort on `isSecure`** (same guard as reads, `:33`). |
| `Sources/LocalDictationApp/SettingsView.swift` | **Add `.learn` to the `private enum SettingsTab`** (`:3–5`) FIRST; then `@AppStorage` for `rejectedBuiltInSwaps` + `liveReinsertionEnabled`; wire `LearnTab` into the `TabView` after the Advanced tab (`:71`) with `.tag(SettingsTab.learn)`. |
| `Sources/LocalDictationApp/LocalDictationApp.swift` | Add `KeyboardShortcuts.Name.reviewLastDictation` to the existing extension (`:389–392`), after `.holdToDictate` (`:391`), default `.init(.z, modifiers: [.option])`. |
| **NEW** `Sources/LocalDictationApp/CorrectionLogStore.swift` | enum mirroring `TranscriptHistoryStore`: `load`/`append`/`clear`, UDefaults key, JSON, max-200. |
| **NEW** `Sources/LocalDictationApp/ReviewPanelController.swift` | own `NSPanel` **subclass** overriding `canBecomeKey`/`canBecomeMain` to return `true` (a borderless/titled panel is non-key by default — a style-mask flag can't do it). `styleMask: [.titled, .fullSizeContentView]` (or `[.borderless, .fullSizeContentView]`), and **NOT** `.nonactivatingPanel` (omitting it is what lets the panel activate — there is no `.activatingPanel` flag). `ignoresMouseEvents = false`, `isMovableByWindowBackground = false`. Programmatic key + responder management (`makeFirstResponder`) + restore prior-app focus on dismiss. Distinct window from the passive HUD (`OverlayController.swift:148` uses `.nonactivatingPanel`). |
| **NEW** `Sources/LocalDictationApp/ReviewPanel.swift` | SwiftUI content: tappable/draggable word tokens, span selection, inline popover editor, "heard → should be" fallback field, "Also bias" toggle. |
| **NEW** `Sources/LocalDictationApp/Settings/LearnTab.swift` | the deferred queue (`CorrectionLogStore.load()`, change count, expand → panel) + rule management as **structured rows only**: user rules from `TextReplacements` as `from → to` rows with edit/delete + an "Add correction" row; built-ins as toggle rows → suppression set; `clear` control. **No raw-text editor here** (it stays in `AdvancedTab`). Follows `Sources/LocalDictationApp/Settings/AdvancedTab.swift` patterns. |
| **NEW** `Sources/LocalDictationApp/SelectVerifyReplace.swift` | experimental live re-insertion: captured `(element, insertedText, range)` → select → read-back verify → atomic replace or abort. **Extract the compare/abort decision as a pure function** (input: captured range + read-back string + caret delta; output: `.match` / `.mismatch(reason)`) so it's unit-testable. Gated on `liveReinsertionEnabled`. |

## Testing strategy

Core is pure and testable via `LocalDictationCoreTestRunner` (currently 51 tests).
Mandated Core unit tests:

- **Edit-set emission (per function).** Each instrumented function returns the
  right ranges: `TextReplacements` (`.replacement` spans); `MishearingCorrections`
  — **both** the `rules` path (`cloud code → Claude Code` span) AND the separate
  `correctClot` path (`clot → Claude` span, and `blood clot` left untouched);
  `CommandModeCorrections` (`me → main` span + the `commandFormatting` period-strip
  and `Git→git` edits, and **empty edits outside command context**); `strip`;
  `cleanup` (esp. the reworked capitalization span accumulation — one edit per run).
- **RuleDerivation logic.** Revert a highlight yields `(edit.to → edit.from)` + a
  suppression entry for built-in sources, with the correct identity (incl. the
  standalone `clot` identity); teach a plain span yields
  `(originalText → typedFix)`; both identical in `(heard → corrected)` shape;
  derivation is pure (no side effects).
- **Edit threading / multipass fold (the load-bearing arithmetic).** Enumerated
  cases:
  - strip removes a leading token → assert the mishearing edit (offset 0 in the
    stripped string) folds to the right raw offset (the worked example above).
  - strip removes leading token THEN mishearing fires mid-string THEN
    capitalization changes char 0 — assert the final `raw → corrected` (Segment A)
    map.
  - two replacements on one line fold without off-by-one drift (reverse-range
    order verified).
  - UTF-16 surrogate: a swap immediately after an astral-plane emoji keeps both
    code units intact in the folded map; a range landing between surrogate halves
    is rejected.
  - **Segment boundary:** assert post-polish `.replacement` edits live in
    Segment B (corrected→final) and are NOT folded across the polish boundary into
    Segment A.
- **`SelectVerifyReplace` decision (pure).** Feed the extracted compare/abort
  function a captured range + read-back: assert `.match` on UTF-16-exact +
  correct caret delta; `.mismatch` on differing text, on a length/caret-delta
  mismatch, and on a substring-but-not-exact read-back. (Only the actual AX I/O is
  left to manual.)
- **`CorrectionLogStore` round-trip.** `CorrectionRecord` encode/decode (incl.
  `segmentA`/`segmentB`), **200-entry overflow** (the 201st append drops the
  oldest), and `clear` empties the store.
- **`SuppressionSet` encode/decode + filtering.** `Set<String>` ↔ JSON `String`
  round-trips; a built-in identity in the set is NOT applied on the next dictation;
  removing it re-enables.

App-layer AX *I/O* (`AXSupport.setValue`/`readTextInRange`, the actual select-
verify-replace round-trip), the overlay augmentation, and the interactive panel
(focus, drag-select, popover) are **largely manual / best-effort** — verify by hand
against well-behaved fields (Notes, TextEdit, Mail, Safari textareas) and confirm
graceful no-op in Terminal / an Electron app. The *decision logic* inside those
(the compare/abort branch) is unit-tested above, not routed to manual.
`scripts/build-app.sh` must stay green.

## Risks & open questions

- **Capitalization range tracking** (`TranscriptCleaner.fixingCapitalization:60`)
  mutates a char array in place — needs a span-accumulating rework. Highest-friction
  part of the Core refactor.
- **Two-segment fold + polish wall** — a single `raw → final` map is impossible
  (polish is opaque, mid-chain). Fold within Segment A and Segment B only; off-by-
  one and UTF-16 surrogate bugs are the main hazard; guard with the enumerated
  tests above.
- **Closure-contract change is load-bearing** — `preCorrect`/`postProcess` are
  opaque `String → String` closures composed in `AppModel`, not called inside the
  workflow. P1 must change the contract to `(String) -> (String, [Edit])` before any
  threading works; this is the hardest single change in the build.
- **`final ≠ corrected`** for text-replacement users — the record persists both;
  the panel highlights against the string each segment owns.
- **Focus-steal on the review panel** — an activating, `canBecomeKey` panel WILL
  pull focus from the user's document when it opens. Acceptable (deliberate review
  moment), but: (a) NEVER auto-open on `.done` — only via the explicit hotkey;
  (b) restore prior-app focus on dismiss (`NSWorkspace.frontmostApplication`
  snapshot). SwiftUI `FocusState` alone doesn't drive the AppKit responder chain —
  needs explicit `makeFirstResponder`.
- **Drag-vs-select / drag-vs-popover** — `isMovableByWindowBackground = false` on
  the review panel; inline popover dismisses on drag start (don't float it).
- **Built-in rule identity stability** — the suppression set keys on built-in rule
  identities; if a built-in rule's text changes in a future release, its suppression
  entry silently stops matching. Use explicit, versioned identity strings.
- **AX write support varies** — even apps that expose the attribute for reading may
  reject writes with a success code but no change; the UTF-16-exact read-back catches
  it → abort. Terminal/Electron/web/remote-desktop silently no-op.
- **Correction-log sensitivity** — stores `raw + corrected + final` text (no audio);
  expose clear + per-row delete; never export. Bound to 200 entries.

**Open questions** — none outstanding. All previously-listed questions are resolved
above: suppression-set serialization = JSON; footgun = capture in P4, guard is an
explicit follow-up; teach-rule format in the Learn tab = **structured rows only**
(user rules as editable rows + built-in toggle rows; the raw `find => replace`
editor stays in `AdvancedTab`).

## Scope & phasing

Full build per the user. Suggested order. Each phase below is shippable on its own
with the noted caveat — P2's suppression toggles are the one deliberate inert-until-
P3 case, called out rather than hidden:

- **P1 — change-set enabler (Core).** Change the `preCorrect`/`postProcess` closure
  contract; instrument the five deterministic functions; thread `EditSet`
  (workflow-local strip/cleanup + closure-borne pre/post); preserve raw; expose
  `lastTranscriptAndEdits` (segmentA/segmentB); `Edit` model + `RuleDerivation` +
  `SuppressionSet`. Full Core test coverage (the fold + UTF-16 cases). No UI yet —
  the pure foundation everything else needs.
- **P2 — stores + Learn tab (Door #2).** `CorrectionRecord` + `CorrectionLogStore`;
  new settings keys; `LearnTab` (deferred queue + rule management + built-in
  suppression toggles). Reviewable at leisure; no overlay change yet. **Caveat:**
  the built-in suppression toggles **persist but are inert until P3** wires the
  apply-path consult — the user-visible no-op is accepted, and P3 activates them.
- **P3 — review panel + span gesture.** `ReviewPanelController` (own key panel, the
  `NSPanel` subclass) + `ReviewPanel` (tokens, span select, inline editor, "also
  bias"). Both doors open it. **Apply path now consults the suppression set +
  appended `TextReplacements`** — this is what makes P2's toggles do something.
- **P4 — Door #1 augmentation + hotkey + insert-target capture.** `OverlayState`
  swapped-ranges field + `showDone(text:swappedRanges:)`; underline swapped words +
  dim hint on the `.done` card; `.reviewLastDictation` shortcut + recorder; the
  App-layer insert wrapper that **captures** the target element (footgun hook). The
  insert-target *guard* is an explicit follow-up, not P4.
- **P5 — live re-insertion (experimental, default-OFF).** `AXSupport` writes
  (secure-field-guarded) + `SelectVerifyReplace` (pure decision unit-tested);
  `liveReinsertionEnabled` gate. Ships dark; the only experimental piece.
