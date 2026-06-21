import Foundation

/// Pure tap-to-select logic for the review panel's word tokens, factored out of the
/// SwiftUI view so its grow / shrink / toggle / adjacent / separated branches are
/// unit-testable. Selections are always a single contiguous span of token indices.
public enum SpanSelection {
    /// New selection after tapping `index`, given the `current` span (nil = none).
    /// Returns nil when the tap clears the selection.
    ///
    /// - No selection → selects the tapped word.
    /// - Tapping a word touching the span (an immediate neighbour) → grows the span.
    /// - Tapping a word separated from the span → starts a fresh single selection.
    /// - Tapping a word already in the span → toggles it off: clears the last word,
    ///   shrinks from whichever end was tapped, or re-anchors on a middle tap.
    public static func tap(current: ClosedRange<Int>?, index: Int) -> ClosedRange<Int>? {
        guard let range = current else { return index...index }
        if range.contains(index) {
            if range.count == 1 { return nil }                                                // last word → clear
            if index == range.lowerBound { return (range.lowerBound + 1)...range.upperBound }  // drop the first
            if index == range.upperBound { return range.lowerBound...(range.upperBound - 1) }  // drop the last
            return index...index                                                              // middle → collapse
        }
        if index == range.lowerBound - 1 || index == range.upperBound + 1 {
            return Swift.min(range.lowerBound, index)...Swift.max(range.upperBound, index)     // adjacent → grow
        }
        return index...index                                                                  // separated → fresh
    }
}
