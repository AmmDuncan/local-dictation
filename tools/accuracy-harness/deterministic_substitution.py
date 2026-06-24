#!/usr/bin/env python3
"""Deterministic triple-gate substitution (round-2 §3 #3) — NO LLM, NO confidence.

Replaces the LLM substitution pass with three deterministic gates so the corrector
can never corrupt a correct word (the reason substitution ships OFF):

  1. SOURCE gate  — only touch a window whose space-stripped form is NOT a real
                    English word (system dictionary). Real words (rest/team/main/
                    view/cloud/dock/post/angle…) are protected → can't be corrupted.
  2. TARGET gate  — the replacement must come from the candidate lexicon (vocab).
                    You can only ever correct *toward* a term the user cares about.
  3. DISTANCE gate — accept only if Double-Metaphone codes are within DIST of each
                    other (phonetic near-identity), so only true mishearings match.

Measures fix-rate (mishear→gold) vs corruption (correct word changed) on the SAME
CASES as substitution_ab.py, so the deterministic gate is directly comparable to
the LLM's ~8% corruption / high fix-rate. Pure Python — no llama-server, instant.

Run (needs jellyfish + metaphone in a venv):
  /tmp/ld-phon-venv/bin/python deterministic_substitution.py --pool-default
"""
import argparse, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jellyfish as jf  # noqa: E402
from metaphone import doublemetaphone  # noqa: E402
from substitution_ab import CASES, DEFAULT_VOCAB, POOL, norm  # noqa: E402

DICT = {w.strip().lower() for w in open("/usr/share/dict/words") if w.strip()}
# Function words: a window containing ANY of these can't be a tech-term mishearing,
# and gluing them onto a real word ("the cloud" -> "thecloud") was defeating the
# dict source-gate. Block any window that contains one.
FUNC = {
    "a", "an", "the", "to", "of", "in", "on", "at", "by", "for", "with", "from", "into",
    "it", "its", "is", "be", "am", "are", "was", "were", "i", "we", "me", "my", "you",
    "your", "he", "she", "him", "her", "they", "them", "this", "that", "these", "those",
    "and", "or", "but", "so", "not", "no", "up", "out", "as", "if", "then", "than", "some",
    "two", "too", "do", "did", "had", "has", "have", "will", "would", "can", "could",
}


def code(s):
    """Primary Double-Metaphone of the alnum-only lowercase form ('' if empty)."""
    s2 = re.sub(r"[^a-z0-9]", "", s.lower())
    return doublemetaphone(s2)[0] if s2 else ""


def eligible(window):
    """Source gate: a window may be replaced only if (1) it contains NO function
    word (those mark real prose, not a tech-term mishearing), and (2) its
    space-stripped concatenation is NOT a real dictionary word (real words/phrases
    are protected → can't be corrupted)."""
    if any(w.lower() in FUNC for w in window):
        return False
    concat = "".join(window).lower()
    if concat in DICT:
        return False
    return True


def apply_gate(transcript, candidates, dist):
    toks = transcript.split()
    n = len(toks)
    cand_codes = [(c, code(c)) for c in candidates]
    matches = []  # (start, length, candidate, code_dist)
    for i in range(n):
        for L in (1, 2, 3):
            if i + L > n:
                break
            win = toks[i:i + L]
            if not eligible(win):
                continue
            wc = code("".join(win))
            if not wc:
                continue
            wlen = len("".join(win))
            for c, cc in cand_codes:
                if not cc:
                    continue
                d = jf.damerau_levenshtein_distance(wc, cc)
                # raw orthographic guard: reject if surface and candidate are wildly
                # different lengths even when codes are close (avoids short->long flukes).
                clen = len(re.sub(r"[^a-z0-9]", "", c.lower()))
                if d <= dist and abs(wlen - clen) <= 3:
                    matches.append((i, L, c, d))
    # greedy non-overlapping: smallest code-distance first, then longest window
    matches.sort(key=lambda m: (m[3], -m[1], m[0]))
    used, chosen = set(), {}
    for (i, L, c, d) in matches:
        span = set(range(i, i + L))
        if span & used:
            continue
        used |= span
        chosen[i] = (L, c)
    out, i = [], 0
    while i < n:
        if i in chosen:
            L, c = chosen[i]
            out.append(c)
            i += L
        else:
            out.append(toks[i])
            i += 1
    return " ".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pool-default", action="store_true", help="feed DefaultVocabulary (~29) to every case (realistic)")
    ap.add_argument("--pooled", action="store_true", help="feed the 68-term union to every case (worst case)")
    ap.add_argument("--dists", default="1,2", help="comma-separated code-distance thresholds to sweep")
    a = ap.parse_args()
    pool = POOL if a.pooled else (DEFAULT_VOCAB if a.pool_default else None)
    tag = f"POOL of {len(pool)}" if pool else "per-case candidates"
    nm = sum(1 for c in CASES if c[3] == "mishear")
    print(f"=== DETERMINISTIC triple-gate (no LLM) — {len(CASES)} cases: {nm} mishear / {len(CASES)-nm} correct-trap ===")
    print(f"candidates: {tag} | dict={len(DICT)} words\n")

    for dist in [int(x) for x in a.dists.split(",")]:
        fix = mis = corrupt = corr = 0
        misses, corrupts = [], []
        for (transcript, cands, gold, kind) in CASES:
            use = pool if pool else cands
            out = apply_gate(transcript, use, dist)
            ok = norm(out) == norm(gold)
            if kind == "mishear":
                mis += 1
                if ok:
                    fix += 1
                else:
                    misses.append(f"MISS    {transcript!r} -> {out!r} (want {gold!r})")
            else:
                corr += 1
                if not ok:
                    corrupt += 1
                    corrupts.append(f"CORRUPT {transcript!r} -> {out!r}")
        print(f"--- code-distance <= {dist} ---")
        print(f"  mishears fixed : {fix}/{mis}  ({100*fix/mis:.0f}%)")
        print(f"  corrupted      : {corrupt}/{corr}  ({100*corrupt/corr:.1f}%)   <-- killer metric (LLM was ~8%)")
        for c in corrupts:
            print("    " + c)
        for m in misses:
            print("    " + m)
        print()


if __name__ == "__main__":
    main()
