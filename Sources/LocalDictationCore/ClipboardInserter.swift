import AppKit
import Foundation

public protocol TextInserting: Sendable {
    func insert(_ text: String) async throws
}

public protocol TextPasteboard: AnyObject, Sendable {
    func readString() -> String?
    func writeString(_ value: String)
    func clear()
}

public protocol PasteCommandSending: AnyObject, Sendable {
    func sendPasteCommand() throws
}

public enum PasteInsertionError: Error, Equatable, Sendable, CustomStringConvertible {
    case pasteCommandFailed
    case keystrokeFailed

    public var description: String {
        switch self {
        case .pasteCommandFailed:
            "The paste command could not be sent to the active app."
        case .keystrokeFailed:
            "The text could not be typed into the active app."
        }
    }
}

public struct ClipboardInserter: TextInserting {
    private let pasteboard: TextPasteboard
    private let pasteCommandSender: PasteCommandSending
    private let restoreDelayNanoseconds: UInt64

    // How long the transcript stays on the clipboard before the previous contents
    // are restored. The ⌘V is posted asynchronously — the frontmost app reads the
    // clipboard whenever ITS event loop processes the keystroke, and macOS exposes
    // no "paste consumed" signal (changeCount tracks writes, not reads). If the
    // restore fires first, the app pastes the OLD clipboard instead of the
    // dictation — observed live at 150ms on a busy machine (whisper decode had
    // just saturated the GPU). The window has to be generous; the restore guard
    // below makes a long window free.
    public init(
        pasteboard: TextPasteboard = SystemPasteboard(),
        pasteCommandSender: PasteCommandSending = SystemPasteCommandSender(),
        restoreDelayNanoseconds: UInt64 = 800_000_000
    ) {
        self.pasteboard = pasteboard
        self.pasteCommandSender = pasteCommandSender
        self.restoreDelayNanoseconds = restoreDelayNanoseconds
    }

    public func insert(_ text: String) async throws {
        await ClipboardRestorer.shared.begin(
            text: text, currentClipboard: pasteboard.readString()
        )
        pasteboard.writeString(text)
        do {
            try pasteCommandSender.sendPasteCommand()
        } catch {
            // A failed paste never leaves the transcript on the clipboard.
            await ClipboardRestorer.shared.finish(pasteboard: pasteboard, text: text)
            throw error
        }
        // The restore runs detached so insert() returns as soon as ⌘V is posted —
        // the success overlay and the next dictation never wait out the window.
        let pasteboard = pasteboard
        let delay = restoreDelayNanoseconds
        Task.detached {
            try? await Task.sleep(nanoseconds: delay)
            await ClipboardRestorer.shared.finish(pasteboard: pasteboard, text: text)
        }
    }
}

/// Serializes the deferred clipboard restores across dictations. Holding the
/// state in one place means a dictation that starts while the previous restore
/// window is still open inherits the ORIGINAL clipboard (what the user had
/// before dictating at all), instead of mistaking the previous transcript for
/// it — and a superseded restore quietly stands down.
public actor ClipboardRestorer {
    public static let shared = ClipboardRestorer()

    private var pendingText: String?
    private var pendingOriginal: String?

    /// Drop any pending restore (tests only — production state must flow
    /// through begin/finish).
    public func reset() {
        pendingText = nil
        pendingOriginal = nil
    }

    /// Register `text` as the clipboard's incoming content. What gets restored
    /// later is the still-pending original when a restore window is open,
    /// otherwise the clipboard as it stands now.
    public func begin(text: String, currentClipboard: String?) {
        pendingOriginal = pendingText != nil ? pendingOriginal : currentClipboard
        pendingText = text
    }

    /// Restore the original clipboard — but only if `text` is still the pending
    /// insert (a newer dictation supersedes this restore) AND the clipboard still
    /// holds our transcript (anything newer, like a user copy or a clipboard
    /// manager rewrite, must never be clobbered). Idempotent.
    public func finish(pasteboard: TextPasteboard, text: String) {
        guard pendingText == text else { return }
        let original = pendingOriginal
        pendingText = nil
        pendingOriginal = nil
        guard pasteboard.readString() == text else { return }
        if let original {
            pasteboard.writeString(original)
        } else {
            pasteboard.clear()
        }
    }
}

public final class SystemPasteboard: TextPasteboard, @unchecked Sendable {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public func readString() -> String? {
        pasteboard.string(forType: .string)
    }

    public func writeString(_ value: String) {
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    public func clear() {
        pasteboard.clearContents()
    }
}

public final class SystemPasteCommandSender: PasteCommandSending, @unchecked Sendable {
    private let keyCodeV: CGKeyCode = 9

    public init() {}

    public func sendPasteCommand() throws {
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCodeV, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCodeV, keyDown: false)
        else {
            throw PasteInsertionError.pasteCommandFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
