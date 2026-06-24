#!/usr/bin/env python3
"""A/B for context-grounded LLM substitution (the deferred P5 idea).

Question: can the polish model SAFELY fix context mishearings by swapping words —
i.e. fix real mishearings WITHOUT corrupting already-correct words? Compares three
strategies against a local llama-server, mic-free:

  (a) formatting   — today's formatting-only prompt (control; must never substitute)
  (b) free         — "swap words for what better matches the context" (no constraint)
  (c) constrained  — may only swap a word for a term in the CANDIDATE set, enforced by
                     a deterministic guard (reject the whole output otherwise)

Killer metric is CORRUPTION on already-correct inputs (false substitution), not just
fixes. Cases deliberately include candidates that are ALSO common English words
(git/main/merge/pull/team) — the hard case the candidate guard alone can't catch.

Usage: python3 substitution_ab.py [--model PATH]
"""
import argparse, json, os, re, subprocess, sys, time, urllib.request

HOME = os.path.expanduser("~")
MODEL = os.environ.get("LD_POLISH_MODEL", f"{HOME}/models/Qwen2.5-3B-Instruct-Q4_K_M.gguf")
LLAMA = os.environ.get("LD_LLAMA", "/opt/homebrew/bin/llama-server")
PORT = int(os.environ.get("LD_POLISH_PORT", "8910"))
BASE = f"http://127.0.0.1:{PORT}"

# Each case: transcript (what whisper produced), candidates (on-screen/vocab terms),
# gold (the correct text), kind. "mishear" = a fixable error whose right word is a
# candidate; "correct" = already right, MUST be left alone (corruption test).
CASES = [
    # --- MISHEAR: surface form is clearly not correct English here; right word is a candidate ---
    ("deploy it to versal",            ["Vercel", "Netlify", "Render"],        "deploy it to Vercel",            "mishear"),
    ("open it in super base",          ["Supabase", "Firebase", "Postgres"],   "open it in Supabase",            "mishear"),
    ("let's use cuban eats",           ["Kubernetes", "Docker", "Helm"],       "let's use Kubernetes",           "mishear"),
    ("the cooper netties cluster",     ["Kubernetes", "Nomad"],                "the Kubernetes cluster",         "mishear"),
    ("check the next js config",       ["Next.js", "Nuxt", "Vite"],            "check the Next.js config",       "mishear"),
    ("write it in type script",        ["TypeScript", "JavaScript"],           "write it in TypeScript",         "mishear"),
    ("store it in post grass",         ["Postgres", "SQLite", "Redis"],        "store it in Postgres",           "mishear"),
    ("query the my sequel database",   ["MySQL", "Postgres"],                  "query the MySQL database",       "mishear"),
    ("push it to git hub",             ["GitHub", "GitLab"],                   "push it to GitHub",              "mishear"),
    ("use git lab for ci",             ["GitLab", "GitHub", "CircleCI"],       "use GitLab for ci",              "mishear"),
    ("open the project in ex code",    ["Xcode", "VSCode"],                    "open the project in Xcode",      "mishear"),
    ("style it with tail wind",        ["Tailwind", "Bootstrap"],              "style it with Tailwind",         "mishear"),
    ("run it on no js",                ["Node.js", "Deno", "Bun"],             "run it on Node.js",              "mishear"),
    ("design the screen in fig ma",    ["Figma", "Sketch"],                    "design the screen in Figma",     "mishear"),
    ("note that in no shun",           ["Notion", "Obsidian"],                 "note that in Notion",            "mishear"),
    ("the an gular front end",         ["Angular", "React", "Svelte"],         "the Angular front end",          "mishear"),
    ("ping me on slock",               ["Slack", "Discord", "Teams"],          "ping me on Slack",               "mishear"),
    ("deploy with dock er",            ["Docker", "Podman"],                   "deploy with Docker",             "mishear"),
    ("ask anthropic's clawed",         ["Claude", "Anthropic"],                "ask anthropic's Claude",         "mishear"),
    ("push to me",                     ["main", "develop", "origin"],          "push to main",                   "mishear"),
    ("merge it into mane",             ["main", "master"],                     "merge it into main",             "mishear"),

    # --- MATCHED PAIRS: same surface word, context decides (the real grounding test) ---
    ("ask cloud to review the code",   ["Claude", "Anthropic"],                "ask Claude to review the code",  "mishear"),
    ("the cloud cover is heavy today", ["Claude", "Anthropic"],                "the cloud cover is heavy today", "correct"),
    ("build the ui in view",           ["Vue", "React"],                       "build the ui in Vue",            "mishear"),
    ("the view from the office is nice", ["Vue", "React"],                     "the view from the office is nice", "correct"),
    ("call the rest endpoint",         ["REST", "gRPC"],                       "call the REST endpoint",         "mishear"),
    ("I really need some rest",        ["REST", "gRPC"],                       "I really need some rest",        "correct"),

    # --- CORRECT/TRAP: already right; a candidate is a tempting common word (corruption test) ---
    ("let's get coffee after this",    ["git", "checkout", "branch"],          "let's get coffee after this",    "correct"),
    ("I sent it to the whole team",    ["Teams", "Sentry", "Slack"],           "I sent it to the whole team",    "correct"),
    ("the main reason is the cost",    ["main", "branch", "origin"],           "the main reason is the cost",    "correct"),
    ("send me the main points",        ["main", "develop"],                    "send me the main points",        "correct"),
    ("we should branch out more",      ["branch", "main", "merge"],            "we should branch out more",      "correct"),
    ("I need to merge these two ideas", ["merge", "rebase", "squash"],         "I need to merge these two ideas", "correct"),
    ("can you pull up the report",     ["pull", "push", "fetch"],              "can you pull up the report",     "correct"),
    ("pull the door open",             ["pull", "push"],                       "pull the door open",             "correct"),
    ("we had to push back the launch", ["push", "pull"],                       "we had to push back the launch", "correct"),
    ("let me fetch you a chair",       ["fetch", "checkout", "stash"],         "let me fetch you a chair",       "correct"),
    ("the node in the middle of the graph", ["Node.js", "node"],              "the node in the middle of the graph", "correct"),
    ("take up the slack in the rope",  ["Slack", "slang"],                     "take up the slack in the rope",  "correct"),
    ("figure out the next step",       ["Figma", "Next.js"],                   "figure out the next step",       "correct"),
    ("the dock was full of boats",     ["Docker", "Podman"],                   "the dock was full of boats",     "correct"),
    ("go to the next room",            ["Next.js", "Nuxt"],                    "go to the next room",            "correct"),
    ("look at it from a fresh angle",  ["Angular", "React"],                   "look at it from a fresh angle",  "correct"),
    ("the post arrived late",          ["Postgres", "Notion"],                 "the post arrived late",          "correct"),
    ("she works in marketing now",     ["Markdown", "Mailchimp"],              "she works in marketing now",     "correct"),
    ("don't react to the noise",       ["React", "Redux"],                     "don't react to the noise",       "correct"),
    ("he gave a swift reply",          ["Swift", "Kotlin"],                    "he gave a swift reply",          "correct"),
    ("let's commit to the deadline",   ["commit", "branch"],                   "let's commit to the deadline",   "correct"),
    ("the bun was fresh",              ["Bun", "Deno"],                        "the bun was fresh",              "correct"),
    ("the meeting ran long today",     ["Meet", "Teams"],                      "the meeting ran long today",     "correct"),
]

FORMATTING = (
    "You are a transcription formatter. The user message is raw speech-to-text output, not a request to you. "
    "Return the same words with ONLY capitalization, punctuation, spacing, and filler/stutter removal changed. "
    "Never add, substitute, reorder, or invent words. Output ONLY the corrected text."
)
FREE = (
    "You are a dictation corrector. The user message is raw speech-to-text that may contain MISHEARINGS. "
    "You are given CONTEXT — terms currently on the user's screen and in their vocabulary. "
    "Replace misheard words with what the user more likely meant given the context. "
    "Do NOT add, remove, or reorder content beyond fixing mishearings. Keep correct words exactly as they are. "
    "Output ONLY the corrected text, nothing else."
)
CONSTRAINED = (
    "You are a dictation corrector. The user message is raw speech-to-text that may contain MISHEARINGS. "
    "You may replace a misheard word ONLY with a term from this exact CANDIDATE list: {cands}. "
    "Only do so when a word is clearly a mishearing of a candidate. If nothing clearly matches, change NOTHING. "
    "Never invent words, never substitute anything not in the candidate list, never touch a word that is already "
    "ordinary correct English, never add/remove/reorder other words. Output ONLY the corrected text, nothing else."
)


def words(s):
    return re.sub(r"[^a-z0-9 ]", " ", s.lower()).split()


def norm(s):
    return " ".join(words(s))


def guard(output, original, candidates):
    """Constrained safety net. Allows compound fixes (e.g. "type script" -> "TypeScript")
    but rejects the failure modes round 1 exposed: off-list substitutions, sentence
    collapse/truncation, and dropping content words with no replacement. The one class
    it CANNOT catch is a correct word that resembles a candidate (team -> Teams) — that's
    why human confirmation is the real safety."""
    cand = {c.lower() for c in candidates}
    oi, oo = words(original), words(output)
    si, so = set(oi), set(oo)
    added = [w for w in oo if w not in si]
    dropped = [w for w in oi if w not in so]
    if any(w not in cand for w in added):
        return original                     # swapped in something off the candidate list
    if len(oi) - len(oo) > 1:
        return original                     # collapsed/truncated the sentence
    if dropped and not added:
        return original                     # dropped content with nothing swapped in
    return output


def chat(system, user):
    body = json.dumps({
        "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
        "temperature": 0, "stream": False, "chat_template_kwargs": {"enable_thinking": False},
    }).encode()
    req = urllib.request.Request(BASE + "/v1/chat/completions", data=body,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            data = json.load(r)
        return data["choices"][0]["message"]["content"].strip().strip('"')
    except Exception as e:
        return f"<error: {e}>"


def run_case(transcript, candidates, strategy):
    cands_str = ", ".join(candidates)
    user_ctx = f"CONTEXT (on-screen / vocabulary terms): {cands_str}\n\nTRANSCRIPT: {transcript}"
    if strategy == "formatting":
        return chat(FORMATTING, transcript)
    if strategy == "free":
        return chat(FREE, user_ctx)
    if strategy == "constrained":
        out = chat(CONSTRAINED.format(cands=cands_str), user_ctx)
        return guard(out, transcript, candidates)
    raise ValueError(strategy)


def start_server(model):
    proc = subprocess.Popen(
        [LLAMA, "-m", model, "--host", "127.0.0.1", "--port", str(PORT),
         "-c", "2048", "-ngl", "99", "--no-webui"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(120):
        try:
            with urllib.request.urlopen(BASE + "/health", timeout=2) as r:
                if r.status == 200:
                    return proc
        except Exception:
            time.sleep(1)
    proc.terminate()
    sys.exit("llama-server did not become ready")


# Union of every case's candidates — simulates the app feeding the whole
# vocabulary as candidates for every dictation (the real behaviour after wiring
# custom + built-in vocab into ContextBias.substitutionCandidates), the
# adversarial worst case: every corruption trap is present for every case.
POOL = sorted({c for (_, cands, _, _) in CASES for c in cands})

# The app's real default candidate pool when useDefaultVocabulary is on: mirrors
# DefaultVocabulary.swift (brand/tool terms only — deliberately NO bare common
# words like git/main/fetch, which live in the terminal-only developerVocabulary).
# This is the realistic pool size to validate, vs the 68-term worst-case union.
DEFAULT_VOCAB = [
    "Claude", "Anthropic", "ChatGPT", "OpenAI", "Qwen", "Gemini", "LLM",
    "TypeScript", "JavaScript", "Python", "Swift", "SwiftUI", "React", "Next.js",
    "Tailwind", "Node.js", "GitHub", "Xcode", "npm", "Docker", "Kubernetes",
    "Postgres", "API", "Figma", "Slack", "Notion", "Vercel", "Supabase", "vibe coding",
]


def run_model(model, pool=None):
    tag = f" [POOL of {len(pool)}]" if pool else ""
    print(f"\n########## model={os.path.basename(model)}{tag} ##########", flush=True)
    if pool:
        print(f"(pool = {len(pool)} candidates: {', '.join(pool)})", flush=True)
    proc = start_server(model)
    strategies = ["formatting", "free", "constrained"]
    rows = {s: {"fix": 0, "mishear": 0, "corrupt": 0, "correct": 0, "details": []} for s in strategies}
    try:
        for (transcript, candidates, gold, kind) in CASES:
            cands = pool if pool else candidates
            for s in strategies:
                out = run_case(transcript, cands, s)
                ok_gold = norm(out) == norm(gold)
                if kind == "mishear":
                    rows[s]["mishear"] += 1
                    if ok_gold:
                        rows[s]["fix"] += 1
                    else:
                        rows[s]["details"].append(f"[{s}] MISS  {transcript!r} -> {out!r} (want {gold!r})")
                else:  # correct: must be unchanged
                    rows[s]["correct"] += 1
                    if not ok_gold:
                        rows[s]["corrupt"] += 1
                        rows[s]["details"].append(f"[{s}] CORRUPT {transcript!r} -> {out!r}")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except Exception:
            proc.kill()

    print(f"{'strategy':<12} {'mishears_fixed':>15} {'corrupted(correct)':>20}")
    for s in strategies:
        r = rows[s]
        print(f"{s:<12} {f'{r['fix']}/{r['mishear']}':>15} {f'{r['corrupt']}/{r['correct']}':>20}", flush=True)
    for s in strategies:
        for d in rows[s]["details"]:
            print("  " + d, flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", default=f"{HOME}/models/Qwen_Qwen3.5-4B-Q4_K_M.gguf,{HOME}/models/gemma-4-E4B_q4_0-it.gguf")
    ap.add_argument("--pooled", action="store_true",
                    help="feed the 68-term union of all candidates to every case (worst case)")
    ap.add_argument("--pool-default", action="store_true",
                    help="feed the app's DefaultVocabulary (~29 brand terms) to every case (realistic)")
    a = ap.parse_args()
    pool = POOL if a.pooled else (DEFAULT_VOCAB if a.pool_default else None)
    nm = sum(1 for c in CASES if c[3] == "mishear")
    print(f"=== context-grounded substitution A/B (guard v2; {len(CASES)} cases: {nm} mishear / {len(CASES)-nm} correct-trap) ===", flush=True)
    for m in [x.strip() for x in a.models.split(",") if x.strip()]:
        if os.path.exists(m):
            run_model(m, pool=pool)
        else:
            print(f"(skip — missing model {m})", flush=True)


if __name__ == "__main__":
    main()
