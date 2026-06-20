import AppKit
import ApplicationServices

/// Reads text around the caret in the focused app via the accessibility API:
/// a single preceding character (for smart-spacing insertion) and the preceding
/// line (for context-aware recognition/correction). Best-effort — returns nil
/// whenever it can't be determined (no accessibility trust, non-text element,
/// caret at the start). Secure (password) fields are NEVER read.
enum CaretContext {
    /// The character immediately before the caret, so insertion can continue a
    /// sentence in lowercase and space cleanly.
    @MainActor
    static func precedingCharacter() -> Character? {
        guard let focused = focusedTextElement(), focused.caret > 0 else { return nil }
        let element = focused.element
        let caret = focused.caret

        // Preferred: ask for just the one character before the caret (cheap even
        // in huge documents).
        var charRange = CFRange(location: caret - 1, length: 1)
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
            let i = caret - 1
            if i >= 0, i < units.count, let scalar = String(utf16CodeUnits: [units[i]], count: 1).first {
                return scalar
            }
        }
        return nil
    }

    /// The text immediately before the caret on the current line (up to
    /// `maxChars`), used as caret-proximate recognition/correction context — e.g.
    /// `git push origin ` right before a dictated branch name. Returns nil when it
    /// can't be read or the field is secure.
    @MainActor
    static func precedingText(maxChars: Int = 120) -> String? {
        guard let focused = focusedTextElement(), focused.caret > 0 else { return nil }
        let element = focused.element
        let caret = focused.caret
        let start = max(0, caret - maxChars)
        guard caret - start > 0 else { return nil }

        var text: String?
        var cfRange = CFRange(location: start, length: caret - start)
        if let axRange = AXValueCreate(.cfRange, &cfRange) {
            var stringRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element, kAXStringForRangeParameterizedAttribute as CFString, axRange, &stringRef
            ) == .success {
                text = stringRef as? String
            }
        }

        // Fallback: slice the full value at the caret.
        if text == nil {
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
               let full = valueRef as? String {
                let units = Array(full.utf16)
                let end = min(caret, units.count)
                if start < end {
                    let slice = Array(units[start..<end])
                    text = String(utf16CodeUnits: slice, count: slice.count)
                }
            }
        }

        guard var preceding = text, !preceding.isEmpty else { return nil }
        // Keep just the current line (after the last newline) — the command /
        // sentence being composed, not whatever scrolled above it.
        if let nl = preceding.lastIndex(where: { $0 == "\n" || $0 == "\r" }) {
            preceding = String(preceding[preceding.index(after: nl)...])
        }
        return preceding.isEmpty ? nil : preceding
    }

    /// The focused element's accessibility role (e.g. "AXTextArea"), for the
    /// context's `focusedElementDescription`. Nil for secure / non-text elements.
    @MainActor
    static func focusedRole() -> String? {
        guard let focused = focusedTextElement() else { return nil }
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused.element, kAXRoleAttribute as CFString, &ref) == .success else {
            return nil
        }
        return ref as? String
    }

    /// The focused text element plus its caret (selection start), or nil when
    /// there's no focused text element, no selection range, or the field is
    /// secure. Shared by every reader above so the secure-field guard is enforced
    /// in exactly one place.
    @MainActor
    private static func focusedTextElement() -> (element: AXUIElement, caret: Int)? {
        let system = AXUIElementCreateSystemWide()

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        let element = focusedRef as! AXUIElement

        // Privacy non-negotiable: never read a secure (password) field.
        guard !isSecure(element) else { return nil }

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &range) else { return nil }
        return (element, range.location)
    }

    @MainActor
    private static func isSecure(_ element: AXUIElement) -> Bool {
        func attr(_ name: String) -> String? {
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success else { return nil }
            return ref as? String
        }
        return attr(kAXRoleAttribute as String) == "AXSecureTextField"
            || attr(kAXSubroleAttribute as String) == "AXSecureTextField"
    }
}
