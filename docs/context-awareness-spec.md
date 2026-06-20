# Context-Aware Dictation — Design Spec

**Status:** Proposed (not started) · **Date:** 2026-06-20 · **Repo:** `~/work/tools/local-dictation`, branch `main`

## Problem

The corrector can't fix mishearings where the *wrong* word is the statistically
common one and is too common to remap globally. Canonical case: dictating a git
command, **"push to main" → "push to me"**. `me → main` can't be a deterministic
rule (you say "me" constantly), and the LLM polish is intentionally cleanup-only
(no substitution) after substitution corrupted correct terms ("Claude Code" →
"Vibe Coding", see v0.2.3). The missing ingredient is **context**: *what app are
you in, what did you just type, what's on screen.* With context, "push to **me**"
in a terminal right after `git push origin` is unambiguously "push to **main**".

## Goals

- Use **on-device, local-only** context to (a) bias Whisper recognition and
  (b) safely enable substitutions that are unsafe globally but correct in context.
- Fix the "me → main" class without hurting prose dictation.
- Preserve the privacy promise: nothing leaves the Mac; context is transient.

## Non-goals

- No cloud/remote context. No always-on screen reading. No per-app profile UI
  (that was deliberately collapsed — context should be automatic, not configured).
- Don't re-enable global LLM substitution (it's off for good reason).

## Context sources (priority order)

Maps onto the existing `DictationContext` struct (`Sources/LocalDictationCore/ContextProvider.swift`):

| Source | API | → DictationContext field | Cost | Permission |
|---|---|---|---|---|
| **Frontmost app** | `NSWorkspace.shared.frontmostApplication` | `activeApplicationName` | ~0 | none |
| **Caret-preceding text** | extend `CaretContext` (AX `kAXStringForRangeParameterizedAttribute`) to read the preceding ~120 chars / current line, not just 1 char | `focusedElementDescription` (role/label) + a new preceding-text field | ms | Accessibility (held) |
| **Focused element role/label** | AX `AXRole`, `AXTitle`/`AXPlaceholderValue`, window title | `focusedElementDescription` | ms | Accessibility (held) |
| **Visible window text (AX tree)** | walk focused window's `AXStaticText`/`AXTextArea` values | `visibleText` (extracted candidates) | ms–tens of ms | Accessibility (held) |
| **OCR of active window (FALLBACK)** | Vision `VNRecognizeTextRequest` on a `CGWindowListCreateImage` grab | `visibleText` | ~150–300ms | **Screen Recording (new prompt)** |

**AX-first, OCR-fallback.** The AX tree gives structured, exact text instantly
and needs no new permission; OCR is only for apps that don't expose text
(canvas/GPU-drawn, some Electron) and carries a scarier permission + latency, so
gate it behind a setting and run it async/throttled.

## How context is used

1. **Recognition bias (no substitution risk).** Extend `RecognitionContext.prompt`
   (currently vocab + defaults + history) to also fold in: app-class vocabulary
   (terminal/editor → `git, main, branch, commit, rebase, npm, …`), caret-preceding
   text, and **candidate terms extracted from `visibleText`** (identifiers, proper
   nouns, branch-like tokens), **weighted by proximity to the caret** and capped to
   Whisper's ~224-token prompt budget. Whisper then leans to "main" before it ever
   guesses "me". This alone likely fixes most misses.

2. **Context-scoped correction (the "me → main" fix).** A *command mode*: when
   `activeApplicationName` is a terminal/editor **AND** the caret-preceding text
   matches a command pattern (`git (push|checkout|switch|merge|rebase) …`), run a
   stricter pass allowed to do substitutions banned in prose — `me|mane|main → main`,
   branch words, flags. Same rule, reckless in Slack, correct after `git push origin`.
   Implement as a context-gated variant alongside `MishearingCorrections` (which
   stays the global-safe layer).

3. **Command-aware formatting.** In command context, suppress sentence
   capitalization / trailing periods (no `Git push origin main.`). Context changes
   cleanup behavior, not just words.

4. **(Later) context-grounded LLM substitution.** Re-enable LLM word-swapping ONLY
   when grounded by context ("user in Terminal after `git push origin`, candidate
   branches: main, dev") — grounding is what made substitution unreliable before.

## Worked example: "push to me" → "push to main"

`ContextProvider.currentContext()` → `{ activeApplicationName: "iTerm2",
focusedElementDescription: "AXTextArea", precedingText: "git push origin ",
visibleText: "…on branch main…develop…" }` → RecognitionContext biases Whisper
toward `main`/`develop` → if Whisper still emits "me", command mode (terminal +
`git push origin` pattern) maps it to `main`, grounded by the branch names present
on screen → inserted: `git push origin main`.

## Constraints (non-negotiable)

- **Privacy:** on-device only; **opt-in**; **transient** (extract terms, discard —
  never log/store/persist context); **skip secure text fields** (passwords).
- **Latency budget:** AX read is cheap and synchronous-ok; OCR async + throttled/
  cached; never block insertion on context.
- **Selectivity:** never dump the whole screen into the prompt — extract relevant,
  caret-proximate candidates, capped to the token budget.

## Phased plan

- **P1 (highest leverage, lowest risk):** `AccessibilityContextProvider` filling
  `activeApplicationName` + preceding text; extend `RecognitionContext.prompt` to
  use them; app-class vocabulary table. Recognition bias only — no substitution.
- **P2:** command-mode context-scoped correction (terminal/editor + command-pattern
  → branch/flag substitutions). The direct "me → main" fix.
- **P3:** AX visible-window text → candidate extraction into `visibleText`, fed to
  bias + grounding.
- **P4:** OCR fallback (opt-in, Screen Recording perm) for text-less apps.
- **P5 (optional):** context-grounded LLM substitution.

## Testing

- Pure/unit (`LocalDictationCoreTestRunner`): context-candidate extraction,
  app-class vocab selection, command-pattern detection, scoped-correction rules
  (`me → main` fires in command context, NOT in prose context). All deterministic.
- Live: real-voice "push to me" in a terminal vs in Slack → correct in one, left
  alone in the other.

## Existing seams to build on

- `Sources/LocalDictationCore/ContextProvider.swift` — `DictationContext` (fields
  already defined) + `ContextProvider` protocol + `EmptyContextProvider`. **Add a
  real provider.**
- `Sources/LocalDictationApp/CaretContext.swift` — extend from 1 char to preceding
  text/line.
- `Sources/LocalDictationCore/RecognitionContext.swift` — extend `prompt(...)` to
  fold in context.
- `Sources/LocalDictationCore/MishearingCorrections.swift` — add a context-gated
  command-mode variant (keep the global-safe layer as-is).
- `Sources/LocalDictationApp/AppModel.swift` — `contextPrompt(settings:)` +
  `makeWorkflow` wire the provider in; `CaretAwareInserter` already proves AX caret
  access works at insertion time.

## Open questions

- Default on or opt-in for P1 (app + caret bias)? (Lean: on — no privacy cost
  beyond AX already used.) OCR clearly opt-in.
- App-class taxonomy + which terminals/editors map to "command" mode.
- Command-pattern coverage (git only first, or shell builtins too).
