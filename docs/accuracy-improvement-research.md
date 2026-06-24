# LocalDictation — Transcription Accuracy Roadmap

> **Research date:** 2026-06-24 · **Baseline:** v0.4.7, whisper.cpp `ggml-large-v3-turbo` (fp16), greedy `-bs 1`, Silero VAD v5.1.2, `--prompt` vocab biasing.
> **Method:** multi-angle online research (7 angles) → independent adversarial verification of all 38 candidates (≥2 independent sources required, or downgrade) → synthesis. Every accuracy *magnitude* below is directional only until re-confirmed on `--libri` (real LibriSpeech) or a real-mic session — macOS `say` TTS understates real-mic WER ~2–3×.
>
> **⚠️ UPDATE 2026-06-24 — the headline Tier-1 item (`-mc 64`) was measured and REJECTED.** The TTS bracket reproduced the win (mc64 best), but the decisive `--libri` real-speech pass showed a small regression. It does *not* generalize to plain prose → do not ship. See §2 for the numbers. The negative result is the main payoff of running the harness; the rest of the roadmap stands.

---

## 1. Framing — where the realistic gains actually are

`large-v3-turbo` is already near the English accuracy frontier, and the cheap levers (static prompt biasing, the LLM polish/substitution passes) are exhausted: polish barely fires because whisper is too good, and substitution corrupts 8–15% of *correct* dictations. Across 38 candidates and their adversarial verifications, **no source produced a measured headline WER win for this stack.** Every big literature number (30%, 56%) came from a different regime — multilingual adaptation, lecture audio + GPT-4o revisor, trained TCPGen decoders, low-resource languages — that does **not** transfer to one English speaker on turbo.

So the honest opportunity is not "beat turbo's WER." It is:

1. **Promote one already-measured decode-flag win the project never shipped** (`-mc 64`).
2. **Make the existing correctors *safer*** via a real detection gate (confidence + phonetics), so the substitution pass becomes shippable instead of OFF-by-default-because-it-corrupts.
3. **Close two cheap open questions decisively** (beam search, VAD v6) so they stop costing attention.

The binding constraint everywhere is the TTS calibration gap — the harness is valid for *direction*, but ship decisions on *magnitude* need `--libri` or real mic.

---

## 2. Tier 1 — Do now / measure-first cheap wins

### `-mc 64` max-context cap → ~~promote to the turbo default~~ **MEASURED & REJECTED**

> **⚠️ MEASURED 2026-06-24 — do NOT ship globally.** TTS bracket (turbo, 4 voices, 188 speech clips) reproduced the win — mc64 was best of {32,64,96,128}: **exact 139→142, WER 0.075→0.061** (mc32 overshot: −8 exact + a hallucination; mc96/128 ≈ baseline). But the decisive `--libri` real-speech pass (200 LibriSpeech clips) **regressed**: **exact 158→157, meanWER 0.0314→0.0347** (~10% relative worse). Fails the pre-registered ship rule (must beat baseline on *both* on real speech). The prior "mc64 helps turbo" was a TTS + jargon-corpus + vocab-prompt-interference artifact; capping context helps when a long vocab `--prompt` fights short technical phrases, but slightly hurts ordinary prose. **Verdict: keep the greedy default, do not promote `-mc 64`.** A narrow salvage (cap context *only* when a vocab prompt is active AND the utterance is short) is complexity for a tiny, uncertain win — not recommended.

- **(a) What it changes** — Caps decoder prompt/prior-context at 64 tokens instead of the unbounded default. Production sets neither (`-mc` unset in `ResidentServerManager.swift:41` server args). Promotion = append `["-mc","64"]` to the server arg array (and the CLI path).
- **(b) Expected gain + cases** — The project's *own* harness measured turbo exact 34→36, WER 0.078→0.057. De-hyped: a small, corpus-specific win in the **vocab-prompt-interference** case-class (single-utterance dictation has no cross-segment history, so it only trims how much of the ~80-token vocab prompt the decoder over-weights). Expect ~+1–3 exact-match clips, a few-hundredths TTS WER drop; smaller in relative terms on real mic.
- **(c) Cost / latency / risk** — Latency-neutral or slightly *faster*. Lowest-risk item in the set. Only risk: the original number is single-source, uncommitted, left no git trace → re-confirm.
- **(d) Measure** — Configs already exist: `harness.py --configs baseline,mc32,mc64,mc96,mc128`, `LD_MODEL=…turbo.bin`, `--voices multi` to bracket, then `--libri` to confirm on real speech. Win = beats baseline on WER **and** exact-match. Commit the harness output.
- **Evidence** — Verdict **plausible**, confidence **high**. Mechanism corroborated by 2+ independent sources (whisper.h `n_max_text_ctx`; OpenAI `condition_on_previous_text` #679); magnitude single-source (internal TTS run). **Best-evidenced, cheapest item in the set.**

### Confidence-gated suppression of low-probability inserts *(depends on verbose_json below)*

- **(a)** Drop a result before insertion when segment `avg_logprob` is low **and** `no_speech_prob` is high — whisper's own silence test as an insert gate, applied *after* decode (not during, unlike the rejected `-sns`).
- **(b)** Real but small and narrow — trims phantom words on near-silence / breath / key-up tail that *survive* Silero VAD. Zero effect on correctly-heard words. Addressable population is only VAD's residue, so may be near-zero.
- **(c)** Near-zero latency. Risk: too-tight threshold eats real quiet speech. `avg_logprob` is trustworthy; `no_speech_prob` is the documented-unreliable leg (community uses >0.72, not 0.6). Gate on both, conservative default, behind a flag, OFF by default.
- **(d)** **Cheapest decisive pre-test first** — run the existing `gen_nonspeech` suite *with VAD on* and count how many phantom-word events even survive today. If near-zero → dead on arrival, stop. Else sweep the gate on `--libri` + multi-voice, measure false-suppression of real words.
- **Evidence** — Verdict **weak**, confidence medium. Gate logic confirmed in OpenAI `transcribe.py`. Adjacent to the rejected `-nth` — which is exactly why the VAD-residue pre-check gates the whole thing.

### Silero VAD v5.1.2 → v6.2.0 drop-in swap

> **✅ MEASURED 2026-06-24 — no clean-speech regression; safe to adopt.** A/B (turbo, `baseline` v5.1.2 vs `vad_v6` v6.2.0, harness configs differ by the model file only): **TTS multi-voice byte-identical** (exact 139/188, WER 0.075, halluc 0/11, vad_drop 0/188 — both). **LibriSpeech 500 real clips:** WER 0.0257→**0.0245** (flat-to-marginally-better), exact 390→387 (−3, within noise). Clears the no-regression bar. **Caveat:** both corpora are clean, so v6's actual upside (noise rejection) is **unmeasured here** — needs a real-mic-in-noise session before claiming the benefit. Harness `vad_v6` config is in place; app wiring (`build-app.sh:42` + `WhisperLocator.swift:21`, 2 spots) is staged, gated on the real-mic noise test.

- **(a)** Replace `ggml-silero-v5.1.2.bin` with `ggml-silero-v6.2.0.bin` (officially supported, whisper.cpp PR #3524). One-constant change in `WhisperLocator`; keep `-vp 200 -vspd 100`.
- **(b)** ~zero measurable WER on clean dictation (0.01 ROC-AUC gap). The prize is **noise rejection** (vendor: ESC-50 0.61→0.87) → fewer non-speech segments → fewer hallucinations on noisy input. Real but unproven in this app's short hold-to-talk regime.
- **(c)** Near-zero latency, sub-1MB, fully reversible. Risk: the v5-tuned `-vp/-vspd` operating point may sit worse on v6's curve — A/B, don't assume.
- **(d)** Add a `vad_v6` config (identical but for the VAD path). `--voices multi` for `vad_drop` + nonspeech `halluc`; `--libri` for WER. Ship only if halluc down-or-flat **and** vad_drop/short-utterance flat-or-better. **Gate the noise win on a real-mic session** — TTS is clean and structurally can't exercise it.
- **Evidence** — Verdict **plausible**, confidence medium. All numbers are vendor self-report, no independent replication. Cheap enough to A/B regardless.

### Keep VAD ON + add an over-segmentation guardrail *(verification, not a feature)*

- **(a)** No behavior change. Add a regression test asserting `-vmsd` is never set low and `-vo` stays ≥0.10, plus a one-line comment at `WhisperVAD.dictationTuningArguments`.
- **(b)** Zero new accuracy — the design is *already correct* (production sets only `-vp 200 -vspd 100`, leaving `max_speech_duration=FLT_MAX` so a sub-30s clip is never split; `samples_overlap=0.10` lossless stitch). Value: a guardrail so a future VAD/pad change can't silently start over-segmenting.
- **(c)** Zero.
- **(d)** Static config assertion; home is the existing VAD assertion test in `Sources/LocalDictationCoreTestRunner/main.swift:666`.
- **Evidence** — Verdict **plausible**, confidence high. Anti-hallucination value (21.3%→0.2%) confirmed (arXiv 2501.11378) but *already realized* by the shipped config. Don't cite the unverified 17–21%→6.5% WER figure.

---

## 3. Tier 2 — Worthwhile but needs measurement / a download / moderate work

### `verbose_json` foundation *(enabler — unlocks the confidence gates)*

- **(a)** `WhisperServerEngine.swift:60` posts `response_format=json` (text only). Switch to `verbose_json` and parse per-segment `avg_logprob` / `no_speech_prob` + per-token `probability`. Guard with a fallback to `.text`.
- **(b)** Zero direct accuracy — pure infrastructure. Unlocks the suppression gate (Tier 1) and the phonetic/confidence interlock below.
- **(c)** Negligible latency. **Correction to the original substitution spec: do NOT drop `-nt`.** Verified against `server.cpp`: `word["probability"]=token.p` emits *unconditionally*; segment fields need only `verbose_json`. Dropping `-nt` is unnecessary regression risk. Watch-item: temperature-fallback (`temp_inc 0.2`) perturbs `avg_logprob` → coarse gating only.
- **(d)** Before building any consumer, log `avg_logprob` / `no_speech_prob` distributions for correct vs. misrecognized vs. near-silence on real mic / `--libri` and confirm a usable separation threshold *exists*. No separation → the infrastructure unlocks nothing.
- **Evidence** — Verdict **plausible**, confidence high. Build only if a downstream consumer clears its own pre-check first.

### Phonetic-mismatch gate (Double Metaphone) AND-ed with confidence → precision filter on the substitution pass

- **(a)** Compute a phonetic code for output tokens and lexicon terms; a span is correction-eligible only when it's NOT a lexicon term but its phonetic code matches one (versal→Vercel, super base→Supabase). AND-ed with low confidence so high-confidence ordinary words (team, rest, view) are vetoed.
- **(b)** **Not a new accuracy win — a precision upgrade to the already-shipped-OFF substitution pass.** Goal: drive corruption on the in-repo homophone-trap cases toward 0 while holding fix-rate on the mishear cases. "Make substitution safe enough to turn on," not "beat turbo." Reject the implied 30%.
- **(c)** Metaphone port ≈200 lines pure Swift, sub-ms. Load-bearing dependency: per-word confidence (needs `verbose_json`) — **without the confidence AND-gate you have the dangerous OR-mode that fires on view/Vue.** Candidate extraction is identifier-shaped (digits, camelCase) which Metaphone keys poorly → scope to alphabetic/English-pronounceable terms.
- **(d)** Port Metaphone in Python, add the phonetic-eligibility gate to `substitution_ab.py` as the trigger. Corruption on the "correct"-trap cases must approach 0; fix-rate on "mishear" cases must hold. Mic-free, directional-valid.
- **Evidence** — Verdict **plausible**, confidence high (downgraded from implied 30%). One source (2506.10779) genuinely uses Metaphone + confidence interlock; a second offered source was mis-cited. Keep the human countdown; do **not** auto-apply on phonetic match alone.

### Confidence-gated correction (front-gate the substitution corrector on low word-confidence)

- **(a)** A detection gate in front of the substitution LLM — allow a span to be corrected only when its min word-confidence is below a tuned threshold.
- **(b)** Moderate reduction in *false* substitutions — directly attacks the 8–15% corruption, realistically toward ~3–7% (partial, not elimination; whisper is overconfident on 10–20% of its errors). Main win: protecting high-confidence ordinary words (team/Teams, dock/docker).
- **(c)** Near-zero latency. Scope to the substitution pass only — the deterministic map is already tight and gating it risks suppressing correct fixes. **Reject the "auto-apply on confident hit" extension** — confidence is least trustworthy on exactly the quiet/noisy cases you'd auto-apply to.
- **(d)** Switch a harness config to `verbose_json`, compute correct-vs-incorrect-word AUC of whisper `p` on *this app's* audio (the papers' 0.69–0.86 is on their data), sweep the threshold, report the corruption-vs-missed-fix tradeoff curve.
- **Evidence** — Verdict **plausible**, confidence high (downgraded). The candidate's own citations argue raw whisper `p` is overconfident — so the gate's value is *suppressing* corrections on high-`p` words, not trusting low `p`. Stacks in front of the existing `guardOutput`.

### Beam search `-bs 3` on turbo — close the open question *(do NOT ship `-bs 5`)*

- **(a)** Greedy `-bs 1` → beam `-bs 3` on the resident server. whisper.cpp's own default, which the project overrode; never measured here.
- **(b)** ~0.3–0.6pp absolute WER on real human speech, concentrated in proper-noun/acronym/homophone disambiguation, plus modest repetition-loop reduction. ~0 on the dominant short-clean-dictation case. **Gains saturate by beam ~3–4; beam=5 buys nothing over 3.**
- **(c)** Latency is the binding cost — ~6× decode compute, but turbo's 4-layer decoder is cheap vs the encoder so the wall-clock hit is smaller than full-Whisper benchmarks imply. **Caveat (maintainer jongwook):** beam operates only at temperature 0; when temp-fallback fires (which this app keeps ON) beam is *disabled* and decoding switches to best-of sampling — so beam only touches the clean segments where gains are smallest.
- **(d)** Add `turbo_beam3`, run `--libri` for real WER + log per-clip decode wall-time. **Decision rule: ship `-bs 3` ONLY if `--libri` shows ≥0.4pp WER win AND measured key-up latency stays sub-second.** Else keep greedy.
- **Evidence** — Verdict **weak** (consistent across all four beam candidates), confidence medium. Cheap to falsify (one config line); strong prior is ~0 gain on this case-class. **Measure once to retire the question; the prior says reject.**

### Drop-in ggml swap to distil-large-v3.5 — adopt for LATENCY, not accuracy

- **(a)** Swap model file to distil-large-v3.5 (official ggml, MIT, ~1.52GB). Same engine, flags, prompt-bias, VAD.
- **(b)** Accuracy: small, corpus-dependent short-form win vs *turbo only* (~0.2–0.6pp WER, within TTS noise). The claim it beats full large-v3 is a factual error (large-v3 ≈7.12, distil ≈7.08; the edge is only over turbo). Real payoff: **~1.5× faster** → latency headroom to fund the beam-search test.
- **(c)** Harness eval = pure `LD_MODEL` swap. Shipping needs a SHA-pinned catalog entry. **Smoke `-fa`+Metal at the project's whisper.cpp ~v1.9.x first** — distil's 2-layer decoder has historically caused whisper.cpp quirks.
- **(d)** `LD_MODEL=distil` vs turbo on `--libri` + `--voices multi`; compare WER, exact-match, nonspeech halluc, key-up latency. Smoke `-fa`/Metal load first.
- **Evidence** — Verdict **plausible**, confidence medium. Two independent sources agree on direction, disagree on magnitude. **Decouple: adopt for latency headroom, not as an accuracy upgrade.**

---

## 4. Tier 3 — Research bets / structural (honest about uncertainty)

### Dynamic per-utterance prompt: end-weight rare tokens, cap ~150 tokens

- **(a)** Stop sending the static front-loaded vocab blob. Score the already-extracted candidates, truncate harder, and reorder so the highest-value spellings sit at the *end* of the prompt (where whisper's attention is strongest). Use a spelling-guide form ("Friends: Aimee, Shawn").
- **(b)** Small and proper-noun-only. There genuinely is an unpulled lever — `RecognitionContext.prompt()` deliberately *front-loads* vocab "so it survives the cap," which is the wrong end if end-weighting is real. Magnitude unmeasured by any source.
- **(c)** Near-zero latency. Real downside is better-evidenced than the upside: naive prompt-biasing *raised* unbiased WER on 6/11 datasets (2502.11572). Hard-cap ~150 tokens; default OFF.
- **(d)** Named-config A/B (front-loaded vs end-weighted+spelling-guide+cap) reporting BOTH proper-noun exact-match AND unbiased-word WER; re-run on `--libri` for U-WER damage on common words. Verify the build's actual prompt window (224 vs `n_text_ctx` 448) before hardcoding a cap.
- **Evidence** — Verdict **plausible**, confidence medium. End-weighting mechanism corroborated by 2 independent sources; reordering *magnitude* uncorroborated. A/B-gate, default-off.

### Prompt-learning + post-processing personalization from the correction log

- **(a)** Mine the verified correction log to (a) auto-grow the `--prompt` vocab (frequency-ranked) and (b) auto-promote high-frequency, high-confidence raw→corrected pairs into the deterministic mishearing map. **Not** the rejected transcript-history loop — these are *verified corrections*, not raw prior transcripts.
- **(b)** Compounding win on the user's *exact-repeat* proper-noun/jargon/homophone tail. The deterministic-map half is the safe real win (high-precision, instant, can't corrupt if gated). The prompt half carries a +1–3pp U-WER regression risk → near-neutral overall.
- **(c)** Low. `CorrectionLog.swift` already keeps the last 200 dictations with edit history. Gate map promotion strictly: N≥3 identical raw→corrected occurrences, whole-word, replacement isn't itself a common English word, never re-promote a pair the user later un-corrected, surface as undoable in the Learn tab.
- **(d)** `substitution_ab.py` for the glossary half (corruption must not rise); unit-test the promotion rule + `harness.py` neutral clips to confirm new map entries never fire on correct text.
- **Evidence** — Both verdicts **plausible**, confidence high. Mechanism independently sourced; the 10% figure is from a generalizing SMT and doesn't transfer to a frequency-promoted lexical map. Bounded, compounding, default-off behind a corruption gate.

---

## 5. Tried-and-rejected — do not repeat

| Item | Why |
|---|---|
| `-sns` (suppress non-speech tokens) | **HARMFUL** — emits real words on near-silence. Already measured-rejected. |
| `-nth` raise (0.6→0.8) | **INERT** — tuned Silero VAD already owns the no-speech decision. |
| `-nf` (no temp fallback) | Removes turbo's repetition-loop escape hatch. |
| disabling `-fa` | English unaffected, CJK-only regression. |
| transcript-history-as-prompt-bias | Feedback loop — one bad transcript poisoned the next. |
| **`-bs 5 -bo 5` specifically** | Beam gains saturate by ~3–4; beam=5 buys nothing over 3 for the latency cost. Test `-bs 3`, not 5. |
| `--suppress-regex` targeting | **reject** — clobbers special tokens (#3355), slow on multibyte (#3356); a deterministic Swift strip strictly dominates. |
| Entropy/logprob threshold tuning (2.4→2.8 / −1.0→−1.25) | **weak** — gain uncorroborated (anecdotal); clean-speech neutrality passes vacuously; two opposite levers conflated. Piggyback on the `-mc 64` run at most. |
| On-device denoise (RNNoise / DeepFilterNet / Voice Isolation) | **strong reject** — 3 independent studies, 3 denoisers, all regress Whisper (+1.1% to +46.6% WER); harm grows with model size and turbo is large. Keep denoise OUT. |
| GBNF grammar-constrained decode | **weak** — 67→98% gain is mis-attributed (trained TCPGen, not GBNF); GBNF leaks partial words; command-mode here is post-decode regex, so no clean bolt-on. |
| CrisperWhisper | **reject** — large-v2-based (trails v3 on English), verbatim output is a *regression* for dictation, not runnable in whisper.cpp. |
| Engine swap → Parakeet-TDT | **weak** — wins generic WER (~1.4) but LOSES whisper `--prompt` biasing (raw jargon WER ~20%), the app's strongest feature. Net neutral-to-negative here. |
| Apple SpeechAnalyzer / SpeechTranscriber | **weak/reject** as accuracy — English parity-to-worse vs turbo; no weighted vocab = jargon regression; macOS 26+ gate. Latency/footprint play only. |
| Quantize turbo (q5/q8) | **weak** — footprint play mislabeled as accuracy; nil benefit on a 36GB Mac; can only hold-or-lose accuracy on the cases the app cares about. |
| LoRA / full fine-tune INTO whisper.cpp | **reject** — whisper.cpp has no runtime LoRA; merge-and-convert produces garbage at inference (issues #1866, #10, both open). |
| B-Whisper instruction-tuned biasing | **reject** near-term — real ceiling (45–60% rare-word) but needs engine swap (TCPGen) + GPU training + custom model. Ceiling marker only. |
| MLX LoRA "personalized engine" | **weak** — engine swap, audio-retention privacy surface, catastrophic-forgetting risk; the one on-target source rates single-speaker gain "modest" and training-free. |
| KenLM n-best rescore | **reject** — n-gram benefit *vanishes* on Large-V3/high-resource English; no n-best exists (greedy) so it needs beam first; risks pulling jargon toward common phrasing. |
| Deterministic phonetic auto-fix (no LLM) | **weak** — degraded version is just "grow the risky mishearing table," whose 8–15% corruption is already measured-and-warned. |
| Per-word confidence flags in review panel | **weak** — raw whisper posteriors are overconfident/miscalibrated, so low-`p` doesn't cleanly route to errors; needs verbose_json plumbing for a noisy hint. |
| Confidence-gated beam cascade | **weak** — single-sourced <1.5pp, tail-only ~0.1–0.5pp aggregate; per-request beam isn't exposed on the resident server (needs a 2nd server = double RAM). Ship `-mc 64` instead. |
| Phonetic-anchored LLM adjudication | **weak** — phonetics is structurally blind to the matched-pair class it targets (view/rest/team have ~0 phonetic distance to their candidates). |
| Core ML (ANE) encoder | **weak** — honest "0 accuracy"; power benefit overstated; live failure mode on M4+recent macOS (#3702). |
| DC-block / 60–80Hz HPF | **plausible-but-narrow** — "mel ignores sub-85Hz" is false (fmin=0Hz); ~0 on clean input. Safe minimal variant if ever: pure DC-block (~10–20Hz). |
| RMS/loudness normalization | **weak** — whisper.cpp's per-clip-max mel norm already absorbs loudness within [-1,1]; ~0 on harness, narrow real-mic edge only. |
| VAD pad/min-silence/threshold grid | **plausible-but-narrow** — fair to A/B *one* conservative cell (`-vp 300`, keep `-vspd 100`, threshold 0.50); harness can't see the trailing-clip win (no key-up tail). Owner real-mic only. |

---

## 6. Recommended first experiment ~~(this week)~~ — DONE 2026-06-24

**Result: `-mc 64` REJECTED.** Ran the bracket below on turbo. TTS A/B picked mc64 as best (exact 139→142, WER 0.075→0.061), but the `--libri` real-speech confirmation regressed (exact 158→157, meanWER 0.0314→0.0347), failing the ship rule. Greedy default stays. **Next candidate to run through the same gate: the VAD v5→v6 swap** (add a `vad_v6` config, same `--voices multi` + `--libri` protocol).

<details><summary>Original experiment (executed)</summary>

**Promote and re-confirm `-mc 64` on turbo** — the only candidate that is high-confidence, already-measured-positive, zero-latency, zero-new-code-to-test, and a 2-line ship.

```bash
cd tools/accuracy-harness
LD_MODEL=~/models/ggml-large-v3-turbo.bin \
  python harness.py --configs baseline,mc32,mc64,mc96,mc128 --voices multi
# then the decisive real-speech pass:
LD_MODEL=~/models/ggml-large-v3-turbo.bin \
  python harness.py --configs baseline,mc64 --libri /path/to/librispeech
```

**Ship rule:** if `mc64` (or whichever bracket point wins) beats baseline on **both** WER and exact-match on `--libri` within noise — reproducing the prior ~0.057 — add `["-mc","64"]` to the server arg array (`ResidentServerManager.swift:41`) + the CLI path, **commit the harness output**, and do a real-mic smoke. While that bracket runs (~50 min) it's free to piggyback the entropy/logprob threshold configs — but expect vacuous neutrality; don't spend a dedicated campaign on them.

</details>

---

### The one-line strategy

The big multipliers (engine swaps, fine-tuning, denoise, grammar decode) are all either rejected on evidence or net-negative for *this* stack. The durable path is **(1) ship the measured `-mc 64`**, **(2) build the `verbose_json` confidence foundation once** and use it to make the substitution corrector *safe* (phonetic + confidence AND-gate) rather than chasing raw WER, and **(3) let the correction log compound** into the deterministic map behind a strict promotion gate. Plus two cheap decisive A/Bs (`-bs 3`, VAD v6) to retire open questions.
