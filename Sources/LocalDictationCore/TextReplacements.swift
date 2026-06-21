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
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { continue }

            var newResult = ""
            var newEdits: [Edit] = []
            // (location in the OLD string, length delta) per match, to rebase the
            // edits accumulated from earlier rules into the new output space.
            var deltas: [(at: Int, delta: Int)] = []
            var lastEnd = 0
            for match in matches {
                let r = match.range
                newResult += ns.substring(with: NSRange(location: lastEnd, length: r.location - lastEnd))
                let fromText = ns.substring(with: r)
                let toText = rule.replacement
                let outLocation = (newResult as NSString).length
                newResult += toText
                let outLength = (toText as NSString).length
                newEdits.append(Edit(location: outLocation, length: outLength, from: fromText, to: toText, source: source))
                deltas.append((at: r.location, delta: outLength - r.length))
                lastEnd = r.location + r.length
            }
            newResult += ns.substring(from: lastEnd)

            edits = edits.map { edit in
                let shift = deltas.filter { $0.at < edit.location }.reduce(0) { $0 + $1.delta }
                return Edit(location: edit.location + shift, length: edit.length, from: edit.from, to: edit.to, source: edit.source)
            }
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

    private static func isWordEdge(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }
}
