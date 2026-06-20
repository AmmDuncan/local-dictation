import AppKit
import Observation
import SwiftUI

/// The four states the dictation overlay can show.
enum DictationPhase: Equatable {
    case listening
    case transcribing
    case done
    case error
}

@MainActor
@Observable
final class OverlayState {
    var phase: DictationPhase = .listening
    var title: String = "Listening"
    var detail: String = ""
    var level: Double = 0
    var actionTitle: String?

    @ObservationIgnored var action: (() -> Void)?
}

@MainActor
final class OverlayController {
    private let state = OverlayState()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private var levelTimer: Timer?
    private var levelProvider: (() -> Double)?

    private static let originDefaultsKey = "overlayOrigin"
    private let panelWidth: CGFloat = 404

    private func height(for phase: DictationPhase) -> CGFloat {
        switch phase {
        case .listening: 196
        case .transcribing: 150
        case .done: 240
        case .error: 214
        }
    }

    func showListening(detail: String, levelProvider: @escaping () -> Double) {
        self.levelProvider = levelProvider
        present(phase: .listening, title: "Listening", detail: detail)
        startLevelUpdates()
    }

    func showTranscribing() {
        stopLevelUpdates()
        present(phase: .transcribing, title: "Transcribing", detail: "Private, on your Mac")
    }

    func showDone(text: String) {
        stopLevelUpdates()
        present(phase: .done, title: "Typed", detail: text)
    }

    func showError(message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        stopLevelUpdates()
        state.actionTitle = actionTitle
        state.action = action
        present(phase: .error, title: "Couldn't dictate", detail: message)
    }

    /// Update the rolling partial transcript without changing phase.
    func updateListeningDetail(_ detail: String) {
        guard state.phase == .listening else { return }
        state.detail = detail
    }

    func hide(after seconds: TimeInterval = 0) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            if seconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            self?.stopLevelUpdates()
            self?.panel?.orderOut(nil)
        }
    }

    private func present(phase: DictationPhase, title: String, detail: String) {
        hideTask?.cancel()
        if phase != .error {
            state.actionTitle = nil
            state.action = nil
        }
        state.phase = phase
        state.title = title
        state.detail = detail

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setContentSize(NSSize(width: panelWidth, height: height(for: phase)))
        panel.ignoresMouseEvents = phase != .error
        positionIfNeeded(panel)
        panel.orderFrontRegardless()
    }

    private func startLevelUpdates() {
        stopLevelUpdates()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let provider = self.levelProvider else { return }
                let target = provider()
                let current = self.state.level
                let smoothing = target > current ? 0.5 : 0.2
                self.state.level = current + (target - current) * smoothing
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        levelTimer = timer
    }

    private func stopLevelUpdates() {
        levelTimer?.invalidate()
        levelTimer = nil
        state.level = 0
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: height(for: .listening)),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hasShadow = false  // SwiftUI draws the rounded shadow; the window shadow is square.
        panel.backgroundColor = .clear
        panel.isOpaque = false
        let hosting = NSHostingView(rootView: OverlayView(state: state))
        hosting.layer?.backgroundColor = .clear
        panel.contentView = hosting

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak panel] _ in
            MainActor.assumeIsolated {
                guard let panel else { return }
                let origin = panel.frame.origin
                UserDefaults.standard.set([origin.x, origin.y], forKey: Self.originDefaultsKey)
            }
        }
        return panel
    }

    private func positionIfNeeded(_ panel: NSPanel) {
        if let stored = UserDefaults.standard.array(forKey: Self.originDefaultsKey) as? [Double],
           stored.count == 2,
           NSScreen.screens.contains(where: { $0.frame.contains(NSPoint(x: stored[0], y: stored[1])) }) {
            panel.setFrameOrigin(NSPoint(x: stored[0], y: stored[1]))
            return
        }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let x = frame.midX - panel.frame.width / 2
        let y = frame.maxY - panel.frame.height - 44
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
