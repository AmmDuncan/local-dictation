import AppKit
import LocalDictationCore
import SwiftUI

/// Hosts `ReviewPanel` in a floating, key-able panel for the Door #1 (hotkey) path.
/// Unlike the passive HUD (`OverlayController`, a non-activating panel), this panel
/// deliberately takes key focus so its text fields work — a considered review moment.
@MainActor
final class ReviewPanelController {
    private var panel: NSPanel?

    func present(record: CorrectionRecord) {
        let panel = panel ?? makePanel()
        self.panel = panel
        let hosting = NSHostingView(rootView: ReviewPanel(
            record: record,
            onClose: { [weak panel] in panel?.orderOut(nil) },
            onSizeChange: { [weak panel] size in
                guard let panel, size.width > 100, size.height > 100 else { return }
                // Track the card's natural size as the sentence measure + selection
                // settle; skip no-op nudges so it converges instead of looping.
                if abs(panel.frame.width - size.width) > 1 || abs(panel.frame.height - size.height) > 1 {
                    panel.setContentSize(size)
                }
            }
        ))
        panel.contentView = hosting
        // Initial size from the card's fitting size; onSizeChange refines it after layout.
        let fit = hosting.fittingSize
        if fit.width > 100, fit.height > 100 { panel.setContentSize(fit) }
        if !panel.isVisible { panel.center() }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makePanel() -> NSPanel {
        // Borderless + clear so the SwiftUI card paints the whole surface (rounded
        // glass, accent bar, shadow) with no system title bar — matching the overlay.
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        // Background-drag is OFF: it made a tap with a hair of movement reposition the
        // window instead of selecting the word. The panel opens centered and is
        // transient, so losing drag-to-move is worth reliable word taps.
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        return panel
    }
}

/// A borderless/titled `NSPanel` is non-key by default; override so its fields can
/// take keyboard focus. (There is no style-mask flag for this.)
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
