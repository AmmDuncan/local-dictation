import AppKit
import LocalDictationCore

/// Experimental live re-insertion via AX select-verify-replace. Captures the target
/// field + the text we inserted at insert time (before the review panel steals key
/// focus); when the user applies a correction, selects the inserted span, reads it
/// back, and replaces it only if it still matches (see `ReinsertionDecision`). Safe
/// by construction — a mismatch aborts and the field is left untouched.
@MainActor
struct LiveReinserter {
    let element: AXUIElement
    let insertedText: String
    let insertedRange: NSRange

    /// Capture the focused field and the span the just-inserted text occupies (the
    /// `insertedText` ends at the caret). Returns nil if there's no focused field,
    /// no caret, or the math doesn't line up.
    static func capture(insertedText: String) -> LiveReinserter? {
        guard !insertedText.isEmpty,
              let element = AXSupport.focusedElement(),
              let caret = AXSupport.selectedRange(element) else { return nil }
        let length = (insertedText as NSString).length
        let location = caret.location - length
        guard location >= 0 else { return nil }
        return LiveReinserter(
            element: element,
            insertedText: insertedText,
            insertedRange: NSRange(location: location, length: length)
        )
    }

    /// Select the inserted span, read it back, and replace it with `newText` only if
    /// it still exactly matches what we inserted. Returns true on a successful replace.
    @discardableResult
    func replace(with newText: String) -> Bool {
        guard AXSupport.setSelectedRange(element, insertedRange) else { return false }
        guard ReinsertionDecision.canReplace(inserted: insertedText, readBack: AXSupport.selectedText(element)) else {
            return false
        }
        return AXSupport.setSelectedText(element, newText)
    }
}
