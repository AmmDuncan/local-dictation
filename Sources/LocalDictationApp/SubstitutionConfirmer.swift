import AppKit
import Foundation
import LocalDictationCore

/// Drives the `.reviewSubstitution` overlay phase: presents the proposed swaps,
/// ticks the countdown, maps number keys to per-swap toggles, ↵ to apply now,
/// esc to keep the original, and a timeout to apply the current toggle state.
/// The continuation resolves exactly once.
@MainActor
final class SubstitutionConfirmer: SubstitutionConfirming {
    private let overlay: OverlayController
    private var countdownTask: Task<Void, Never>?
    private var keyMonitor: Any?
    private var continuation: CheckedContinuation<SubstitutionDecision, Never>?
    /// Original proposals keyed by their 1-based id, so the accepted subset
    /// resolves back to swaps that still carry real UTF-16 ranges.
    private var swapsByID: [Int: ProposedSwap] = [:]

    init(overlay: OverlayController) { self.overlay = overlay }

    nonisolated func confirm(text: String, swaps: [ProposedSwap], countdown: TimeInterval) async -> SubstitutionDecision {
        await withCheckedContinuation { cont in
            Task { @MainActor in
                self.start(swaps: swaps, countdown: countdown, continuation: cont)
            }
        }
    }

    private func start(swaps: [ProposedSwap], countdown: TimeInterval, continuation: CheckedContinuation<SubstitutionDecision, Never>) {
        self.continuation = continuation
        var byID: [Int: ProposedSwap] = [:]
        let pending = swaps.enumerated().map { idx, swap -> OverlayState.PendingSwap in
            byID[idx + 1] = swap
            return OverlayState.PendingSwap(id: idx + 1, from: swap.from, to: swap.to)
        }
        swapsByID = byID
        overlay.showReviewSubstitution(swaps: pending, countdown: countdown)
        overlay.setReviewApplyAction { [weak self] in self?.resolveWithCurrentToggles() }
        armKeyMonitor()
        armCountdown(countdown)
    }

    private func armCountdown(_ countdown: TimeInterval) {
        let tickInterval: TimeInterval = 0.05
        countdownTask = Task { @MainActor [weak self] in
            var remaining = countdown
            while remaining > 0 {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: UInt64(tickInterval * 1_000_000_000))
                if Task.isCancelled { return }
                remaining = max(0, remaining - tickInterval)
                self?.overlay.updateCountdownRemaining(remaining)
            }
            self?.resolveWithCurrentToggles()
        }
    }

    private func armKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    /// Returns true if the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53:  // esc
            resolve(.keepOriginal)
            return true
        case 36, 76:  // return, keypad enter
            resolveWithCurrentToggles()
            return true
        default:
            if let chars = event.charactersIgnoringModifiers, let n = Int(chars), n >= 1 {
                overlay.togglePendingSwap(id: n)
                return true
            }
            return false
        }
    }

    private func resolveWithCurrentToggles() {
        let accepted = overlay.acceptedPendingSwaps
        guard !accepted.isEmpty else { resolve(.keepOriginal); return }
        // Map the still-accepted pending swaps (by id) back to the original
        // proposals, which carry the real UTF-16 ranges needed to apply them.
        let swaps = accepted.compactMap { swapsByID[$0.id] }
        guard !swaps.isEmpty else { resolve(.keepOriginal); return }
        resolve(.apply(swaps))
    }

    /// Resolve exactly once; tear down the timer, key monitor, and overlay.
    private func resolve(_ decision: SubstitutionDecision) {
        guard let cont = continuation else { return }
        continuation = nil
        countdownTask?.cancel()
        countdownTask = nil
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        overlay.hide()
        cont.resume(returning: decision)
    }
}
