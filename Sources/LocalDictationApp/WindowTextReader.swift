import AppKit
import ApplicationServices

/// Reads visible text from the focused window's accessibility tree — the
/// surrounding context (terminal scrollback, the file you're editing, the
/// document around the caret) that biases recognition even when there's no
/// caret-preceding text. AX-first: structured, instant, and needs no Screen
/// Recording permission. Bounded so it stays fast and never dumps the whole
/// screen, and secure (password) fields are never read.
enum WindowTextReader {
    /// Walk the focused window's subtree collecting text node values, capped to
    /// `maxChars`/`maxNodes` and a wall-clock `budget` so it never stalls mic
    /// startup on a pathological tree. Returns nil when nothing readable is found
    /// (e.g. a GPU/Chromium window that exposes no AX text — the case OCR fills as
    /// an opt-in fallback).
    @MainActor
    static func visibleText(
        maxChars: Int = 1600, maxNodes: Int = 600, perNodeMax: Int = 1200, budget: TimeInterval = 0.03
    ) -> String? {
        guard let window = focusedWindow() else { return nil }
        let deadline = Date().addingTimeInterval(budget)

        var collected: [String] = []
        var charCount = 0
        // Breadth-first (shallower, usually more salient nodes first) over a queue
        // walked with a head index — popping the front of an Array is O(n), so an
        // index keeps the whole walk O(n).
        var queue: [AXUIElement] = [window]
        var head = 0
        while head < queue.count, head < maxNodes, charCount < maxChars, Date() < deadline {
            let element = queue[head]
            head += 1
            if AXSupport.isSecure(element) { continue }

            if let text = textValue(of: element, perNodeMax: perNodeMax) {
                collected.append(text)
                charCount += text.count
            }
            if let children = AXSupport.children(element) {
                queue.append(contentsOf: children)
            }
        }

        let joined = collected.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { return nil }
        return joined.count > maxChars ? String(joined.suffix(maxChars)) : joined
    }

    /// The focused application's focused window, via the system-wide focused
    /// application. Nil when there's no focused window (or AX isn't trusted).
    @MainActor
    private static func focusedWindow() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var appRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &appRef) == .success,
              let appRef, CFGetTypeID(appRef) == AXUIElementGetTypeID() else { return nil }
        let app = appRef as! AXUIElement

        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let winRef, CFGetTypeID(winRef) == AXUIElementGetTypeID() else { return nil }
        return (winRef as! AXUIElement)
    }

    /// Text carried by a node: the value of a text-bearing role (text area/field,
    /// static text). For a large value (a terminal buffer, a long document) keep
    /// the suffix — the most recent / caret-proximate content. Non-text roles
    /// (buttons, groups) contribute nothing themselves but are still descended.
    @MainActor
    private static func textValue(of element: AXUIElement, perNodeMax: Int) -> String? {
        guard let role = AXSupport.string(element, kAXRoleAttribute as String), isTextRole(role) else { return nil }
        let raw = AXSupport.string(element, kAXValueAttribute as String)
            ?? AXSupport.string(element, kAXTitleAttribute as String)
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > perNodeMax ? String(trimmed.suffix(perNodeMax)) : trimmed
    }

    private static func isTextRole(_ role: String) -> Bool {
        role == "AXTextArea" || role == "AXTextField" || role == "AXStaticText"
    }
}
