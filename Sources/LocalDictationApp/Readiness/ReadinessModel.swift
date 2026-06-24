import AVFoundation
import ApplicationServices
import Foundation
import Observation

enum ReadinessState {
    case ok
    case warn
    case fail

    /// Spoken status for VoiceOver, so state isn't conveyed by colour alone.
    var spokenStatus: String {
        switch self {
        case .ok: "ready"
        case .warn: "needs attention"
        case .fail: "not set up"
        }
    }
}

struct ReadinessItem: Identifiable {
    let id: String
    let label: String
    let state: ReadinessState
    let detail: String?
}

/// Snapshot of whether the app can actually dictate right now: binary present,
/// model present, and the two permissions granted. Re-checked when Settings
/// appears and whenever the app reactivates, since permissions can change
/// outside the app.
@MainActor
@Observable
final class ReadinessModel {
    private(set) var items: [ReadinessItem] = []

    var allReady: Bool {
        items.allSatisfy { $0.state == .ok }
    }

    func refresh() {
        let settings = AppSettingsSnapshot.current
        items = [
            whisperItem(settings),
            modelItem(settings),
            microphoneItem(),
            accessibilityItem(settings),
            polishItem(settings)
        ]
    }

    /// Pull-only standing health for the optional LLM polish, plus the lifetime
    /// tally that answers "is it actually doing anything?" without any per-dictation
    /// signal. `.ok` when off or ready (so it never nags the menu-bar problem strip);
    /// `.warn` only when polish is ON but the model file is missing — the dangerous
    /// "enabled but every dictation is silently raw" case the user must be able to see.
    private func polishItem(_ settings: AppSettingsSnapshot) -> ReadinessItem {
        guard settings.polishWithAI else {
            return ReadinessItem(id: "polish", label: "Polish · off", state: .ok,
                                 detail: "Enable in Settings to clean up formatting")
        }
        let path = settings.polishModelPath.expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else {
            return ReadinessItem(id: "polish", label: "Polish · unavailable", state: .warn,
                                 detail: "Model not loaded — dictation still works, just unpolished")
        }
        // The lifetime tally lives in the LABEL: HealthStripView renders the pill
        // label for .ok items (detail shows only for problems), and a counter that
        // has visibly moved is the durable, pull-only proof that polish runs.
        let d = UserDefaults.standard
        let applied = d.integer(forKey: AppSettingsKeys.polishAppliedCount)
        let heldBack = d.integer(forKey: AppSettingsKeys.polishHeldBackCount)
        let label: String
        if applied > 0 {
            label = "Polish · \(PolishProof.grouped(applied)) polished"
                + (heldBack > 0 ? " · \(PolishProof.grouped(heldBack)) held back" : "")
        } else if heldBack > 0 {
            label = "Polish · \(PolishProof.grouped(heldBack)) held back"
        } else {
            label = "Polish · ready"
        }
        return ReadinessItem(id: "polish", label: label, state: .ok, detail: nil)
    }

    private func whisperItem(_ settings: AppSettingsSnapshot) -> ReadinessItem {
        let path = WhisperLocator.resolved(configured: settings.whisperExecutablePath)
        let ok = FileManager.default.isExecutableFile(atPath: path)
        return ReadinessItem(
            id: "whisper",
            label: "Speech engine",
            state: ok ? .ok : .fail,
            detail: ok ? nil : "Install with: brew install whisper-cpp"
        )
    }

    private func modelItem(_ settings: AppSettingsSnapshot) -> ReadinessItem {
        let path = settings.modelPath.expandingTildeInPath
        let ok = FileManager.default.fileExists(atPath: path)
        let name = (path as NSString).lastPathComponent
            .replacingOccurrences(of: "ggml-", with: "")
            .replacingOccurrences(of: ".bin", with: "")
        return ReadinessItem(
            id: "model",
            label: ok ? "Model · \(name)" : "Model",
            state: ok ? .ok : .fail,
            detail: ok ? nil : "No model file — download one below"
        )
    }

    private func microphoneItem() -> ReadinessItem {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return ReadinessItem(id: "mic", label: "Microphone", state: .ok, detail: nil)
        case .notDetermined:
            return ReadinessItem(id: "mic", label: "Microphone", state: .warn, detail: "Will be requested on first use")
        default:
            return ReadinessItem(id: "mic", label: "Microphone", state: .fail, detail: "Enable in System Settings › Privacy")
        }
    }

    private func accessibilityItem(_ settings: AppSettingsSnapshot) -> ReadinessItem {
        guard settings.pasteOnRelease else {
            return ReadinessItem(id: "ax", label: "Accessibility", state: .ok, detail: "Not needed (paste off)")
        }
        let trusted = AXIsProcessTrusted()
        return ReadinessItem(
            id: "ax",
            label: "Accessibility",
            state: trusted ? .ok : .warn,
            detail: trusted ? nil : "Grant for paste insertion"
        )
    }
}
