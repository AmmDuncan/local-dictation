# Dictation accuracy — mic-free A/B findings

*Date: 2026-06-23 · Branch: `feat/accuracy-tuning-and-harness` · Harness: `tools/accuracy-harness/`*

## What this was

The improvement research (`docs/dictation-improvement-research.md`) proposed a
"no-regret trio" of whisper decoder flags to improve recognition: `-sns`
(suppress non-speech), a raised `-nth` (no-speech threshold), and `-mc 64` (cap
context). Rather than trust the panel, we built a **mic-free A/B harness** and
measured them before shipping a line.

**Method.** `say` → 16 kHz mono WAV → `whisper-cli` (per clip, per config) → metrics
(exact-match, mean WER, hallucination-on-silence, prompt-echo). Decode is identical
to the resident `whisper-server` (same core; the server accepts the same flags), so
values measured here transfer to production. Corpus: ~57 clips across prose, names,
dev, homophones, numbers, punctuation, short utterances, plus synthesized
silence/noise/tone (hallucination bait) and short clips with the full vocab prompt
(echo bait). Runs: 12-config single-voice sweep on base.en; 4-config multi-voice
(4 voices, 188 speech clips) on base.en; 4-config single-voice on large-v3-turbo.

**Limitation (important).** `say` TTS is cleaner than real speech, so the harness
**understates** where vocabulary bias helps (bias earns its keep on accented / fast /
mumbled speech, which TTS doesn't produce) and where accidental-tap hallucination
happens (real breaths/clicks vs synthetic silence). Directional A/B of a specific
flag is valid and reproducible; absolute WER is optimistic. Real-voice verification
remains the owner's to do.

## Verdict: ship none of the three flags

| Flag | Panel claimed | Measured | Ship? |
|---|---|---|---|
| `-sns` | kills "Thank you." hallucinations on taps | **Harmful.** It suppresses the `[BLANK_AUDIO]`/`.` tokens the insertion path relies on to read silence as "no speech", forcing whisper to emit real words instead. No-VAD isolation: hallucinations 0 → 8/11 with the flag combo; `-sns` alone took a clean clip to a word. | **No** |
| `-nth` (0.60→0.70/0.80) | load-bearing knob | **Inert.** Byte-identical to baseline across every config — the tuned VAD already owns the no-speech decision, so the threshold never bites. | **No** |
| `-mc 64` (cap context) | minor hygiene win | **Tradeoff, net-negative on the default model.** Fixes long-utterance word-mashing (dev WER 0.135→0.064) but **weakens the flagship vocab-bias**: multi-voice names WER 0.088→0.120, "Claude"→"Cloud", "Vercel"→"vessel". `-mc 96/128` are no-ops (cap never engages). Clear win on turbo (exact 34→36, WER 0.078→0.057) but turbo isn't the default. | **No** (default); see follow-ups |

### Supporting numbers

base.en, single voice (47 speech / 11 non-speech):

```
baseline  exact 37/47  WER 0.081  halluc 0/11      <- VAD already nukes silence
sns       exact 37/47  WER 0.081  halluc 0/11      (VAD masks it; harm shows w/o VAD)
nth70/80  exact 37/47  WER 0.081  halluc 0/11      (inert)
mc32      exact 33/47  WER 0.089                   (too aggressive — hurts)
mc64      exact 36/47  WER 0.072                   (−1 exact; names regress)
nv_base   halluc 0/11   nv_sns halluc 1/11   nv_impr halluc 8/11   <- the -sns mechanism
```

base.en, multi-voice (4 voices, 188 speech):

```
baseline  exact 132/188  WER 0.1086
mc64      exact 129/188  WER 0.1049   names 0.088 -> 0.120 (Claude->Cloud)
mc96      exact 132/188  WER 0.1086   (identical to baseline — no-op)
mc128     exact 132/188  WER 0.1086   (identical to baseline — no-op)
```

large-v3-turbo, single voice:

```
baseline  exact 34/47  WER 0.078
sns       exact 34/47  WER 0.078   (inert here too)
mc64      exact 36/47  WER 0.057   (win — but turbo is not the default model)
mc96      exact 35/47  WER 0.076
```

## What shipped

**Command-mode git-homophone recovery.** The harness caught whisper mis-hearing the
command head even *with* the vocab prompt — "git checkout main" → "get checkout main"
(4× on one voice). Command mode now recognizes a misheard "get"/"guit" as "git" and
recovers it — but **only before an unambiguous git subcommand** (checkout / switch /
merge / rebase / fetch / cherry-pick), never before prose-ambiguous ones
(push / pull / branch / reset), so "get push notifications" is left alone. Terminal/
editor-gated like the rest of command mode. `Sources/LocalDictationCore/CommandModeCorrections.swift`;
tracked as a `.command` edit (the length-changing `guit`→`git` rebases later edits).

**Auto-bias taught corrections** (orthogonal to the flags; the genuine win). When a
user teaches a correction in the review panel, "also bias recognition" now defaults
**on** (opt-out), so the corrected term is added to the custom vocabulary that feeds
whisper's `--prompt` — the decoder stops mishearing the term, not just rewriting it
after the fact. Appends are de-duplicated (case/whitespace-insensitive) so re-teaching
can't bloat the prompt.

- `Sources/LocalDictationCore/CustomVocabulary.swift` — pure `appending(_:to:)` helper.
- `Sources/LocalDictationApp/ReviewPanel.swift` — `alsoBias` default `false`→`true`
  (decl + `resetEditor` + `clearSelection`); append routed through the helper.
- Tests: `testCustomVocabularyAppendDedup` (incl. CRLF). Suite 65→66, all green.

**Why this is sound while the flags aren't:** the vocab `--prompt` mechanism is
already proven net-positive — the prior campaign (`/tmp/ld-campaign/REPORT.md`,
Round 2) measured names 27/30 *with* prompt vs 22/30 without (+5: fixes
Vercel→"Versal", Supabase→"Superbase", main→"Maine"). Auto-bias extends that proven
path; it does not touch decoding.

## Reproduce

```bash
cd tools/accuracy-harness
python3 harness.py --configs baseline,improved --voices multi   # A/B
python3 harness.py --report                                     # re-print summary
LD_MODEL=~/models/ggml-large-v3-turbo.bin python3 harness.py --configs baseline,mc64
```

Configs are named whisper-cli arg-sets in `harness.py`; corpus in `corpus.py`.

## Follow-ups (data-backed, not yet done)

1. **Model-conditional `-mc 64`** — real win on large-v3-turbo, regression on base.en.
   If turbo (or another non-`.en` model) is adopted, apply `-mc 64` only there. Needs
   a multi-voice turbo run to confirm (the turbo win above is single-voice).
3. **Model default** — base.en beat turbo on exact-match for English here (37 vs 34),
   consistent with "prefer a `.en`-specialized model for the English path." Keep
   base.en as the default; don't switch to turbo for English.
4. **Real-voice pass (owner)** — confirm the auto-bias gain and re-check accidental-tap
   hallucination on real breaths/clicks, which TTS can't synthesize.
