# Local Dictation — Production Readiness Ledger

Goal: ship a tested, working macOS app that can be bundled and handed to friends.
"Done" = every persona below is **🟢 GREEN** (no open blockers in their lane).

## Persona team & sign-off

| Persona | Lane | Status |
|---|---|---|
| **Dana** — Release / Distribution Eng. | Signing, Gatekeeper-for-friends, whisper-cli + ggml plugins + libomp bundling, packaging, install UX, remove dev-only code | 🟢 GREEN |
| **Quinn** — QA / Test Eng. | Test coverage, real dictation flow, error/empty/permission-denied states, regressions | 🟢 GREEN |
| **Sasha** — Security & Privacy | "Strictly local" verification, network surface, model-download integrity (sha256), clipboard, permission strings, no telemetry | 🟢 GREEN |
| **Tom** — Swift Code Quality & Concurrency | Architecture, `@unchecked Sendable` correctness, async/actor safety, error handling, maintainability | 🟢 GREEN |
| **Robin** — UX & Accessibility | VoiceOver labels, keyboard nav, contrast, overlay, first-run/onboarding, empty/error states | 🟢 GREEN |
| **Iris** — Product Design Lead | Premium "funded-startup" overlay (Signal Energy: glass, breathing halo, live waveform, typed phases), menu-bar onboarding, brand cohesion | 🟢 GREEN |

**STATUS: ALL GREEN.** Self-contained friend build at `dist/LocalDictation.zip` (2.9M, zero Homebrew deps, Metal-accelerated, verified). Residual minors (acceptable for friends-distribution): normalizedLevel unit test (private App func), string-only clipboard restore, workflow-guard TOCTOU (safe under @MainActor topology), default model-path string.

### Dana re-review follow-up (the one RED → now GREEN)
The re-review caught that the Wave-C bundle still pulled `/opt/homebrew` for libomp AND the ggml compute backends (Metal/CPU/BLAS) are dlopen'd plugins from a baked Homebrew path — friends would crash. **Fixed:** bundle all 5 ggml plugins + libomp into Frameworks/ with rpath surgery; patch the baked plugin path (exact-length binary replace) to a fixed 40-char location the app symlinks to its own Frameworks at launch + before each dictation (`WhisperLocator.ensureBackendsLinked`). Verified: 0 `/opt/homebrew` refs in any binary; friend-sim (no symlink → 0 backends → fail; app creates symlink → 3 backends, Metal, transcribes).

Legend: 🔴 pending · 🟡 issues found (being fixed) · 🟢 green (signed off)

## Process
1. Each persona audits the settled code and reports findings (severity-ranked).
2. Findings triaged and fixed on the main thread (not bounced back to the auditor).
3. Persona re-reviews → flips to 🟢 when no blockers remain.
4. When all 🟢: live test, then produce a distributable bundle + friend install instructions.

## Fixes applied (Waves A–D)
- **Wave A (Core correctness):** clipboard-pollution bug fixed (restore via `defer`, regression test); watchdog race fixed (only timeout if process lost); sidecar `.txt` cleanup via `defer`; `DictationWorkflow` state lock-guarded; parser regex cached; arg-builder exposed + tested. **Test suite 12→18, all pass.**
- **Wave B (audio/model):** model SHA-256 verification (all 6 pinned, streamed CryptoKit); friendly download errors; recorder `isCapturing` lock-guarded; `writeWav` force-unwraps guarded; preview/final subprocess serialized (no CPU contention); defensive WAV `defer`.
- **Wave C (distribution):** **whisper-cli + 3 dylibs bundled into the .app** (rpath surgery, signed, VERIFIED running self-contained at 142ms) → friends need zero setup; `WhisperLocator` (bundled→Homebrew); LSMinimumSystemVersion→14; CFBundleVersion from git; `tiny.en` added; `package.sh` (ditto zip); `INSTALL.md`; release excludes the dev screenshot hook (`#if DEBUG`, verified 0 occurrences).
- **Wave D (UX/onboarding):** cold accessibility prompt removed (in-context only); menu-bar panel now shows dynamic shortcut + a "Finish setup" callout w/ failing items + Open Settings CTA; paste-on-release help; Language text field → picker; VoiceOver labels on health pills + level meter; Models tab badge when no model.
- **Wave E (overlay redesign):** in progress — design workflow exploring 3 premium directions.

## Findings log

### Dana (release/distribution) — 🟡 RED, 3 blockers
- BLOCKER: self-signed → Gatekeeper blocks on friends' Macs → ship right-click-Open / `xattr` instructions (no paid acct).
- BLOCKER: whisper-cli not on friends' machines + hardcoded `/opt/homebrew` path → **bundle whisper-cli + dylibs into the .app** (decided; feasible).
- BLOCKER: no entitlements/hardened runtime → only needed for notarization (not doing) → mic works via plist string; skip hardened runtime, sign `--deep` with our cert.
- MAJOR: LSMinimumSystemVersion 13 vs requires 14; arm64-only (Apple-Silicon friends only); no packaging step → `package.sh` (ditto zip).
- MINOR: CFBundleVersion always 1; LD_SCREENSHOT hook ships → `#if DEBUG`; default model path mismatch.

### Quinn (QA/test) — 🟡 RED, real bug + coverage gaps
- **REAL BUG (M4)**: `ClipboardInserter.insert` — if `sendPasteCommand()` throws, restore never runs → user's clipboard left holding the transcript. Fix + regression test.
- BLOCKERS: untested missing-audio-file path, recorder/transcriber throw-through-workflow.
- Add tests: clipboard-restore-on-failure, workflow error paths, `whisperArguments` beam/language, parser sidecar-whitespace + ggml log filter, normalizedLevel math.

### Sasha (security/privacy) — 🟡 mostly green, 2 majors
- MAJOR: no sha256 on downloaded models → add checksum verify (have all 6 hashes).
- MAJOR: transcript `.txt` sidecar not deleted on `processFailed` → `defer` cleanup.
- MINOR: clipboard restore loses rich content (string-only); preview WAV defensive `defer`; document clipboard exposure window.
- Verdict: honors "strictly local"; only outbound = HTTPS model downloads from HF.

### Robin (UX/a11y) — 🟡 RED, onboarding dead-ends
- BLOCKERS: invisible first-run + unnamed shortcut; whisper-cli install needs Terminal (← solved by bundling); cold accessibility prompt; no-model dead end.
- MAJOR: overlay stringly-typed → typed `DictationPhase` enum + redesign w/ live level meter + position persistence; VoiceOver labels on pills/meter; friendly download errors; Models tab badge; paste-on-release help.

### Tom (code/concurrency) — ⏳ still auditing

### Model SHA-256 (for integrity check)
- large-v3-turbo: `1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69`
- large-v3-turbo-q5_0: `394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2`
- medium.en: `cc37e93478338ec7700281a7ac30a10128929eb8f427dda2e865faa8f6da4356`
- small.en: `c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d`
- base.en: `a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002`
- tiny.en: `921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f`
