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
        var result = text
        for rule in rules {
            let escaped = NSRegularExpression.escapedPattern(for: rule.pattern)
            // Word boundaries only where the edge is a word char, so phrase and
            // punctuation triggers still match.
            let leading = rule.pattern.first.map(isWordEdge) == true ? #"\b"# : ""
            let trailing = rule.pattern.last.map(isWordEdge) == true ? #"\b"# : ""
            guard let regex = try? NSRegularExpression(
                pattern: leading + escaped + trailing, options: [.caseInsensitive]
            ) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            let template = NSRegularExpression.escapedTemplate(for: rule.replacement)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: template)
        }
        return result
    }

    /// Convenience: parse `list` and apply to `text`.
    public static func applying(_ list: String, to text: String) -> String {
        apply(parse(list), to: text)
    }

    private static func isWordEdge(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }
}
