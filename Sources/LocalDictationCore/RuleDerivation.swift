import Foundation

/// Pure logic turning a review-panel gesture into a persisted correction. Both the
/// revert and teach paths feed the same downstream stores; the App layer just
/// applies what these return.
public enum RuleDerivation {
    /// Stable identity for a rejected built-in swap, used to key the suppression set.
    /// Symmetric: the apply path computes it from a built-in rule's pattern/`from`,
    /// and a reverted edit computes it from the heard text — both lowercased so a
    /// `"Clot"→"Claude"` instance matches the `"clot"` rule. Returns `nil` for user
    /// replacements (not suppressible) and for empty-text edits (e.g. a punctuation
    /// strip, which isn't a revertable swap).
    public static func suppressionIdentity(for edit: Edit) -> String? {
        suppressionIdentity(source: edit.source, from: edit.from, to: edit.to)
    }

    /// Identity from the raw parts — also called by the apply path with a built-in
    /// rule's pattern as `from`.
    public static func suppressionIdentity(source: Edit.Source, from: String, to: String) -> String? {
        guard source == .mishearing || source == .command else { return nil }
        let from = from.trimmingCharacters(in: .whitespaces).lowercased()
        guard !from.isEmpty, !to.isEmpty else { return nil }
        return "\(source.rawValue):\(from)→\(to)"
    }

    /// Build a teach rule from a heard span and the user's correction. Returns `nil`
    /// when the correction is blank or identical to what was heard (a no-op).
    public static func teach(heard: String, correction: String) -> TextReplacements.Rule? {
        let heard = heard.trimmingCharacters(in: .whitespaces)
        let correction = correction.trimmingCharacters(in: .whitespaces)
        guard !heard.isEmpty, !correction.isEmpty, heard != correction else { return nil }
        return TextReplacements.Rule(pattern: heard, replacement: correction)
    }
}
