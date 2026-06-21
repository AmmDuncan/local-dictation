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

    /// True for a secure (password) field — its text is NEVER read. Privacy
    /// non-negotiable; checked by both role and subrole.
    @MainActor
    static func isSecure(_ element: AXUIElement) -> Bool {
        string(element, kAXRoleAttribute as String) == "AXSecureTextField"
            || string(element, kAXSubroleAttribute as String) == "AXSecureTextField"
    }
}
