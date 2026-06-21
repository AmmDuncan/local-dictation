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
        panel.contentView = NSHostingView(rootView: ReviewPanel(record: record) { [weak panel] in
            panel?.orderOut(nil)
        })
        if !panel.isVisible { panel.center() }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }
}

/// A borderless/titled `NSPanel` is non-key by default; override so its fields can
/// take keyboard focus. (There is no style-mask flag for this.)
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
