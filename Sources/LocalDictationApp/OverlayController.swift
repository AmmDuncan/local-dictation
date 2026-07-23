import AppKit
import Observation
import SwiftUI

/// The states the dictation overlay can show.
enum DictationPhase: Equatable {
    case listening
    case transcribing
    case reviewSubstitution
    case done
    case error
    case cancelled
}

@MainActor
@Observable
final class OverlayState {
    var phase: DictationPhase = .listening
    var title: String = "Listening"
    var detail: String = ""
    var level: Double = 0
    var actionTitle: String?
    /// Ranges (UTF-16, in `detail`) of words the system swapped, for the "Typed"
    /// card to flat-underline. Empty unless the `.done` card has reviewable swaps.
    var swappedRanges: [NSRange] = []
    /// One-time first-run "Polished on-device" proof on the `.done` card. True only
    /// for the first few applied polishes after polish is enabled / the model swaps,
    /// then permanently false — steady-state success stays silent.
    var polishStreak: Bool = false

    /// Proposed swaps for the .reviewSubstitution phase, with per-swap accepted flag.
    var pendingSwaps: [PendingSwap] = []
    var countdownTotal: TimeInterval = 5
    var countdownRemaining: TimeInterval = 5
    /// The held transcript shown in the review card (swaps rendered inline).
    var reviewText: String = ""
    /// True while the auto-apply countdown runs; flips false the moment the user
    /// toggles a swap (manual mode — resolve via Apply / Keep).
    var countdownActive: Bool = true

    struct PendingSwap: Identifiable, Equatable {
        let id: Int            // 1-based index, shown as the row number
        let range: NSRange     // UTF-16 span in `reviewText`, for inline underlining
        let from: String
        let to: String
        var accepted: Bool = true
    }

    @ObservationIgnored var action: (() -> Void)?
    /// Compact HUD hover/keyboard controls: commit = stop where it is + insert now;
    /// cancel = discard. Set during listening, cleared otherwise.
    @ObservationIgnored var onCommit: (() -> Void)?
    @ObservationIgnored var onCancel: (() -> Void)?
    @ObservationIgnored var reviewToggle: ((Int) -> Void)?
    @ObservationIgnored var reviewApply: (() -> Void)?
    @ObservationIgnored var reviewKeep: (() -> Void)?
}

@MainActor
final class OverlayController {
    private let state = OverlayState()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private var levelTimer: Timer?
    private var levelProvider: (() -> Double)?

    private static let originDefaultsKey = "overlayOrigin"

    /// Transparent breathing room around the visible card so the SwiftUI drop
    /// shadow + halo render in full instead of being clipped by the panel's
    /// rectangular bounds (which showed as a hard "box" cutting off the shadow).
    /// `OverlayView` pads by exactly this; the panel size includes it on every
    /// edge. Keep the two in sync.
    static let shadowMargin: CGFloat = 40
    private static let cardWidth: CGFloat = 384
    // Compact HUD: one fixed pill size across phases (the pill hugs its content
    // and centers). Wide enough for the widest state ("Transcribing").
    private static let compactCardWidth: CGFloat = 208
    private static let compactCardHeight: CGFloat = 34

    /// The overlay treatment in effect, read fresh so a Settings change applies on
    /// the next dictation. `present` rebuilds the panel when this flips.
    private var style: OverlayStyle { AppSettingsSnapshot.current.overlay }
    /// The style the current panel was built for, so we know when to rebuild.
    private var hostedStyle: OverlayStyle?

    private func panelWidth(for style: OverlayStyle) -> CGFloat {
        let card = style == .compact ? Self.compactCardWidth : Self.cardWidth
        return card + Self.shadowMargin * 2
    }

    /// Visible card height per phase. The panel adds `shadowMargin` top + bottom.
    private func cardHeight(for phase: DictationPhase) -> CGFloat {
        switch phase {
        case .listening: 226  // taller for the 3-line tailing transcript + draft eyebrow
        case .transcribing: 130
        case .reviewSubstitution: min(400, 234 + CGFloat(max(1, state.pendingSwaps.count)) * 26)
        case .done: 220
        case .error: 194
        case .cancelled: 120
        }
    }

    private func panelHeight(for phase: DictationPhase) -> CGFloat {
        if style == .compact { return Self.compactCardHeight + Self.shadowMargin * 2 }
        return cardHeight(for: phase) + Self.shadowMargin * 2
    }

    func showListening(
        detail: String,
        levelProvider: @escaping () -> Double,
        onCommit: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.levelProvider = levelProvider
        state.onCommit = onCommit
        state.onCancel = onCancel
        present(phase: .listening, title: "Listening", detail: detail)
        startLevelUpdates()
    }

    func showTranscribing() {
        stopLevelUpdates()
        present(phase: .transcribing, title: "Transcribing", detail: "Private, on your Mac")
    }

    func showDone(text: String, swappedRanges: [NSRange] = [], polishStreak: Bool = false) {
        stopLevelUpdates()
        state.swappedRanges = swappedRanges
        state.polishStreak = polishStreak
        present(phase: .done, title: "Typed", detail: text)
    }

    func showError(message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        stopLevelUpdates()
        state.actionTitle = actionTitle
        state.action = action
        present(phase: .error, title: "Couldn't dictate", detail: message)
    }

    func showCancelled() {
        stopLevelUpdates()
        present(phase: .cancelled, title: "Cancelled", detail: "Nothing was typed")
    }

    func showReviewSubstitution(text: String, swaps: [OverlayState.PendingSwap], countdown: TimeInterval) {
        stopLevelUpdates()
        state.reviewText = text
        state.pendingSwaps = swaps
        state.countdownTotal = countdown
        state.countdownRemaining = countdown
        state.countdownActive = true
        present(phase: .reviewSubstitution, title: "Review swaps", detail: "")
    }

    /// Mutate the live overlay state for the .reviewSubstitution phase. The
    /// confirmer ticks the countdown and toggles swaps through these.
    func updateCountdownRemaining(_ remaining: TimeInterval) {
        guard state.phase == .reviewSubstitution else { return }
        state.countdownRemaining = remaining
    }

    /// Wire the review overlay's mouse interactions back to the confirmer.
    func setReviewActions(toggle: @escaping (Int) -> Void,
                          apply: @escaping () -> Void,
                          keep: @escaping () -> Void) {
        guard state.phase == .reviewSubstitution else { return }
        state.reviewToggle = toggle
        state.reviewApply = apply
        state.reviewKeep = keep
    }

    /// The user engaged a toggle — stop the auto-apply countdown (manual mode).
    func markCountdownInactive() {
        guard state.phase == .reviewSubstitution else { return }
        state.countdownActive = false
    }

    func togglePendingSwap(id: Int) {
        guard state.phase == .reviewSubstitution,
              let idx = state.pendingSwaps.firstIndex(where: { $0.id == id }) else { return }
        state.pendingSwaps[idx].accepted.toggle()
    }

    /// The swaps still toggled on, in id order.
    var acceptedPendingSwaps: [OverlayState.PendingSwap] {
        state.pendingSwaps.filter(\.accepted)
    }

    #if DEBUG
    // Headless smoke hooks: invoke the EXACT closures the overlay's tap gestures
    // and buttons call, so the confirmer state machine can be driven without a
    // mouse (computer-use can't target this app). See runReviewSubstitutionLive.
    var debugCountdownActive: Bool { state.countdownActive }
    func simulateReviewToggle(id: Int) { state.reviewToggle?(id) }
    func simulateReviewApply() { state.reviewApply?() }
    func simulateReviewKeep() { state.reviewKeep?() }
    #endif

    /// Update the rolling partial transcript without changing phase.
    func updateListeningDetail(_ detail: String) {
        guard state.phase == .listening else { return }
        state.detail = detail
    }

    /// How often to re-check the cursor while it parks on the overlay, and the
    /// beat after it leaves before hiding (so a pass-through doesn't flicker).
    private static let hoverPollSeconds: TimeInterval = 0.15
    private static let hoverExitGraceSeconds: TimeInterval = 0.3

    /// `holdWhileHovered` is opt-in per call site: right for the done and error
    /// overlays (the user is reading them), wrong for sub-second blips like
    /// no-speech, where a parked cursor would hold a toast open indefinitely.
    func hide(after seconds: TimeInterval = 0, holdWhileHovered: Bool = false) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            if seconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            // The cursor resting on the overlay means the user is reading it —
            // hold until it leaves (plus a short grace). Checked via the global
            // mouse position, NOT by accepting mouse events, so the panel stays
            // click-through.
            while holdWhileHovered, !Task.isCancelled, self?.cursorIsOverPanel == true {
                try? await Task.sleep(nanoseconds: UInt64(Self.hoverPollSeconds * 1_000_000_000))
                if self?.cursorIsOverPanel == false {
                    try? await Task.sleep(nanoseconds: UInt64(Self.hoverExitGraceSeconds * 1_000_000_000))
                }
            }
            guard !Task.isCancelled else { return }
            self?.stopLevelUpdates()
            self?.panel?.orderOut(nil)
        }
    }

    /// NSEvent.mouseLocation and NSWindow.frame share the same bottom-left
    /// screen coordinate space.
    private var cursorIsOverPanel: Bool {
        guard let panel, panel.isVisible else { return false }
        return panel.frame.contains(NSEvent.mouseLocation)
    }

    private func present(phase: DictationPhase, title: String, detail: String) {
        hideTask?.cancel()
        if phase != .error {
            state.actionTitle = nil
            state.action = nil
        }
        if phase != .listening { state.onCommit = nil; state.onCancel = nil }
        if phase != .done { state.swappedRanges = []; state.polishStreak = false }
        if phase != .reviewSubstitution {
            state.pendingSwaps = []
            state.reviewText = ""
            state.reviewToggle = nil
            state.reviewApply = nil
            state.reviewKeep = nil
            state.countdownActive = true
        }
        state.phase = phase
        state.title = title
        state.detail = detail

        // Rebuild the panel if the overlay style changed since it was built (the
        // compact pill and the standard card host different views + sizes).
        if let existing = panel, hostedStyle != style {
            existing.orderOut(nil)
            panel = nil
        }
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setContentSize(NSSize(width: panelWidth(for: style), height: panelHeight(for: phase)))
        // The compact pill's hover controls (✕ / ✓) need clicks while listening.
        let compactListening = style == .compact && phase == .listening
        panel.ignoresMouseEvents = phase != .error && phase != .reviewSubstitution && !compactListening
        // The compact HUD is fixed (not draggable). Its ✕/✓ still receive clicks
        // (ignoresMouseEvents handled above). The standard card stays draggable;
        // the review card (chip toggles) opts out of drag-by-background.
        panel.isMovableByWindowBackground = phase != .reviewSubstitution && style != .compact
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
        hostedStyle = style
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth(for: style), height: panelHeight(for: .listening)),
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
        let hosting: NSHostingView<AnyView>
        if style == .compact {
            hosting = NSHostingView(rootView: AnyView(CompactOverlayView(state: state)))
        } else {
            hosting = NSHostingView(rootView: AnyView(OverlayView(state: state)))
        }
        hosting.layer?.backgroundColor = .clear
        panel.contentView = hosting

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                guard let self, let panel else { return }
                // The compact HUD is fixed (not draggable) and always opens at its
                // computed default, so it never persists a position.
                guard self.style == .standard else { return }
                let origin = panel.frame.origin
                UserDefaults.standard.set([origin.x, origin.y], forKey: Self.originDefaultsKey)
            }
        }
        return panel
    }

    private func positionIfNeeded(_ panel: NSPanel) {
        // The compact HUD is fixed: always the computed default, never a saved
        // origin. Only the standard card restores a dragged position.
        if style == .standard,
           let stored = UserDefaults.standard.array(forKey: Self.originDefaultsKey) as? [Double],
           stored.count == 2,
           NSScreen.screens.contains(where: { $0.frame.contains(NSPoint(x: stored[0], y: stored[1])) }) {
            panel.setFrameOrigin(NSPoint(x: stored[0], y: stored[1]))
            return
        }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let x = frame.midX - panel.frame.width / 2
        // Compact HUD sits in the lower third (~75% down), centered — near where the
        // cursor/typing is, out of the way. The standard card keeps its near-top
        // placement. Either can be dragged anywhere (the move persists).
        let y = style == .compact
            ? frame.minY + frame.height * 0.18
            : frame.maxY - panel.frame.height - 44
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
