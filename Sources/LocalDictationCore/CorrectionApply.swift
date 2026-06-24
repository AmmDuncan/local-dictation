import Foundation

/// Builds the running corrected text the review panel copies to the clipboard:
/// each fix replaces the FIRST occurrence of the old text with the new, composing
/// onto the previous result. Pure, so the composition is unit-testable without the
/// SwiftUI panel or a live clipboard.
public enum CorrectionApply {
    /// Replace the first occurrence of `expecting` with `replacement` in `text`.
    /// No-op when `replacement` is empty or `expecting` isn't present.
    public static func apply(_ replacement: String, for expecting: String, to text: String) -> String {
        guard !replacement.isEmpty, let range = text.range(of: expecting) else { return text }
        var out = text
        out.replaceSubrange(range, with: replacement)
        return out
    }
}
