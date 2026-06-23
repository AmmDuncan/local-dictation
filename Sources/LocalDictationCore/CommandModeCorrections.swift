import Foundation

/// Context-scoped corrections that are CORRECT inside a typed command but unsafe
/// to apply globally. The canonical case: dictating a git command in a terminal,
/// "push to main" comes back as "push to me" — yet `me -> main` can never be a
/// global rule (you say "me" constantly). The fix is context: only when the
/// focused app is a shell/editor AND the line being composed is a branch-taking
/// git command do we map the branch-position homophones onto `main`.
///
/// This is the reckless layer that `MishearingCorrections` (the global-safe one)
/// deliberately can't be. It runs only after `isCommandContext` says yes, so the
/// exact same dictation in Slack or Notes is left completely alone.
public enum CommandModeCorrections {
    /// git subcommands that take a branch/ref argument, so a trailing branch-name
    /// homophone is a misheard ref. Excludes `commit`/`-m` (takes a message, where
    /// "me" is genuinely "me"), so command mode never rewrites a commit message.
    private static let branchSubPattern = "(?:push|pull|fetch|checkout|switch|merge|rebase|branch|reset|cherry-pick)"
    /// The subset we'll accept after a MISHEARD git head ("get"/"guit"): subcommands
    /// that aren't plausible English right after "get", so prose like "get push
    /// notifications" is never rewritten into a git command. Excludes push/pull/
    /// branch/reset (all common after "get").
    private static let homophoneSubPattern = "(?:checkout|switch|merge|rebase|fetch|cherry-pick)"

    /// Command context = the literal "git" before a branch subcommand, OR a misheard
    /// "get"/"guit" before an unambiguous one (whisper renders "git checkout" as
    /// "get checkout"). Deliberately excludes `commit` / `-m` (those take a message,
    /// where "me" is genuinely "me"), so command mode never rewrites a commit message.
    private static let branchCommandRegex = try? NSRegularExpression(
        pattern: "\\bgit\\s+\(branchSubPattern)\\b|\\b(?:get|guit)\\s+\(homophoneSubPattern)\\b",
        options: [.caseInsensitive]
    )

    /// The leading command head to normalize to lowercase "git": a capitalization of
    /// "git" before any branch subcommand, or a misheard "get"/"guit" before an
    /// unambiguous one. Anchored at the start; the subcommand is a lookahead, so the
    /// match is just the head word.
    private static let gitHeadRegex = try? NSRegularExpression(
        pattern: "^(git)(?=\\s+\(branchSubPattern))|^(get|guit)(?=\\s+\(homophoneSubPattern))",
        options: [.caseInsensitive]
    )

    /// Branch-position homophones of `main` that whisper emits for a spoken
    /// "main". Applied as whole-word, case-insensitive replacements (the lowercase
    /// `main` casing is kept), but ONLY in command context — see `apply`.
    static let branchRules: [TextReplacements.Rule] = [
        .init(pattern: "me", replacement: "main"),
        .init(pattern: "mane", replacement: "main"),
        .init(pattern: "maine", replacement: "main"),
        .init(pattern: "mein", replacement: "main"),
    ]

    /// True when the app permits command mode (terminal/editor) AND the composed
    /// line — the already-typed preceding text plus the new transcript — is a
    /// branch-taking git command. Prose apps (chat/notes/browser) never qualify.
    public static func isCommandContext(appClass: ContextBias.AppClass, line: String) -> Bool {
        guard appClass.allowsCommandMode, let branchCommandRegex else { return false }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return branchCommandRegex.firstMatch(in: line, range: range) != nil
    }

    /// Apply command-scoped corrections to `transcript`. The command pattern is
    /// detected on the FULL line (`precedingText` + `transcript`) so it works
    /// whether the user already typed `git push origin ` and only dictated the
    /// branch, or dictated the whole command; substitutions are applied only to
    /// the transcript (the part actually being inserted). Returns the transcript
    /// unchanged outside command context.
    public static func apply(
        to transcript: String,
        appClass: ContextBias.AppClass,
        precedingText: String?
    ) -> String {
        applyTracked(to: transcript, appClass: appClass, precedingText: precedingText).0
    }

    /// Like `apply`, but also returns one `.command` `Edit` per change (ranges in the
    /// output): the branch-homophone substitutions plus the `commandFormatting`
    /// mutations (trailing-period strip, `Git`→`git`). Returns the transcript
    /// unchanged with no edits outside command context.
    public static func applyTracked(
        to transcript: String,
        appClass: ContextBias.AppClass,
        precedingText: String?,
        suppressing: Set<String> = []
    ) -> (String, [Edit]) {
        let line = [precedingText, transcript].compactMap { $0 }.joined(separator: " ")
        guard isCommandContext(appClass: appClass, line: line) else { return (transcript, []) }

        let activeRules = branchRules.filter { rule in
            guard let id = RuleDerivation.suppressionIdentity(source: .command, from: rule.pattern, to: rule.replacement) else { return true }
            return !suppressing.contains(id)
        }
        var (corrected, edits) = TextReplacements.applyTracked(activeRules, to: transcript, source: .command)
        let (formatted, formatEdits, formatDeltas) = commandFormattingTracked(corrected)
        edits = Edit.shifting(edits, by: formatDeltas)
        edits.append(contentsOf: formatEdits)
        return (formatted, edits)
    }

    /// Command-aware formatting: undo the prose cleanup that's wrong for a shell
    /// command — normalize the leading command head to lowercase `git` (fixing a
    /// capitalized `Git` and a misheard `get`/`guit`) and strip a trailing sentence
    /// period (`git push origin main.` breaks). Only ever runs in command context.
    private static func commandFormattingTracked(
        _ text: String
    ) -> (String, [Edit], [(at: Int, delta: Int)]) {
        var result = text
        var edits: [Edit] = []
        var deltas: [(at: Int, delta: Int)] = []

        // Leading command head → "git". Done first (it's at the start) so its length
        // delta rebases every later edit. The lookahead in gitHeadRegex guarantees a
        // git subcommand follows, so a stray prose "Get"/"get" is never rewritten.
        if let gitHeadRegex,
           let match = gitHeadRegex.firstMatch(in: result, range: NSRange(result.startIndex..<result.endIndex, in: result)),
           let headRange = Range(match.range, in: result) {
            let head = String(result[headRange])
            if head != "git" {
                let oldLength = (head as NSString).length
                result.replaceSubrange(headRange, with: "git")
                edits.append(Edit(location: 0, length: 3, from: head, to: "git", source: .command))
                // The head sits at offset 0, so its last char is at oldLength-1; a
                // shorter "git" (the "guit" case) shifts every later edit left by 1.
                if oldLength != 3 { deltas.append((at: oldLength - 1, delta: 3 - oldLength)) }
            }
        }

        if result.hasSuffix(".") {
            let periodLocation = (result as NSString).length - 1
            result.removeLast()
            // Deletion: zero-length `to` at the now-end of the string.
            edits.append(Edit(location: (result as NSString).length, length: 0, from: ".", to: "", source: .command))
            deltas.append((at: periodLocation, delta: -1))
        }
        return (result, edits, deltas)
    }
}
