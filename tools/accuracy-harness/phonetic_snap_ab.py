#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["jellyfish", "rapidfuzz"]
# ///
"""The measured basis for PhoneticSnapCorrections (Swift): does the phonetic
post-corrector still help ON TOP of the shipped
'Technical terms: {…}.' framing prompt (v0.4.19)?

Reuses the framed transcripts in prompt_framing_sweep.json ('wrapped' = shipped).
Scores: wrapped vs wrapped+phono, per condition. Also reports every text the
corrector changed so false swaps are visible one by one.
"""
import json, re, sys
from collections import defaultdict

import jellyfish
from rapidfuzz import fuzz

sys.path.insert(0, "/Users/ammielyawson/work/tools/local-dictation-qwen/tools/accuracy-harness")
import ab_recorder as R
import ab_scored as S
import jargon_corpus as JC
import harness as H

ROWS = json.load(open("/tmp/ld-h2h-results/prompt_framing_sweep.json"))
MIC_VOCAB = [t.strip() for t in (R.VOCAB + ", " + S.EXTRA_VOCAB).split(",") if t.strip()]
JARGON_VOCAB = [t.strip() for t in (R.VOCAB + ", " + ", ".join(JC._RARE_VOCAB)).split(",") if t.strip()]

PHONO_SIM = 0.80
ORTHO_SIM = 55


def keys(s):
    return jellyfish.metaphone(re.sub(r"[^a-z0-9 ]", "", s.lower()))


def sim(a, b):
    if not a or not b:
        return 0.0
    return 1 - jellyfish.levenshtein_distance(a, b) / max(len(a), len(b))


DICT = {w.strip().lower() for w in open("/usr/share/dict/words")}


def snap(hyp, vocab):
    terms = [(t, keys(t)) for t in vocab if len(re.sub(r"[^A-Za-z0-9]", "", t)) >= 4]
    present = {t.lower() for t in vocab}
    words = hyp.split()
    out, i = [], 0
    while i < len(words):
        best = None
        for n in (3, 2, 1):
            if i + n > len(words):
                continue
            window = " ".join(words[i:i + n])
            wclean = re.sub(r"[^a-z0-9]", "", window.lower())
            if not wclean or window.lower() in present:
                continue
            if all(re.sub(r"[^a-z']", "", w) in DICT for w in window.lower().split()):
                continue  # windows made only of real English words are never snapped
            wkey = keys(window)
            for term, tkey in terms:
                if term.lower() in hyp.lower():
                    continue
                p = sim(wkey, tkey)
                o = fuzz.ratio(wclean, re.sub(r"[^a-z0-9]", "", term.lower()))
                if p >= PHONO_SIM and o >= ORTHO_SIM:
                    score = p + o / 100
                    if best is None or score > best[2] or (score == best[2] and n > best[0]):
                        best = (n, term, score)
            if best and best[0] == n:
                break
        if best:
            out.append(best[1])
            i += best[0]
        else:
            out.append(words[i])
            i += 1
    return " ".join(out)


def main():
    groups = defaultdict(lambda: defaultdict(list))
    changes = []
    for r in ROWS:
        vocab = JARGON_VOCAB if r["set"] == "tts_jargon" else MIC_VOCAB
        grp = (r["set"] + ":" + ("jargon_names" if r["cat"] in ("jargon", "names") else r["cat"])
               if r["set"].startswith("mic/") else "tts_jargon")
        raw = r["wrapped"]["text"]
        fixed = snap(raw, vocab)
        w_raw, w_fix = H.wer(r["ref"], raw), H.wer(r["ref"], fixed)
        groups[grp]["wrapped"].append(w_raw)
        groups[grp]["wrapped+phono"].append(w_fix)
        if fixed != raw:
            changes.append((grp, w_raw, w_fix, r["ref"], raw, fixed))

    print(f"{'group':<28}{'n':>4}{'wrapped':>12}{'  +phono':>12}")
    order = ["mic/clean:jargon_names", "mic/clean:clean", "mic/hfp:jargon_names", "mic/hfp:clean",
             "mic/hfp_noisy:jargon_names", "mic/hfp_noisy:clean", "tts_jargon"]
    for g in [x for x in order if x in groups]:
        d = groups[g]
        print(f"{g:<28}{len(d['wrapped']):>4}{sum(d['wrapped'])/len(d['wrapped']):>12.3f}"
              f"{sum(d['wrapped+phono'])/len(d['wrapped+phono']):>12.3f}")

    helped = sum(1 for c in changes if c[2] < c[1])
    hurt = sum(1 for c in changes if c[2] > c[1])
    print(f"\nchanged {len(changes)} clips: {helped} improved, {hurt} regressed, {len(changes)-helped-hurt} neutral")
    for g, wr, wf, ref, raw, fixed in changes:
        if wf < wr:
            mark = "WIN "
        elif wf > wr:
            mark = "LOSS"
        else:
            mark = "same"
        print(f"\n[{mark}] ({g}) {wr:.3f} -> {wf:.3f}\n  ref:   {ref}\n  raw:   {raw}\n  fixed: {fixed}")


def traps():
    """Grade the corrector on substitution_ab.py's 50 cases (recall + trap corruption)."""
    sys.path.insert(0, __file__.rsplit("/", 1)[0])
    from substitution_ab import CASES
    fixed_n = missed = corrupt = safe = 0
    for transcript, candidates, gold, kind in CASES:
        out = snap(transcript, candidates)
        ok = re.sub(r"[^a-z0-9 ]", "", out.lower()).split() == re.sub(r"[^a-z0-9 ]", "", gold.lower()).split()
        if kind == "mishear":
            fixed_n, missed = (fixed_n + 1, missed) if ok else (fixed_n, missed + 1)
        else:
            safe, corrupt = (safe + 1, corrupt) if out == transcript else (safe, corrupt + 1)
    print(f"mishear: {fixed_n}/{fixed_n+missed} fixed; correct-trap: {corrupt}/{safe+corrupt} corrupted")


def parity(out_path):
    """Dump (raw -> fixed) pairs for the Swift LD_PHONO_PARITY conformance run."""
    rows = []
    for r in ROWS:
        vocab = JARGON_VOCAB if r["set"] == "tts_jargon" else MIC_VOCAB
        raw = r["wrapped"]["text"]
        rows.append({"set": r["set"], "raw": raw, "fixed": snap(raw, vocab)})
    json.dump({"mic_vocab": MIC_VOCAB, "jargon_vocab": JARGON_VOCAB, "rows": rows}, open(out_path, "w"), indent=1)
    print(f"{len(rows)} rows -> {out_path}")


if __name__ == "__main__":
    if "--traps" in sys.argv:
        traps()
    elif "--parity" in sys.argv:
        parity(sys.argv[sys.argv.index("--parity") + 1])
    else:
        main()
