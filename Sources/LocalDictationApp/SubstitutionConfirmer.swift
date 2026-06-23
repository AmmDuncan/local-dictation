import AppKit
import Foundation
import LocalDictationCore

/// Drives the `.reviewSubstitution` overlay phase. Shows the held transcript with
/// the proposed swaps inline and runs a countdown that auto-applies ALL swaps if
/// the user does nothing. The moment the user toggles a swap, the countdown is
/// cancelled — they've taken control, so nothing auto-applies and they resolve
/// explicitly via Apply / Keep. Mouse-driven: the overlay is a non-focused HUD,
/// so it can't capture keystrokes without stealing focus or swallowing the user's
/// typing — hands-free rejection is instead available afterwards via the ⌃⌥Z
/// review panel. The continuation resolves exactly once.
@MainActor
final class SubstitutionConfirmer: SubstitutionConfirming {
    private let overlay: OverlayController
    private var countdownTask: Task<Void, Never>?
    private var continuation: CheckedContinuation<SubstitutionDecision, Never>?
    /// Original proposals keyed by their 1-based id, so the accepted subset
    /// resolves back to swaps that still carry real UTF-16 ranges.
    private var swapsByID: [Int: ProposedSwap] = [:]

    init(overlay: OverlayController) { self.overlay = overlay }

    nonisolated func confirm(text: String, swaps: [ProposedSwap], countdown: TimeInterval) async -> SubstitutionDecision {
        await withCheckedContinuation { cont in
            Task { @MainActor in
                self.start(text: text, swaps: swaps, countdown: countdown, continuation: cont)
            }
        }
    }

    private func start(text: String, swaps: [ProposedSwap], countdown: TimeInterval,
                       continuation: CheckedContinuation<SubstitutionDecision, Never>) {
        // Defensive: a prior confirm must never be left dangling. finishCurrent
        // serializes dictations so re-entry shouldn't happen, but if it ever does,
        // resolve the NEW caller immediately rather than orphaning either
        // continuation (an orphaned CheckedContinuation hangs the workflow forever).
        guard self.continuation == nil else {
            continuation.resume(returning: .keepOriginal)
            return
        }
        self.continuation = continuation
        var byID: [Int: ProposedSwap] = [:]
        let pending = swaps.enumerated().map { idx, swap -> OverlayState.PendingSwap in
            byID[idx + 1] = swap
            return OverlayState.PendingSwap(id: idx + 1, range: swap.range, from: swap.from, to: swap.to)
        }
        swapsByID = byID
        overlay.showReviewSubstitution(text: text, swaps: pending, countdown: countdown)
        overlay.setReviewActions(
            toggle: { [weak self] id in self?.onToggle(id) },
            apply: { [weak self] in self?.resolveWithCurrentToggles() },
            keep: { [weak self] in self?.resolve(.keepOriginal) }
        )
        armCountdown(countdown)
    }

    /// First interaction cancels the countdown: the user has taken control, so
    /// nothing auto-applies — they decide explicitly via Apply / Keep.
    private func onToggle(_ id: Int) {
        cancelCountdown()
        overlay.togglePendingSwap(id: id)
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

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        overlay.markCountdownInactive()
    }

    private func resolveWithCurrentToggles() {
        let accepted = overlay.acceptedPendingSwaps
        let swaps = accepted.compactMap { swapsByID[$0.id] }
        guard !swaps.isEmpty else { resolve(.keepOriginal); return }
        resolve(.apply(swaps))
    }

    /// Resolve exactly once; tear down the timer and overlay.
    private func resolve(_ decision: SubstitutionDecision) {
        guard let cont = continuation else { return }
        continuation = nil
        countdownTask?.cancel()
        countdownTask = nil
        overlay.hide()
        cont.resume(returning: decision)
    }
}
