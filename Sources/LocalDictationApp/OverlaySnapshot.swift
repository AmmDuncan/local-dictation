import AppKit
import SwiftUI

/// Dev-only: `LocalDictation --snapshot-overlay` renders the real overlay SwiftUI
/// in each phase to PNGs and exits — runtime proof the views compose correctly
/// without needing a mic session. Never runs in normal launches (flag-gated).
@MainActor
enum OverlaySnapshot {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--snapshot-overlay") else { return }
        let dir = URL(fileURLWithPath: NSString(string:
            "~/Desktop/redesign-shots/local-dictation/compact-overlay-swift").expandingTildeInPath)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let cases: [(name: String, phase: DictationPhase, level: Double, detail: String)] = [
            ("listening", .listening, 0.62, ""),
            ("listening-hover", .listening, 0.62, ""),
            ("transcribing", .transcribing, 0, ""),
            ("done", .done, 0, "Hello world"),
            ("cancelled", .cancelled, 0, ""),
            ("error", .error, 0, "No speech detected"),
        ]
        for c in cases {
            let state = OverlayState()
            state.phase = c.phase
            state.level = c.level
            state.detail = c.detail
            // The hover case seeds the controls so the ✕/✓ render.
            let hover = c.name == "listening-hover"
            if hover { state.onCommit = {}; state.onCancel = {} }
            let view = ZStack {
                Color(hex: 0x1B1F22)  // desktop-ish backdrop so the pill + shadow read
                CompactOverlayView(state: state, previewHover: hover)
            }
            .frame(width: 340, height: 124)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            if let img = renderer.nsImage,
               let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("compact-\(c.name).png"))
                FileHandle.standardError.write(Data("wrote compact-\(c.name).png\n".utf8))
            }
        }
        exit(0)
    }
}
