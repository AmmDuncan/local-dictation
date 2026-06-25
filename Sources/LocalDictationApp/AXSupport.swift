import AppKit
import ApplicationServices

/// Small shared wrappers over the C accessibility API used by the context
/// readers (`CaretContext`, `WindowTextReader`). Best-effort: every call returns
/// nil/empty rather than throwing, so a missing attribute never breaks the
/// dictation path. The secure-field guard lives here so it's enforced identically
/// everywhere text is read.
enum AXSupport {
    /// String value of a single attribute, or nil if absent / not a string.
    @MainActor
    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    /// Child elements, or nil if none / not readable.
    @MainActor
    static func children(_ element: AXUIElement) -> [AXUIElement]? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
              let array = ref as? [AnyObject] else { return nil }
        return array.compactMap { item -> AXUIElement? in
            guard CFGetTypeID(item) == AXUIElementGetTypeID() else { return nil }
            return (item as! AXUIElement)
        }
    }

    /// True for a secure (password) field — its text is NEVER read or written.
    /// Privacy non-negotiable; checked by both role and subrole.
    @MainActor
    static func isSecure(_ element: AXUIElement) -> Bool {
        string(element, kAXRoleAttribute as String) == "AXSecureTextField"
            || string(element, kAXSubroleAttribute as String) == "AXSecureTextField"
    }

    /// The element's selected-text range (caret = a zero-length range), or nil.
    @MainActor
    static func selectedRange(_ element: AXUIElement) -> NSRange? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(ref as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    /// The currently selected text, or nil. Secure fields are never read.
    @MainActor
    static func selectedText(_ element: AXUIElement) -> String? {
        guard !isSecure(element) else { return nil }
        return string(element, kAXSelectedTextAttribute as String)
    }

    /// Set the selected-text range. Secure fields are never written. Returns success.
    @MainActor
    @discardableResult
    static func setSelectedRange(_ element: AXUIElement, _ range: NSRange) -> Bool {
        guard !isSecure(element) else { return false }
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }

    /// Replace the current selection with `text`. Secure fields are never written.
    @MainActor
    @discardableResult
    static func setSelectedText(_ element: AXUIElement, _ text: String) -> Bool {
        guard !isSecure(element) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }
}
