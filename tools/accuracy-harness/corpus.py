"""Stress corpus for the mic-free accuracy harness.

Each entry is (text, category, kind):
  - text:     what `say` speaks (and, for speech, the expected transcript verbatim)
  - category: grouping for the per-category report
  - kind:     "speech"      — real speech, expected == text
              "nonspeech"   — silence/noise/ultra-short; expected == "" (any
                              insertable output is a hallucination)
              "echo_bait"   — short real speech run WITH the full vocab prompt;
                              we watch for prompt vocabulary leaking into output

The vocab PROMPT mirrors the app's DefaultVocabulary bias so decode matches the
real path. The echo_bait clips are deliberately short so an unbounded -mc lets
the long prompt bleed into the output.
"""

# Mirrors Sources/LocalDictationCore/DefaultVocabulary.swift (the default bias).
PROMPT = (
    "Claude, Anthropic, ChatGPT, OpenAI, Qwen, Gemini, GitHub, Xcode, "
    "TypeScript, JavaScript, Python, Swift, SwiftUI, React, Next.js, Tailwind, "
    "Node.js, Docker, Kubernetes, Postgres, Figma, Slack, Notion, Vercel, Supabase, "
    "git, main, branch, origin, commit, checkout, rebase, merge, npm, pnpm"
)

CORPUS = [
    # --- realistic prose (the actual use case — must NOT regress) ---
    ("The quick brown fox jumps over the lazy dog.", "prose", "speech"),
    ("Let's meet at three o'clock tomorrow afternoon.", "prose", "speech"),
    ("I think we should ship the feature this week.", "prose", "speech"),
    ("Can you send me the report before the end of the day?", "prose", "speech"),
    ("Please remember to back up your files regularly.", "prose", "speech"),
    ("The weather today is sunny with a light breeze.", "prose", "speech"),
    ("We need to schedule a follow up call next Tuesday.", "prose", "speech"),
    ("Thanks so much for your help, I really appreciate it.", "prose", "speech"),

    # --- product / tech names (vocab-bias should fix these) ---
    ("open Claude and ask Anthropic about the model", "names", "speech"),
    ("deploy the app to Vercel with a Supabase database", "names", "speech"),
    ("write it in TypeScript using React and Next.js", "names", "speech"),
    ("push the code to GitHub and open it in Xcode", "names", "speech"),
    ("use Tailwind for styling and Postgres for storage", "names", "speech"),
    ("ask ChatGPT and Gemini to compare the answers", "names", "speech"),
    ("the Kubernetes cluster is running in Docker", "names", "speech"),
    ("send the file in Slack and link it in Notion", "names", "speech"),

    # --- dev / command shapes ---
    ("git push origin main", "dev", "speech"),
    ("check out the feature branch and rebase onto develop", "dev", "speech"),
    ("commit the changes and open a pull request", "dev", "speech"),
    ("npm run build then docker compose up", "dev", "speech"),
    ("stash my changes and switch to the main branch", "dev", "speech"),
    ("merge the pull request into main", "dev", "speech"),
    ("run the test suite before you push", "dev", "speech"),
    ("revert the last commit and force push", "dev", "speech"),

    # --- homophones / command-mode bait (the "push to me" -> "main" class) ---
    ("git push origin main", "homophone", "speech"),
    ("git checkout main", "homophone", "speech"),
    ("switch to the main branch", "homophone", "speech"),
    ("their car is over there and they're leaving", "homophone", "speech"),
    ("write the code right now", "homophone", "speech"),
    ("I need to buy two items as well too", "homophone", "speech"),
    ("the affect of the change had a big effect", "homophone", "speech"),

    # --- numbers / versions / times ---
    ("the meeting is at nine thirty in the morning", "numbers", "speech"),
    ("increase the timeout to sixty seconds", "numbers", "speech"),
    ("we shipped in the year twenty twenty six", "numbers", "speech"),

    # --- punctuation-sensitive ---
    ("Hello, how are you? I'm fine, thanks!", "punct", "speech"),
    ("Wait, what? That can't be right.", "punct", "speech"),
    ("First, open the file; then, save it.", "punct", "speech"),

    # --- short one/two-word utterances (VAD-drop risk; must NOT vanish) ---
    ("yes", "short", "speech"),
    ("no", "short", "speech"),
    ("okay", "short", "speech"),
    ("undo", "short", "speech"),
    ("stop", "short", "speech"),
    ("delete", "short", "speech"),
    ("Claude", "short", "speech"),
    ("main", "short", "speech"),
    ("commit", "short", "speech"),
    ("send it", "short", "speech"),

    # --- non-speech: silence / noise / clicks (hallucination bait for -sns/-nth) ---
    # Generated synthetically (see harness.gen_nonspeech), text is the GENERATOR spec.
    ("silence:0.4", "nonspeech", "nonspeech"),
    ("silence:0.8", "nonspeech", "nonspeech"),
    ("silence:1.5", "nonspeech", "nonspeech"),
    ("noise:0.6:0.004", "nonspeech", "nonspeech"),   # faint room hiss
    ("noise:1.0:0.008", "nonspeech", "nonspeech"),   # louder hiss
    ("noise:0.5:0.02", "nonspeech", "nonspeech"),    # noticeable noise
    ("tone:0.3:440", "nonspeech", "nonspeech"),      # short beep/click
    ("silence:0.2", "nonspeech", "nonspeech"),       # ultra-short accidental tap
    ("noise:1.0:0.05", "nonspeech", "nonspeech"),    # loud hiss — may pass VAD
    ("noise:1.5:0.10", "nonspeech", "nonspeech"),    # louder still
    ("tone:0.6:220", "nonspeech", "nonspeech"),      # speech-band tone

    # --- echo bait: short real speech, scored for prompt leakage with -mc unbounded ---
    ("okay", "echo", "echo_bait"),
    ("yes please", "echo", "echo_bait"),
    ("got it", "echo", "echo_bait"),
    ("sounds good", "echo", "echo_bait"),
    ("let's go", "echo", "echo_bait"),
    ("one moment", "echo", "echo_bait"),
]
