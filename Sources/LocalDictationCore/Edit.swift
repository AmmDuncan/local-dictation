import Foundation

/// One deterministic substitution made by a correction pass. `range` (via
/// `location`/`length`) is the span of the replacement text (`to`) in that pass's
/// OUTPUT string, in UTF-16 code units (`NSRange`/`CFRange` are UTF-16, never
/// bytes). `from` is the text that was replaced — what was actually heard — and
/// `to` is what it became.
///
/// Stored as `location`/`length` ints rather than a bare `NSRange` so the struct
/// is trivially `Codable` for the persisted correction log.
public struct Edit: Codable, Sendable, Equatable {
    /// UTF-16 offset of `to` in the pass output.
    public let location: Int
    /// UTF-16 length of `to`.
    public let length: Int
    public let from: String
    public let to: String
    public let source: Source

    /// Which correction pass produced the edit. An enum (not a raw string) so new
    /// cases don't break the persisted `CorrectionRecord`. Polish is deliberately
    /// absent — the LLM rewrite is not attributable token-by-token.
    public enum Source: String, Codable, Sendable {
        case strip, cleanup, mishearing, command, replacement
    }

    public var range: NSRange { NSRange(location: location, length: length) }

    public init(location: Int, length: Int, from: String, to: String, source: Source) {
        self.location = location
        self.length = length
        self.from = from
        self.to = to
        self.source = source
    }

    public init(range: NSRange, from: String, to: String, source: Source) {
        self.init(location: range.location, length: range.length, from: from, to: to, source: source)
    }
}

/// An ordered list of edits emitted by one or more correction passes.
public typealias EditSet = [Edit]

public extension Edit {
    /// Map edits from a pre-replacement string into the post-replacement output by
    /// shifting each edit's location forward by the length deltas of replacements
    /// that occur before it. `deltas` are `(location-in-old-string, length-delta)`.
    /// Used to rebase edits accumulated by an earlier pass when a later pass changes
    /// lengths ahead of them.
    static func shifting(_ edits: [Edit], by deltas: [(at: Int, delta: Int)]) -> [Edit] {
        guard !deltas.isEmpty else { return edits }
        return edits.map { edit in
            let shift = deltas.filter { $0.at < edit.location }.reduce(0) { $0 + $1.delta }
            return Edit(location: edit.location + shift, length: edit.length, from: edit.from, to: edit.to, source: edit.source)
        }
    }
}
