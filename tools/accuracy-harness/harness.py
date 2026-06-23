#!/usr/bin/env python3
"""Mic-free A/B accuracy harness for Local Dictation.

Pipeline: `say`/`ffmpeg` -> 16 kHz mono WAV -> `whisper-cli` (per clip, per config)
-> metrics. Decode is identical to the resident whisper-server (same core; the
server accepts the same -sns/-nth/-mc flags), so values tuned here transfer to the
production path. Correction/bias layers (Swift) are covered by the unit-test runner.

Usage:
  python3 harness.py --configs baseline,improved --voices primary      # tuning
  python3 harness.py --configs baseline,improved --voices multi        # validation
  python3 harness.py --report                                          # re-print A/B

Configs are named whisper-cli arg-sets (see CONFIGS). `baseline` mirrors the app's
current WhisperCLICommand.arguments exactly. Results stream to <work>/results.jsonl;
the A/B table prints at the end. Set LD_MODEL to swap models (default base.en).
"""
import argparse, hashlib, json, os, re, subprocess, sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from corpus import CORPUS, PROMPT  # noqa: E402

HOME = os.path.expanduser("~")
MODEL = os.environ.get("LD_MODEL", f"{HOME}/models/ggml-base.en.bin")
VAD = f"{HOME}/models/ggml-silero-v5.1.2.bin"
WHISPER = os.environ.get("LD_WHISPER", "/opt/homebrew/bin/whisper-cli")
WORK = os.environ.get("LD_WORK", "/tmp/ld-accuracy")
WAVS = os.path.join(WORK, "wavs")
RESULTS = os.path.join(WORK, "results.jsonl")
os.makedirs(WAVS, exist_ok=True)

DESIRED_VOICES = ["Samantha", "Alex", "Daniel", "Karen", "Moira", "Tessa"]

# The app's current decode args (WhisperCLICommand.arguments + ResidentServerManager).
_DECODE = ["-nt", "-bs", "1", "-bo", "1", "-l", "en"]
_VAD = ["--vad", "-vm", VAD, "-vp", "200", "-vspd", "100"]
_PROMPT = ["--prompt", PROMPT]
_BASE = _DECODE + _VAD + _PROMPT            # the app's current default (VAD on)
_BASE_NOVAD = _DECODE + _PROMPT             # isolates flag effect on hallucination

CONFIGS = {
    # VAD-on family (production-realistic)
    "baseline": _BASE,
    "sns":      _BASE + ["-sns"],
    "nth70":    _BASE + ["-nth", "0.70"],
    "nth80":    _BASE + ["-nth", "0.80"],
    "mc32":     _BASE + ["-mc", "32"],
    "mc64":     _BASE + ["-mc", "64"],
    "mc96":     _BASE + ["-mc", "96"],
    "mc128":    _BASE + ["-mc", "128"],
    "improved": _BASE + ["-sns", "-nth", "0.70", "-mc", "64"],
    # no-VAD family (isolate -sns/-nth effect on hallucination — VAD masks it)
    "nv_base":  _BASE_NOVAD,
    "nv_sns":   _BASE_NOVAD + ["-sns"],
    "nv_nth70": _BASE_NOVAD + ["-nth", "0.70"],
    "nv_nth80": _BASE_NOVAD + ["-nth", "0.80"],
    "nv_impr":  _BASE_NOVAD + ["-sns", "-nth", "0.70", "-mc", "64"],
}

# Mirror of WhisperTranscriptParser.strippedForInsertion: drop non-speech
# annotations, then require a letter/number or the result is empty (nothing typed).
_NONSPEECH_RE = re.compile(r"\[[^\]]*\]|\([^)]*\)|\*{1,2}[^*]+\*{1,2}|♪[^♪]*♪|♪")
VOCAB_TERMS = [t.strip().lower() for t in PROMPT.replace(",", " ").split() if len(t.strip()) > 2]


def strip_for_insertion(text):
    base = re.sub(r"\s+", " ", _NONSPEECH_RE.sub(" ", text)).strip()
    return base if any(c.isalnum() for c in base) else ""


def norm(s):
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9 ]", " ", s.lower())).strip()


def wer(ref, hyp):
    r, h = norm(ref).split(), norm(hyp).split()
    if not r:
        return 0.0 if not h else 1.0
    d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        prev, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            cur = d[j]
            d[j] = min(d[j] + 1, d[j - 1] + 1, prev + (0 if r[i - 1] == h[j - 1] else 1))
            prev = cur
    return d[len(h)] / len(r)


def available_voices():
    try:
        out = subprocess.run(["say", "-v", "?"], capture_output=True, text=True, timeout=10).stdout
    except Exception:
        return []
    voices = []
    for line in out.splitlines():
        m = re.match(r"^(\S[\S ]*?)\s{2,}([a-z]{2}_[A-Z]{2})", line)
        if m and m.group(2).startswith("en"):
            voices.append(m.group(1).strip())
    return voices


def gen_speech(text, voice, rate):
    key = hashlib.md5(f"s|{text}|{voice}|{rate}".encode()).hexdigest()[:16]
    wav = os.path.join(WAVS, key + ".wav")
    if os.path.exists(wav) and os.path.getsize(wav) > 1000:
        return wav
    aiff = os.path.join(WAVS, key + ".aiff")
    cmd = ["say"] + (["-v", voice] if voice else []) + (["-r", str(rate)] if rate else []) + ["-o", aiff, text]
    subprocess.run(cmd, check=True, timeout=30)
    subprocess.run(["afconvert", aiff, "-o", wav, "-d", "LEI16@16000", "-c", "1"], check=True, timeout=30)
    try:
        os.remove(aiff)
    except OSError:
        pass
    return wav


def gen_nonspeech(spec):
    """spec: 'silence:DUR' | 'noise:DUR:AMP' | 'tone:DUR:FREQ' -> 16 kHz mono WAV via ffmpeg."""
    key = hashlib.md5(("n|" + spec).encode()).hexdigest()[:16]
    wav = os.path.join(WAVS, key + ".wav")
    if os.path.exists(wav) and os.path.getsize(wav) > 200:
        return wav
    parts = spec.split(":")
    kind = parts[0]
    if kind == "silence":
        src = f"anullsrc=r=16000:cl=mono"
        dur = parts[1]
    elif kind == "noise":
        dur, amp = parts[1], parts[2]
        src = f"anoisesrc=d={dur}:c=pink:r=16000:a={amp}"
    elif kind == "tone":
        dur, freq = parts[1], parts[2]
        src = f"sine=frequency={freq}:duration={dur}:sample_rate=16000"
    else:
        raise ValueError(spec)
    subprocess.run(["ffmpeg", "-y", "-f", "lavfi", "-i", src, "-t", parts[1],
                    "-ac", "1", "-ar", "16000", "-acodec", "pcm_s16le", wav],
                   check=True, capture_output=True, timeout=30)
    return wav


def transcribe(wav, config_args):
    base = os.path.join(WAVS, "out_" + hashlib.md5((wav + "".join(config_args)).encode()).hexdigest()[:12])
    txt = base + ".txt"
    args = [WHISPER, "-m", MODEL, "-f", wav, "-otxt", "-of", base] + config_args
    try:
        subprocess.run(args, check=True, capture_output=True, timeout=120)
        with open(txt) as f:
            raw = f.read()
    except Exception as e:
        raw = f"<error: {e}>"
    finally:
        try:
            os.remove(txt)
        except OSError:
            pass
    return re.sub(r"\s+", " ", raw).strip()


def echo_terms(insertable, expected):
    exp = set(norm(expected).split())
    got = norm(insertable).split()
    return [w for w in got if w in VOCAB_TERMS and w not in exp]


def run(configs, voices_mode):
    voices = available_voices()
    primary = next((v for v in DESIRED_VOICES if v in voices), (voices[0] if voices else ""))
    if voices_mode == "multi":
        speak_voices = [v for v in DESIRED_VOICES if v in voices][:4] or [primary]
    else:
        speak_voices = [primary]
    print(f"model={os.path.basename(MODEL)} configs={configs} voices={speak_voices}", flush=True)

    records = []
    open(RESULTS, "w").close()
    with open(RESULTS, "a") as out:
        for cfg in configs:
            cfg_args = CONFIGS[cfg]
            for (text, cat, kind) in CORPUS:
                # nonspeech clips are voice-independent; speak the rest in each voice.
                voset = [""] if kind == "nonspeech" else speak_voices
                for voice in voset:
                    wav = gen_nonspeech(text) if kind == "nonspeech" else gen_speech(text, voice, 0)
                    raw = transcribe(wav, cfg_args)
                    ins = strip_for_insertion(raw)
                    expected = "" if kind == "nonspeech" else text
                    rec = {
                        "config": cfg, "cat": cat, "kind": kind, "voice": voice,
                        "expected": expected, "raw": raw, "insertable": ins,
                        "wer": round(wer(expected, ins), 3) if kind != "nonspeech" else None,
                        "exact": norm(expected) == norm(ins) if kind != "nonspeech" else None,
                        "hallucinated": bool(ins) if kind == "nonspeech" else None,
                        "vad_drop": (kind == "speech" and ins == ""),
                        "echo": echo_terms(ins, expected) if kind == "echo_bait" else [],
                    }
                    records.append(rec)
                    out.write(json.dumps(rec) + "\n")
                    out.flush()
            print(f"  [{cfg}] done ({sum(1 for r in records if r['config']==cfg)} clips)", flush=True)
    report(records)


def load_records():
    with open(RESULTS) as f:
        return [json.loads(l) for l in f if l.strip()]


def report(records=None):
    records = records or load_records()
    configs = []
    for r in records:
        if r["config"] not in configs:
            configs.append(r["config"])

    print("\n=== A/B SUMMARY ===", flush=True)
    hdr = f"{'config':<10} {'speech_exact':>13} {'speech_WER':>11} {'halluc':>10} {'vad_drop':>9} {'echo':>8}"
    print(hdr)
    print("-" * len(hdr))
    for cfg in configs:
        rs = [r for r in records if r["config"] == cfg]
        sp = [r for r in rs if r["kind"] in ("speech",)]
        ns = [r for r in rs if r["kind"] == "nonspeech"]
        eb = [r for r in rs if r["kind"] == "echo_bait"]
        exact = sum(1 for r in sp if r["exact"]) if sp else 0
        mwer = sum(r["wer"] for r in sp) / len(sp) if sp else 0.0
        halluc = sum(1 for r in ns if r["hallucinated"])
        vdrop = sum(1 for r in sp if r["vad_drop"])
        echo = sum(1 for r in eb if r["echo"])
        print(f"{cfg:<10} {f'{exact}/{len(sp)}':>13} {mwer:>11.3f} "
              f"{f'{halluc}/{len(ns)}':>10} {f'{vdrop}/{len(sp)}':>9} {f'{echo}/{len(eb)}':>8}", flush=True)

    # Per-category WER for baseline vs improved (regression guard).
    pair = [c for c in ("baseline", "improved") if c in configs]
    if len(pair) == 2:
        print("\n=== per-category speech WER: baseline -> improved ===", flush=True)
        cats = []
        for r in records:
            if r["kind"] == "speech" and r["cat"] not in cats:
                cats.append(r["cat"])
        for cat in cats:
            row = {}
            for cfg in pair:
                rs = [r for r in records if r["config"] == cfg and r["cat"] == cat and r["kind"] == "speech"]
                row[cfg] = (sum(r["wer"] for r in rs) / len(rs), sum(1 for r in rs if r["exact"]), len(rs)) if rs else (0, 0, 0)
            b, im = row["baseline"], row["improved"]
            flag = "  <-- regressed" if im[0] > b[0] + 1e-9 else ""
            print(f"  {cat:<10} WER {b[0]:.3f} -> {im[0]:.3f}   exact {b[1]}/{b[2]} -> {im[1]}/{im[2]}{flag}", flush=True)

    # Show what hallucinated / echoed, so we can eyeball it.
    print("\n=== nonspeech outputs that survived stripping (hallucinations) ===", flush=True)
    seen = set()
    for r in records:
        if r["kind"] == "nonspeech" and r["hallucinated"]:
            k = (r["config"], r["expected"] or "?", r["insertable"])
            if k not in seen:
                seen.add(k)
                print(f"  [{r['config']}] {r['raw'][:60]!r} -> insertable={r['insertable']!r}", flush=True)
    if not seen:
        print("  (none — clean across all configs)", flush=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--configs", default="baseline,improved")
    ap.add_argument("--voices", choices=["primary", "multi"], default="primary")
    ap.add_argument("--report", action="store_true", help="re-print A/B from existing results.jsonl")
    a = ap.parse_args()
    if a.report:
        report()
    else:
        cfgs = [c.strip() for c in a.configs.split(",") if c.strip()]
        bad = [c for c in cfgs if c not in CONFIGS]
        if bad:
            sys.exit(f"unknown configs: {bad}; known: {list(CONFIGS)}")
        run(cfgs, a.voices)
