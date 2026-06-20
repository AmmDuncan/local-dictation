import AppKit
import LocalDictationCore

/// Real `ContextProvider` backed by NSWorkspace + the accessibility API. Gathers,
/// on-device and transiently, the signals that let recognition and command-mode
/// correction know *where* you're dictating: the frontmost app name, the focused
/// element's role, and the caret-preceding text.
///
/// Privacy: AX-first (no Screen Recording permission — accessibility is already
/// held for paste insertion); secure/password fields are never read (enforced in
/// `CaretContext`); and the returned `DictationContext` is consumed for a single
/// dictation and dropped — never logged or persisted.
struct AccessibilityContextProvider: ContextProvider {
    func currentContext() async -> DictationContext {
        await MainActor.run { Self.gather() }
    }

    @MainActor
    static func gather(includeVisibleText: Bool = true) -> DictationContext {
        DictationContext(
            activeApplicationName: NSWorkspace.shared.frontmostApplication?.localizedName,
            focusedElementDescription: CaretContext.focusedRole(),
            precedingText: CaretContext.precedingText(),
            // Surrounding window text (AX-first) — biases recognition even when
            // there's no caret-preceding text. Bounded; nil for text-less apps.
            visibleText: includeVisibleText ? WindowTextReader.visibleText() : nil
        )
    }
}
