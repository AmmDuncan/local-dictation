import Foundation

/// Turns on-device context — what app you're in and the text around the caret —
/// into recognition-bias terms and an app "class". Pure and deterministic: the
/// app-side `AccessibilityContextProvider` gathers the raw `DictationContext`,
/// and this distils it into bias terms (folded into the whisper prompt) plus the
/// command-mode signal, all without touching AppKit so it stays unit-testable.
public enum ContextBias {
    /// Coarse category of the focused app. Decides which built-in vocabulary to
    /// bias toward, and whether context-scoped command-mode substitution is even
    /// eligible (only in shells/editors, never in prose apps).
    public enum AppClass: String, Sendable, Equatable {
        case terminal
        case editor
        case browser
        case chat
        case notes
        case unknown

        /// Apps where a dictated git/shell command is plausible, so command-mode
        /// substitution (e.g. "me" -> "main") may run when the surrounding text
        /// also matches a command pattern. Prose apps never qualify.
        public var allowsCommandMode: Bool { self == .terminal || self == .editor }
    }

    /// Caret-proximate raw preceding text is capped to this many trailing chars
    /// before going into the prompt — enough to carry a command line, small
    /// enough to leave budget for vocabulary and candidates.
    public static let maxPrecedingChars = 80

    /// Classify the focused app from its (localized) name. Substring match,
    /// case-insensitive; terminal is checked before editor so an integrated
    /// terminal host still resolves sensibly. Unknown when nothing matches.
    public static func classify(appName: String?) -> AppClass {
        guard let name = appName?.lowercased(),
              !name.trimmingCharacters(in: .whitespaces).isEmpty else { return .unknown }
        func anyOf(_ tokens: [String]) -> Bool { tokens.contains { name.contains($0) } }

        if anyOf(terminalTokens) { return .terminal }
        if anyOf(editorTokens) { return .editor }
        if anyOf(chatTokens) { return .chat }
        if anyOf(browserTokens) { return .browser }
        if anyOf(notesTokens) { return .notes }
        return .unknown
    }

    private static let terminalTokens = [
        "iterm", "terminal", "warp", "kitty", "alacritty", "wezterm", "ghostty",
        "hyper", "tabby", "rio", "wave",
    ]
    private static let editorTokens = [
        "code", "xcode", "cursor", "windsurf", "sublime", "zed", "nova", "textmate",
        "jetbrains", "intellij", "pycharm", "webstorm", "goland", "rubymine",
        "phpstorm", "clion", "rider", "datagrip", "fleet", "android studio",
        "neovim", "vim", "emacs",
    ]
    private static let browserTokens = [
        "safari", "chrome", "chromium", "arc", "firefox", "brave", "edge",
        "vivaldi", "opera", "orion",
    ]
    private static let chatTokens = [
        "slack", "discord", "messages", "telegram", "whatsapp", "signal",
        "microsoft teams", "mattermost",
    ]
    private static let notesTokens = [
        "notes", "obsidian", "bear", "notion", "craft", "logseq", "typora",
        "ulysses", "drafts", "anytype",
    ]

    /// Built-in terms to bias whisper toward for a given app class. Shells and
    /// editors get the dev/git vocabulary that the canonical mishearings live in
    /// ("main", "branch", "origin", …); prose apps get nothing so dictation there
    /// isn't dragged toward jargon.
    public static func vocabulary(for appClass: AppClass) -> [String] {
        switch appClass {
        case .terminal, .editor: return developerVocabulary
        case .browser, .chat, .notes, .unknown: return []
        }
    }

    private static let developerVocabulary = [
        "git", "GitHub", "main", "master", "branch", "origin", "commit",
        "checkout", "rebase", "merge", "push", "pull", "fetch", "stash",
        "develop", "staging", "HEAD", "repo", "clone", "diff", "npm", "pnpm",
        "yarn", "Docker", "localhost", "dev", "prod", "deploy", "build",
    ]

    /// Distil a raw `DictationContext` into prompt-ready bias material:
    /// caret-proximate preceding text, app-class vocabulary, and identifier
    /// candidates extracted from the text around the caret/screen.
    public struct PromptContext: Equatable, Sendable {
        public var precedingText: String?
        public var appVocabulary: [String]
        public var candidates: [String]

        public init(precedingText: String? = nil, appVocabulary: [String] = [], candidates: [String] = []) {
            self.precedingText = precedingText
            self.appVocabulary = appVocabulary
            self.candidates = candidates
        }

        /// True when there is nothing to fold into the prompt.
        public var isEmpty: Bool {
            (precedingText?.isEmpty ?? true) && appVocabulary.isEmpty && candidates.isEmpty
        }
    }

    public static func promptContext(for context: DictationContext) -> PromptContext {
        PromptContext(
            precedingText: cappedPreceding(context.precedingText),
            appVocabulary: vocabulary(for: classify(appName: context.activeApplicationName)),
            candidates: candidates(precedingText: context.precedingText, visibleText: context.visibleText)
        )
    }

    /// The allow-list context substitution may swap a misheard word toward: the
    /// user's curated vocabulary (custom terms first, then the built-in defaults
    /// when enabled), followed by the live on-screen context (extracted identifier
    /// candidates, then app-class vocabulary). Vocabulary leads so the cap keeps
    /// the curated, low-noise terms the feature is designed around — the A/B
    /// harness that validated the swap safety feeds candidates that are exactly
    /// these "on-screen / vocabulary" terms. Deduped case-insensitively (first
    /// occurrence wins) and capped. Empty → substitution is skipped entirely.
    public static func substitutionCandidates(
        customVocabulary: String,
        defaults: [String] = [],
        context: PromptContext? = nil,
        limit: Int = 40
    ) -> [String] {
        let ordered = CustomVocabulary.terms(customVocabulary)
            + defaults
            + (context?.candidates ?? [])
            + (context?.appVocabulary ?? [])
        var seen = Set<String>()
        var result: [String] = []
        for term in ordered {
            let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, seen.insert(t.lowercased()).inserted else { continue }
            result.append(t)
            if result.count >= limit { break }
        }
        return result
    }

    /// Trailing slice of the preceding text, trimmed and capped — keeps the part
    /// closest to the caret (where the command/word being completed lives).
    static func cappedPreceding(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        guard trimmed.count > maxPrecedingChars else { return trimmed }
        return String(trimmed.suffix(maxPrecedingChars))
    }

    /// Extract identifier-like candidates (branch names, filenames, camelCase,
    /// ALLCAPS, versions) from the text around the caret, ordered by proximity:
    /// preceding text first (closest to where the user is speaking), then visible
    /// text. Deduped, capped. Plain dictionary words are left out — whisper
    /// already knows those; the value is the tokens it can't guess.
    public static func candidates(precedingText: String?, visibleText: String?, limit: Int = 24) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for source in [precedingText, visibleText] {
            guard let source else { continue }
            for token in tokenize(source) where isInteresting(token) {
                let key = token.lowercased()
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                result.append(token)
                if result.count >= limit { return result }
            }
        }
        return result
    }

    /// Split on whitespace and trim surrounding punctuation that isn't part of an
    /// identifier (quotes, parens, sentence punctuation), keeping inner `_-/.` so
    /// `feat/context`, `main.swift`, `snake_case` survive whole.
    private static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
            .map { trimEdges(String($0)) }
            .filter { !$0.isEmpty }
    }

    private static func trimEdges(_ token: String) -> String {
        let edge = CharacterSet(charactersIn: "\"'`(){}[]<>,;:!?…“”‘’")
        var chars = Array(token.unicodeScalars)
        while let first = chars.first, edge.contains(first) { chars.removeFirst() }
        while let last = chars.last, edge.contains(last) { chars.removeLast() }
        // Trailing sentence dots are noise; an inner dot (main.swift) is kept.
        while chars.last == "." { chars.removeLast() }
        return String(String.UnicodeScalarView(chars))
    }

    /// An "interesting" token is one whisper is unlikely to know: it carries an
    /// identifier shape (internal caps, an id separator, a digit+letter mix, or
    /// ALLCAPS) rather than being an ordinary lowercase word.
    public static func isInteresting(_ token: String) -> Bool {
        guard token.count >= 2, token.count <= 40 else { return false }
        guard token.first(where: { $0.isLetter }) != nil else { return false }

        let hasSeparator = token.contains("_") || token.contains("-")
            || token.contains("/") || token.contains(".")
        let hasDigit = token.contains(where: \.isNumber)
        let letters = token.filter(\.isLetter)
        let internalUpper = token.dropFirst().contains(where: \.isUppercase)
        let allCaps = letters.count >= 2 && letters.allSatisfy(\.isUppercase)

        if hasSeparator { return true }
        if internalUpper { return true }            // camelCase / PascalCase
        if allCaps { return true }                  // HEAD, API
        if hasDigit { return true }                 // v0.2.3, sha1
        return false
    }
}
