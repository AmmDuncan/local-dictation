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
    /// homophone is a misheard ref. Deliberately excludes `commit` / `-m` (those
    /// take a message, where "me" is genuinely "me"), so command mode never
    /// rewrites a commit message.
    private static let branchCommandRegex = try? NSRegularExpression(
        pattern: #"\bgit\s+(push|pull|fetch|checkout|switch|merge|rebase|branch|reset|cherry-pick)\b"#,
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
        precedingText: String?
    ) -> (String, [Edit]) {
        let line = [precedingText, transcript].compactMap { $0 }.joined(separator: " ")
        guard isCommandContext(appClass: appClass, line: line) else { return (transcript, []) }

        var (corrected, edits) = TextReplacements.applyTracked(branchRules, to: transcript, source: .command)
        let (formatted, formatEdits, formatDeltas) = commandFormattingTracked(corrected)
        edits = Edit.shifting(edits, by: formatDeltas)
        edits.append(contentsOf: formatEdits)
        return (formatted, edits)
    }

    /// Command-aware formatting: undo the prose cleanup that's wrong for a shell
    /// command — a trailing sentence period (`git push origin main.` breaks) and a
    /// capitalized leading `Git` (the shell is case-sensitive). Only ever runs in
    /// command context.
    private static func commandFormattingTracked(
        _ text: String
    ) -> (String, [Edit], [(at: Int, delta: Int)]) {
        var result = text
        var edits: [Edit] = []
        var deltas: [(at: Int, delta: Int)] = []

        if result.hasSuffix(".") {
            let periodLocation = (result as NSString).length - 1
            result.removeLast()
            // Deletion: zero-length `to` at the now-end of the string.
            edits.append(Edit(location: (result as NSString).length, length: 0, from: ".", to: "", source: .command))
            deltas.append((at: periodLocation, delta: -1))
        }
        if result.hasPrefix("Git ") {
            result = "git " + result.dropFirst(4)
            // Same length, so no offset delta; model the word change at the start.
            edits.append(Edit(location: 0, length: 3, from: "Git", to: "git", source: .command))
        }
        return (result, edits, deltas)
    }
}
