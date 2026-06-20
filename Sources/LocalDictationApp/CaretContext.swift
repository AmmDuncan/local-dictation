import AppKit
import ApplicationServices

/// Reads the character immediately before the text caret in the focused app via
/// the accessibility API, so insertion can continue a sentence in lowercase and
/// space cleanly. Best-effort: returns nil whenever it can't be determined (no
/// accessibility trust, non-text field, caret at the start), and the caller then
/// inserts the text unchanged.
enum CaretContext {
    @MainActor
    static func precedingCharacter() -> Character? {
        let system = AXUIElementCreateSystemWide()

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        let element = focusedRef as! AXUIElement

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() else { return nil }
        let axRange = rangeRef as! AXValue
        var range = CFRange()
        guard AXValueGetValue(axRange, .cfRange, &range), range.location > 0 else { return nil }

        // Preferred: ask for just the one character before the caret (cheap even
        // in huge documents).
        var charRange = CFRange(location: range.location - 1, length: 1)
        if let axCharRange = AXValueCreate(.cfRange, &charRange) {
            var stringRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element, kAXStringForRangeParameterizedAttribute as CFString, axCharRange, &stringRef
            ) == .success, let s = stringRef as? String, let c = s.last {
                return c
            }
        }

        // Fallback: read the whole value and index into it.
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let full = valueRef as? String {
            let units = Array(full.utf16)
            let i = range.location - 1
            if i >= 0, i < units.count, let scalar = String(utf16CodeUnits: [units[i]], count: 1).first {
                return scalar
            }
        }
        return nil
    }
}
