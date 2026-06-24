# Round 2 (post-v0.4.9) — What Could Improve Accuracy *More*

> **Research date:** 2026-06-24 (round 2) · **Baseline:** v0.4.9 — whisper.cpp 1.9.1 `ggml-large-v3-turbo` (fp16), greedy `-bs 1` (best-of 2 server default), temp-0 with temp-fallback ON, **Silero VAD v6.2.0** (shipped), `--prompt` vocab + AX/caret context biasing, deterministic mishearing map + command-mode git-homophone recovery, LLM polish (Gemma E2B, OFF) + experimental context-substitution (OFF, ~8% corrupt-correct).
> **Method:** 34 candidates across 6 research angles, each independently adversarially verified. Magnitudes take the **verifier's de-hyped `revisedGain`** over finder optimism. The `say`-TTS calibration gap still binds: every magnitude is directional until re-run on `--libri` or a real mic. Toolchain check confirmed: `whisper-server` supports `response_format=verbose_json`; `whisper-cli` exposes `-ojf`; per-token probability is emitted without `-dtw`.

---

## 1. Framing — where the *additional* gains are, honestly

Round 1 retired the one measured decode-flag win (`-mc 64` — regressed real prose) and shipped VAD v6 (no clean regression; noise upside still unmeasured). Round 2 confirms the round-1 verdict from a different angle: **no candidate offers a measured headline WER win on this stack**, and nothing dethrones turbo for an on-device app whose strongest feature is `--prompt` biasing. The realistic round-2 gains are *not* "lower WER" — they are **(a)** finally building the `verbose_json` confidence foundation (now triple-verified as a one-field flip + struct, per-word probability free of DTW), **(b)** using that signal to *gate* the OFF-by-default substitution pass so its ~8% corruption drops toward shippable, paired with a deterministic Double-Metaphone + dictionary triple-gate that replaces the fragile human-countdown safety, and **(c)** one genuinely net-new engine bet — Qwen3-ASR via MLX — that is the *first* documented counterexample to round-1's "engine swaps lose `--prompt` biasing," but lives or dies on a measured biasing-safety A/B and costs 5–6× the RAM. Everything else is a latency-only enabler, a measure-to-retire diagnostic, or a nothing-burger.

---

## 2. NET-NEW levers (not in round 1)

Ranked by value/cost. The confidence foundation leads because it is near-zero-cost, verified buildable exactly as described, and unblocks most of section 3.

### 2.1 `verbose_json` per-segment/per-token confidence — the foundation (verdict: **strong** → **MEASURED: weak for accuracy**)
*(Round-1 roadmap #1, but round 2 turned it from "switch the format" into a line-verified spec — so it leads here as the prerequisite for everything else.)*

> **⚠️ MEASURED 2026-06-24 (`confidence_calibration.py`, 500 LibriSpeech clips, turbo+VADv6+prompt, 10,515 words / 2.30% wrong):** word-level error-detection **AUC 0.836** (confidence ranks errors low) but **flag-precision only 0.10–0.18** at every threshold — the 2.3% base rate means ~82–90% of any low-confidence flag is a *correct* word. Utterance-level (min word-conf → any error) **AUC 0.585** (~chance). **NO-GO for any auto-gate/auto-suppression** (would delete ~9 correct words per error caught). The segment-level `avg_logprob` signal that the LLM-gate (2.2) actually wants is NOT exposed by `whisper-cli` (only the production `verbose_json` server path has it), so 2.2 is untested-and-unpromising. Confidence is empirically a **review-cue only** (AUC 0.836 supports ordering suspects in ⌃⌥Z — a UX nicety, not an accuracy win). **Conclusion: the confidence foundation is not the accuracy path; pivot to the deterministic triple-gate substitution (§3 #3), which needs no confidence signal.**

- **(a) What it changes** — `WhisperServerEngine.swift:60` posts `response_format=json` (text only); the `InferenceResponse` struct (~74–76) decodes `{text}` only. Flip to `verbose_json` and extend the struct to decode `segments[]` (`avg_logprob`, `no_speech_prob`, `temperature`) and `segments[].words[]` (`word`, `probability=token.p`). Caller already falls back to raw text → backward compatible.
- **(b) Gain + class** — Zero direct WER. Enabling-only: unlocks 2.2, 2.3, the gated substitution pass, and short-utterance abort. Most reliable on **single-word/very-short failures** (a low-prob lone word is a strong abort/flag candidate).
- **(c) Cost/risk** — Lowest in the set. No engine patch, permission, or notarization impact. JSON grows ~5–10× of a tiny payload (still sub-KB). Two myths busted *in the project's favor*: `no_speech_prob` is **active** code (only `compression_ratio` is stubbed); per-word `probability` is emitted **unconditionally** — it does NOT require `-dtw`/`token_timestamps`, so zero latency tax. Leave `token_timestamps` OFF.
- **(d) Harness** — Add a `vjson` config dumping `avg_logprob`/`no_speech_prob`/min-word-prob per utterance. **First assert `words[].word` concatenation reconstructs the segment text** before trusting per-word boundaries. Then bucket errors by confidence on `--libri` + a real-mic sample and build the error-detection ROC/AUC for *this* pipeline. **If distributions overlap heavily, every downstream gate is dead — measure this first.**
- **Evidence** — Fields verified by direct read of master `server.cpp` + the local Swift + the toolchain `--help`. Calibration caveat corroborated independently (arXiv 2509.07195; OpenAI #1183): `avg_logprob`/`no_speech_prob` are leaky — hallucinations pass them, turbo is overconfident on noise. **Confidence: high.** Ship behind a flag, log a measurement window, *then* decide on consumers.

### 2.2 Confidence-GATE the LLM passes — fire only on low-confidence utterances (verdict: **plausible**)

- **(a)** Run the (OFF) substitution/polish pass **only** when an utterance has a word below threshold or low segment `avg_logprob`; otherwise pass whisper text through untouched. "Gate WHEN to attempt a correction," not "decide WHAT to change."
- **(b)** *Not* a WER move. The win is operational: removes the LLM from the ~90% confident-correct dictations — exactly the population that produced the ~8% corruption — so corruption on clean inputs drops toward near-zero while **near-miss tech terms / rare jargon / accented proper nouns** (which surface as low-confidence) still get the pass. Net latency *win*.
- **(c)** Low cost (pre-check before an already-built pass). Threshold is model-specific — **calibrate on turbo, don't borrow 0.7/0.95 from tiny/medium**. Load-bearing failure mode: **homophones (get/git) are usually HIGH-confidence** so the gate skips them (leave to command-mode recovery); a *confidently-wrong* proper noun ("clod" for "Claude") is also high-confidence → the gate won't fire.
- **(d)** `substitution_ab.py`/`polish_ab.py`: sweep threshold T; metric = corruption-of-correct rate vs catch rate on the seeded-error set, plus % of utterances hitting the LLM. Pick T at the knee. Confirm residual errors actually land below threshold.
- **Evidence** — "Gate WHEN not WHAT" corroborated by 3 papers (2407.21414, 2509.25048, 2505.24347). De-hype: 2407.21414's own numbers show selective gating *slightly regressed* Whisper-Large-V3 on clean speech (2.78→2.86 WER) — on a strong model on clean speech there's little to correct. **Confidence: high** on mechanism; expect ~0 WER, reframe value as "makes substitution safe enough to enable."

### 2.3 Confidence is a review-cue, NOT an auto-deleter (verdict: **strong** — adopt as a design rule)

- **(a)** Forbids the literal reading of round-1's "confidence-gated SUPPRESSION of low-prob inserts." Raw word confidence as an automated error *detector* has precision **0.41–0.55** (CHI 2025, 9 ASR systems incl. Whisper). So low confidence may TRIGGER a phonetic-gated attempt (2.2 + §3 #3) or pre-select the lowest-confidence token in the existing ⌃⌥Z panel — **never silently delete.**
- **(b)** A guardrail: a hard "suppress any word below T" rule would delete a *true* word ~half the times it fires — worse than a visible misspelling for dictation. Small UX upside on short utterances (flag, don't drop).
- **(c)** None (reuses shipped `ReviewPanel`/`OverlayView`/`SuppressionSet.swift`). Hedge: CHI study found confidence *highlighting* didn't improve correction efficiency → keep UI minimal (near-free pre-selection of the lowest-confidence token).
- **(d)** Reuse the 2.1 calibration dump to compute this pipeline's precision/recall. **If local precision lands in 0.4–0.55, that empirically forbids auto-suppression.**
- **Evidence** — 2 independent sources (2503.15124 CHI 2025; 2509.07195: 11–22% of wrong tokens score >0.7). **Confidence: high.**

### 2.4 Qwen3-ASR-1.7B via MLX — the one engine that beats turbo AND keeps native biasing (verdict: **plausible**, high effort)

- **(a)** Off-by-default *alternate* engine behind the existing WAV→transcribe contract. The genuine counterexample to "engine swaps forfeit `--prompt` biasing": Qwen3-ASR was SFT'd on context-biasing data — feed the app's vocab + AX/caret context as a *trained-biasing* system-prompt string. Native Swift/MLX path exists (`Blaizzy/mlx-audio-swift`); `moona3k/mlx-qwen3-asr` (OpenAI-compatible server) is a viable interim helper.
- **(b)** Clean English: **~0–0.4 WER pts vs turbo — parity within noise**. The differentiated upside is the classes turbo can't reach via `--prompt`: **bare proper nouns on accents, near-miss tech terms, rare jargon** — independent evidence (TypeWhisper #321) shows the biasing path can ~2× jargon accuracy (18.2% vs 33.8% WER) *with correct wrapper framing*. Homophones not reliably helped; sub-1s carries decoder-only hallucination risk.
- **(c)** Biggest effort. **Double-edged biasing:** the same run shows naive space-joined context *regresses* WER ~2× and **echoes context tokens into output** — the exact corruption class the app already disabled in substitution. RAM: ~1.9–2.7GB + MLX vs turbo's ~0.4GB (5–6×). You abandon the tuned whisper.cpp temp-fallback + Silero v6 plumbing and re-tune. Use the **non-streaming 1.7B** (0.6B streaming has an open hotword-loop bug). Context must be wrapped ("Technical terms: …"), not a raw vocab dump.
- **(d)** Stand up the MLX helper; `LD_MODEL`→Qwen3-1.7B-8bit alongside turbo. (1) `--libri` WER vs turbo. (2) Jargon set, three arms: turbo+`--prompt` vs Qwen no-context vs Qwen+wrapped-context — exact-match + WER + **echo/regression check** on clean dictation. (3) Sub-1s hallucination rate vs turbo. (4) Cold-load + warm-resident latency + GPU contention with polish. Pass bar: Qwen+context beats turbo+prompt on jargon *without* regressing clean LibriSpeech, no context echo, p50 key-up sub-second.
- **Evidence** — Corroborated on WER/RTF/RAM (Soniqo), native biasing (Qwen report + arXiv 2512.21828), double-edged risk (TypeWhisper #321). **Confidence: medium.** Best lever for the app's actual failure list *if* biasing safety measures out — high-effort, gated on the 4 tests, not the headline 1.32%.

---

## 3. Deepened standing items

- **Roadmap #1 — confidence foundation → fully concrete.** See 2.1. One-field flip + struct; per-word prob free of DTW. Sequence: ship segment-level signal first, validate word-boundary reconstruction, log a measurement window, then build consumers.
- **Roadmap #2 — confidence-gated suppression → reframed.** See 2.2 (gate the LLM pass) + 2.3 (trigger/flag, never auto-delete). Literal "delete low-prob inserts" is forbidden by the 0.41–0.55 precision evidence.
- **Roadmap #3 — confidence-gated correction + phonetic gate → concrete deterministic triple-gate** that makes the substitution pass enable-able *without* the human countdown:
  - **Source gate** — only a token NOT in a common-English dictionary (`/usr/share/dict/words` or `NSSpellChecker` — no bundled wordlist) AND not in a homophone stoplist.
  - **Target gate** — replacement comes ONLY from the closed ~35-term lexicon (`ContextBias.substitutionCandidates()` already builds it). You can only correct *toward* a word the user cares about.
  - **Distance gate** — accept only if Damerau-Levenshtein of the two **Double-Metaphone** codes ≤ 1, plus a raw orthographic cap.
  - **Algorithm:** ship **Double Metaphone** (free; dual code helps foreign-origin names) **but strike the unsourced "95%/clear winner" framing** — the one peer-reviewed head-to-head (DATA 2016) shows DM's dual code can *hurt* open-match precision; keep single-Metaphone/NYSIIS as evidence-backed fallbacks. **Vendor the ~200–600-line DM port** (the `DoubleMetaphoneSwift` lib is unmaintained since 2017, no tests).
  - **De-hyped gain:** precision-control, recall bounded by the ~35-term lexicon, **~0 global WER**; targets near-miss tech terms / accented proper nouns; structurally EXCLUDES homophones. The "~0% corruption by construction" claim is **overstated** — a rare *correct* word missing from the dictionary that's DM-near a vocab term will leak; `/usr/share/dict/words` is weakest on exactly the proper nouns dictation users say.
  - **First measurement:** on `substitution_ab.py`, replace the LLM with the deterministic gates; corruption on trap cases (team→Teams, dock→docker) must drop materially below the LLM's ~8% (target <1%); recall on Supabae→Supabase must hold; `--libri` no-regression; **measure the dictionary-leak rate**. Blocked on #1 landing.
- **Roadmap #4 — dynamic end-weighted prompt → round-1 plan stands, two cautions.** The "irrelevant padding degrades rare-word WER ~3pts" claim is **mis-cited** (that's the fine-tuned case). 2406.05806 shows vanilla Whisper topic-follows <30% and relevant prompts are sometimes *worse* → reranking does NOT predict a WER gain. Most of "rank rare/capitalized, cap, no-history" is **already shipped** (`RecognitionContext.swift`/`ContextBias.swift`). Net-new sliver: a hard term-count cap (~50) + end-weighting — low value, unproven. First measurement: front-loaded vs end-weighted+spelling-guide+cap on `--libri`, reporting proper-noun exact-match AND unbiased-word WER. Strong prior: ~null on clean short dictation.
- **Roadmap #5 — auto-promote verified corrections → concrete, half shipped.** `RuleDerivation.teach()` already persists an exact-string rule on first accept. Net-new: also index `intended_word` into the DM lexicon (#3) for fuzzy recall, gated by **N≥2 confirmations + dictionary-collision check**. Blocked on #3. De-hyped: per-user, cumulative, **~0 aggregate WER**; literature ceiling ~3.5–8% relative on *targeted* terms. Risk is real: naive correction-learning *regressed* overall quality (4.5–20%) in the literature — the N≥2 + collision gate is load-bearing.
- **Roadmap #6 — distil-large-v3.5 → LATENCY-only enabler, plan stands.** Re-verified ~1.5× faster, short-form WER 7.08 vs turbo 7.30 (marginally better, in noise — the "regresses short-form" claim is **false**). Zero residual-class benefit. **New ship-blocker:** distil's 2-layer decoder handles prompt-context *worse* — and `--prompt` biasing is load-bearing — so gate on a real-mic biasing-parity check. Only worth it if a latency wall appears (it hasn't).
- **Roadmap #7 — `-bs 3` beam → prior stands (~0 on clean short dictation); selective variant cheap but low-priority.** Net-new: per-request `beam_size`/`best_of`/`temperature` ARE exposed in `server.cpp` → **a selective beam re-decode needs NO 2nd server** (answers the round-1 open question). De-hyped weak: <1.5pp on large-v3 English, proper-noun recovery is from *biasing not beam*, beam can hallucinate on short clips, and beam only engages at temp 0 (but fallback is ON). Run as a low-priority rider A/B after #1.

---

## 4. Newest-frontier check (2025–2026)

**Still no clear winner for this exact use case — with one real "maybe."** The frontier is LLM-decoder ASR (Canary-Qwen-2.5B tops the Open ASR Leaderboard at 5.63% WER; Parakeet-TDT-0.6B-v3 at 1.92% LS-clean) — but Canary-Qwen has **no on-device Apple-Silicon runtime and no inference-time biasing knob** (un-deployable here). CrispASR (ggml fork running Parakeet/Canary with a Metal server) is mechanically near-drop-in, but its `--hotwords` biasing claim is **uncorroborated and actively contradicted** by NVIDIA's own users (boosting degraded Parakeet WER 12→22%); it also forfeits the confidence roadmap (transducers emit no `avg_logprob`). The genuine exception is **Qwen3-ASR-1.7B (§2.4)** — turbo-parity-to-slightly-better on clean English, *native trained biasing*, a real Swift/MLX path. High integration cost (5–6× RAM, abandon tuned whisper.cpp plumbing, re-engineer context) and double-edged biasing. The only frontier item worth prototyping — OFF by default, gated on §2.4 — but **not a free win.**

---

## 5. Nothing-burgers (do not re-propose)

- **Canary-Qwen-2.5B** — reject. SOTA generic WER, but no on-device runtime, no biasing knob; un-deployable.
- **CrispASR / Parakeet-TDT engine swap** — weak→reject. Real latency/footprint win, but the `--hotwords` biasing claim is uncorroborated/contradicted; forfeits the confidence roadmap.
- **Moonshine v2 (streaming)** — reject for accuracy (no prompt-biasing API; streaming TTFT irrelevant for hold-to-talk). Record for a *future* live-preview UX only.
- **Multi-temperature self-consistency / ROVER voting** — reject. MBR re-eval (2510.19471) rules it out for real-time; regresses on short utterances + low-diversity greedy; n-best not exposed (→ N round-trips); worst latency.
- **Token entropy / top-k logit spread** — weak. "Entropy beats max-prob" mis-attributed; marginal add-on to #1.
- **Calibrate token-p via temperature scaling before gating** — reject. Temperature scaling is monotone → AUC unchanged by construction; dominated by grid-searching the threshold directly.
- **Idle Gemma generates the bias prompt pre-decode** — weak/reject. Source paper is NBA-domain, two-pass transcript-fed (= rejected feedback loop), corrupts 7–26%.
- **VAD `-vspd` sweep for sub-100ms words** — weak. Already tuned `-vspd 100`; lowering re-admits breath/click = the rejected `-sns` class.
- **Single-word phonetic confusion-set re-score (no-LLM)** — weak. Under-evidenced; viable only as a tiny fixed homophone trap-list downstream of #1.
- **Standalone Double-Metaphone post-corrector (no confidence gate)** — weak. A threshold can't split equidistant matched pairs (view/Vue); only viable as the precision half of the #3 interlock.
- **Caret-context homophone resolver (get/git)** — weak. Largely *already shipped* (`CommandModeCorrections.swift`).
- **Prompt-biasing scale-emergence (turbo vs large-v3)** — weak diagnostic. OWLS puts the biasing sweet spot at ~9B; both Whisper models are far below it. Free to run as a B-WER/U-WER diagnostic, but don't pre-commit to a large-v3 mode.
- **Targeted-prompt re-decode of low-confidence clips ("poor-man's B-Whisper")** — weak. B-Whisper's 45–60% is fine-tuning-only; overlaps #4 + the rejected transcript-as-bias loop; corrupting tail ~7%+.
- **Dynamic relevance-rank/cap of AX candidates** — weak/overlaps-shipped (already in `RecognitionContext.swift`/`ContextBias.swift`).

---

## 6. Recommended next experiment — DONE 2026-06-24

**Result: confidence calibration ran → NO-GO for auto-gating; pivot to the deterministic triple-gate (§3 #3).** `confidence_calibration.py` on 500 LibriSpeech clips: word AUC 0.836 (ranks errors) but flag-precision 0.10–0.18 (base-rate-killed), utterance AUC 0.585. Auto-suppression is dead; the segment-level LLM-gate signal isn't exposed by `whisper-cli`. The `verbose_json` foundation is only worth building for a review-cue UX, not accuracy. **Next build: the deterministic triple-gate substitution (§3 #3) — no confidence signal needed — measured on `substitution_ab.py` (target: ~8%→<1% corruption).**

<details><summary>Original experiment (executed)</summary>

**Build the `verbose_json` foundation (2.1) behind a flag and run the calibration measurement *before* building any gate** — the cheapest decisive thing, and it tells you whether the entire confidence line (2.2/2.3/§3 #2/#3) is alive on *this* pipeline. Concrete kill-criterion: if low `avg_logprob`/word-`p` doesn't separate the app's real errors from correct rare words, every downstream gate is dead and you stop.

```bash
# 1. Flip WhisperServerEngine.swift:60  json -> verbose_json (+ decode segments[]/words[]) behind a flag.
# 2. Assert word-boundary reconstruction in the harness BEFORE trusting per-word probs:
cd tools/accuracy-harness
LD_MODEL=~/models/ggml-large-v3-turbo.bin \
  python harness.py --configs vjson --voices multi   # dump avg_logprob / no_speech_prob / min-word-p per utterance
# 3. Decisive separation check on real speech (say-TTS understates WER ~2-3x):
LD_MODEL=~/models/ggml-large-v3-turbo.bin \
  python harness.py --configs vjson --libri /path/to/librispeech
# Compute error-detection precision/recall (ROC/AUC) of low-confidence -> wrong-token.
# GO only if a usable separation threshold exists AND local precision clears the 0.41-0.55 floor (else 2.3 forbids auto-suppression).
```

If that clears, the highest-value follow-on is the **deterministic triple-gate substitution (§3 #3)** measured on `substitution_ab.py` — the path to flipping substitution from OFF-because-it-corrupts to shippable, the largest realistic accuracy improvement on this stack that doesn't require the §2.4 engine bet.

</details>
