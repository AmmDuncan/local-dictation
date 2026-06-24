#!/usr/bin/env python3
"""Confidence-calibration experiment (round-2 gate).

Question: does whisper's per-token confidence separate REAL errors from correct
words on THIS pipeline? This decides whether the verbose_json confidence line
(gating / flagging) is worth building in the app — BEFORE any Swift code.

Method: run whisper-cli with -oj -ojf (full JSON, per-token `p`) using the
production-equivalent decode (turbo + Silero v6 VAD + vocab prompt) on
LibriSpeech, group subword tokens into words (min token-p = word confidence),
word-align hypothesis to reference, label each hyp word correct/wrong, then
compute the error-detection ROC-AUC + precision/recall of the rule
"flag word when confidence < T", at word AND utterance level.

KILL-CRITERION: if word-level AUC is ~0.5 (no separation) OR flag-precision
can't clear ~0.55 at any useful recall, the confidence gate is dead — stop,
don't build the verbose_json foundation.

Usage:
  LD_MODEL=~/models/ggml-large-v3-turbo.bin \\
    python3 confidence_calibration.py --libri /tmp/libri/LibriSpeech/test-clean --limit 500
"""
import argparse, hashlib, json, os, re, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import MODEL, VAD_V6, WHISPER, WAVS, flac_to_wav, load_libri, norm  # noqa: E402
from corpus import PROMPT  # noqa: E402

_SPECIAL = re.compile(r"^\[.*\]$")


def transcribe_json(wav, use_prompt=True):
    """Run whisper-cli with full JSON output; return the parsed dict or None."""
    base = os.path.join(WAVS, "calj_" + hashlib.md5((wav + str(use_prompt)).encode()).hexdigest()[:12])
    args = [WHISPER, "-m", MODEL, "-f", wav, "-oj", "-ojf", "-of", base,
            "-l", "en", "-nt", "-bs", "1", "-bo", "1",
            "--vad", "-vm", VAD_V6, "-vp", "200", "-vspd", "100"]
    if use_prompt:
        args += ["--prompt", PROMPT]
    try:
        subprocess.run(args, check=True, capture_output=True, timeout=180)
        with open(base + ".json") as f:
            return json.load(f)
    except Exception:
        return None
    finally:
        try:
            os.remove(base + ".json")
        except OSError:
            pass


def words_with_conf(js):
    """Group subword tokens into words. Return [(normalized_word, min_p, mean_p)].

    A word boundary is a token whose raw text starts with a space (whisper BPE
    convention). Word confidence = min token probability (weakest-link); mean
    kept for comparison. Special/bracket tokens and empties are dropped.
    """
    words = []
    cur_txt, cur_ps = "", []

    def flush():
        nonlocal cur_txt, cur_ps
        n = norm(cur_txt)
        if n and cur_ps:
            words.append((n, min(cur_ps), sum(cur_ps) / len(cur_ps)))
        cur_txt, cur_ps = "", []

    for seg in js.get("transcription", []):
        for t in seg.get("tokens", []):
            txt = t.get("text", "")
            p = t.get("p")
            if p is None or _SPECIAL.match(txt.strip()):
                continue
            if txt.startswith(" ") and cur_txt:
                flush()
            cur_txt += txt
            cur_ps.append(float(p))
    flush()
    return words


def align_labels(ref_words, hyp_words):
    """Levenshtein-align; return a bool per HYP word: True=correct(match), False=wrong(sub/ins)."""
    n, m = len(ref_words), len(hyp_words)
    d = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1):
        d[i][0] = i
    for j in range(m + 1):
        d[0][j] = j
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            cost = 0 if ref_words[i - 1] == hyp_words[j - 1] else 1
            d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
    i, j = n, m
    labels = {}
    while i > 0 or j > 0:
        if i > 0 and j > 0 and d[i][j] == d[i - 1][j - 1] + (0 if ref_words[i - 1] == hyp_words[j - 1] else 1):
            labels[j - 1] = ref_words[i - 1] == hyp_words[j - 1]
            i -= 1
            j -= 1
        elif j > 0 and d[i][j] == d[i][j - 1] + 1:
            labels[j - 1] = False  # insertion → wrong hyp word
            j -= 1
        else:
            i -= 1  # deletion → no hyp word
    return [labels.get(k, False) for k in range(m)]


def auc(scores, labels):
    """ROC-AUC where higher score should indicate the positive (wrong) class.
    scores: list of floats (wrongness score = 1 - confidence). labels: 1=wrong."""
    pairs = sorted(zip(scores, labels))
    npos = sum(labels)
    nneg = len(labels) - npos
    if npos == 0 or nneg == 0:
        return float("nan")
    # rank-sum (handle ties with average ranks)
    ranks = [0.0] * len(pairs)
    i = 0
    while i < len(pairs):
        j = i
        while j + 1 < len(pairs) and pairs[j + 1][0] == pairs[i][0]:
            j += 1
        avg = (i + j) / 2.0 + 1
        for k in range(i, j + 1):
            ranks[k] = avg
        i = j + 1
    rank_pos = sum(r for r, (_, lab) in zip(ranks, pairs) if lab == 1)
    return (rank_pos - npos * (npos + 1) / 2.0) / (npos * nneg)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--libri", required=True)
    ap.add_argument("--limit", type=int, default=500)
    a = ap.parse_args()

    items = load_libri(a.libri, a.limit)
    if not items:
        sys.exit(f"no LibriSpeech utterances under {a.libri}")
    print(f"model={os.path.basename(MODEL)} clips={len(items)} (production decode: turbo+VADv6+prompt)", flush=True)

    word_conf, word_wrong = [], []          # per-word min-p + wrong label
    utt_minconf, utt_haserr = [], []         # per-utterance signal + any-error label
    done = 0
    for uttid, flac, ref in items:
        js = transcribe_json(flac_to_wav(flac))
        if js is None:
            continue
        hyp = words_with_conf(js)
        if not hyp:
            continue
        ref_w = norm(ref).split()
        hyp_w = [w for (w, _, _) in hyp]
        labels = align_labels(ref_w, hyp_w)
        for (w, minp, _meanp), correct in zip(hyp, labels):
            word_conf.append(minp)
            word_wrong.append(0 if correct else 1)
        utt_minconf.append(min(minp for (_, minp, _) in hyp))
        utt_haserr.append(1 if any(not c for c in labels) else 0)
        done += 1
        if done % 50 == 0:
            print(f"  [{done}/{len(items)}]", flush=True)

    nw = len(word_conf)
    nwrong = sum(word_wrong)
    print("\n=== WORD-LEVEL confidence calibration ===", flush=True)
    print(f"words={nw}  wrong={nwrong} ({100*nwrong/nw:.2f}%)  correct={nw-nwrong}", flush=True)
    word_auc = auc([1 - c for c in word_conf], word_wrong)
    print(f"error-detection ROC-AUC (min token-p): {word_auc:.3f}   (0.5 = useless, 1.0 = perfect)", flush=True)
    print(f"{'thresh<T':>9} {'flagged':>8} {'precision':>10} {'recall':>8}   (precision = wrong among flagged)", flush=True)
    for T in (0.50, 0.60, 0.70, 0.80, 0.90, 0.95):
        flagged = [(w, c) for c, w in zip(word_conf, word_wrong) if c < T]
        nf = len(flagged)
        tp = sum(w for w, _ in flagged)
        prec = tp / nf if nf else float("nan")
        rec = tp / nwrong if nwrong else float("nan")
        print(f"{T:>9.2f} {nf:>8} {prec:>10.3f} {rec:>8.3f}", flush=True)

    print("\n=== UTTERANCE-LEVEL (min word-conf → any error) ===", flush=True)
    nu = len(utt_minconf)
    nue = sum(utt_haserr)
    utt_auc = auc([1 - c for c in utt_minconf], utt_haserr)
    print(f"utterances={nu}  with>=1 error={nue} ({100*nue/nu:.1f}%)", flush=True)
    print(f"error-detection ROC-AUC (min word-conf): {utt_auc:.3f}", flush=True)

    print("\n=== VERDICT ===", flush=True)
    floor = 0.55
    best_prec = max(
        (sum(w for w, c2 in zip(word_wrong, word_conf) if c2 < T) /
         max(1, sum(1 for c2 in word_conf if c2 < T)))
        for T in (0.50, 0.60, 0.70, 0.80, 0.90, 0.95)
    )
    go = (word_auc >= 0.70) and (best_prec >= floor)
    print(f"word AUC={word_auc:.3f}  best flag-precision={best_prec:.3f}  (need AUC>=0.70 AND precision>={floor})", flush=True)
    print("GO — confidence separates errors; the verbose_json gate is viable." if go
          else "NO-GO (or weak) — confidence does not cleanly separate errors on this pipeline; "
               "an auto-gate would be unreliable. Confidence is at best a review CUE, never an auto-deleter.", flush=True)


if __name__ == "__main__":
    main()
