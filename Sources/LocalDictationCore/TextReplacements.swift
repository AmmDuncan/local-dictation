import Foundation

/// Deterministic, fully-local find-replace / snippet expansion applied to a
/// finished transcript before insertion. Distinct from recognition vocabulary
/// (`RecognitionContext`), which biases what whisper *hears*; this rewrites the
/// text *after* transcription — fixing pet spellings ("teh" -> "the") and
/// expanding spoken triggers into stored blocks ("my address" -> a full line).
/// Opt-in and off by default.
public enum TextReplacements {
    public struct Rule: Equatable, Sendable {
        public let pattern: String
        public let replacement: String

        public init(pattern: String, replacement: String) {
            self.pattern = pattern
            self.replacement = replacement
        }
    }

    /// Parse a newline-delimited list. Each line is `trigger => replacement`
    /// (also accepts a bare `=`). Whitespace around each side is trimmed; blank
    /// lines, comment lines (`#`), and lines with an empty trigger are ignored.
    public static func parse(_ text: String) -> [Rule] {
        var rules: [Rule] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            let separator = line.contains("=>") ? "=>" : "="
            guard let range = line.range(of: separator) else { continue }
            let pattern = line[line.startIndex..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let replacement = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !pattern.isEmpty else { continue }
            rules.append(Rule(pattern: pattern, replacement: replacement))
        }
        return rules
    }

    /// Apply rules to `text` in order. Whole-word, case-insensitive matching; the
    /// replacement's own casing is used verbatim. A rule whose pattern can't form
    /// a valid expression is skipped (never throws into the insertion path).
    public static func apply(_ rules: [Rule], to text: String) -> String {
        applyTracked(rules, to: text).0
    }

    /// Like `apply`, but also returns one `Edit` per substitution, each with its
    /// `range` in the FINAL output string (UTF-16 units) so callers can highlight
    /// the swapped spans. This is the shared range-tracking engine — the other
    /// deterministic correctors route through it. `source` tags every emitted edit
    /// (e.g. `.mishearing`, `.command`); defaults to `.replacement`.
    public static func applyTracked(
        _ rules: [Rule],
        to text: String,
        source: Edit.Source = .replacement
    ) -> (String, [Edit]) {
        var result = text
        var edits: [Edit] = []
        for rule in rules {
            guard let regex = regex(for: rule) else { continue }
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: (result as NSString).length))
            guard !matches.isEmpty else { continue }

            let replacements = matches.map { (range: $0.range, to: rule.replacement) }
            let (newResult, newEdits, deltas) = EditTracking.rebuild(result, replacements: replacements, source: source)
            // Rebase edits accumulated from earlier rules into the new output space.
            edits = Edit.shifting(edits, by: deltas)
            edits.append(contentsOf: newEdits)
            result = newResult
        }
        return (result, edits)
    }

    /// Whole-word, case-insensitive regex for a rule. Word boundaries only where the
    /// edge is a word char, so phrase and punctuation triggers still match.
    private static func regex(for rule: Rule) -> NSRegularExpression? {
        let escaped = NSRegularExpression.escapedPattern(for: rule.pattern)
        let leading = rule.pattern.first.map(isWordEdge) == true ? #"\b"# : ""
        let trailing = rule.pattern.last.map(isWordEdge) == true ? #"\b"# : ""
        return try? NSRegularExpression(pattern: leading + escaped + trailing, options: [.caseInsensitive])
    }

    /// Convenience: parse `list` and apply to `text`.
    public static func applying(_ list: String, to text: String) -> String {
        apply(parse(list), to: text)
    }

    /// Serialize rules back to the newline `trigger => replacement` format that
    /// `parse` reads. Used by the Learn tab's structured-row editor to write changes
    /// back to the stored string. (Comments aren't preserved — structured editing
    /// owns the list; raw editing stays in Advanced.)
    public static func serialize(_ rules: [Rule]) -> String {
        rules.map { "\($0.pattern) => \($0.replacement)" }.joined(separator: "\n")
    }

    private static func isWordEdge(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }
}
