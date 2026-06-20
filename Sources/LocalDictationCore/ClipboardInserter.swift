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

    public init(
        pasteboard: TextPasteboard = SystemPasteboard(),
        pasteCommandSender: PasteCommandSending = SystemPasteCommandSender(),
        restoreDelayNanoseconds: UInt64 = 150_000_000
    ) {
        self.pasteboard = pasteboard
        self.pasteCommandSender = pasteCommandSender
        self.restoreDelayNanoseconds = restoreDelayNanoseconds
    }

    public func insert(_ text: String) async throws {
        let previous = pasteboard.readString()
        pasteboard.writeString(text)
        // Restore on EVERY exit — including a thrown paste command — so a failed
        // paste never leaves the user's clipboard holding the transcript.
        defer {
            if let previous {
                pasteboard.writeString(previous)
            } else {
                pasteboard.clear()
            }
        }
        try pasteCommandSender.sendPasteCommand()
        try await Task.sleep(nanoseconds: restoreDelayNanoseconds)
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
