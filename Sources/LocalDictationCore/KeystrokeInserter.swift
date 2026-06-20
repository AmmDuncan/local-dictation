import AppKit
import Foundation

/// Inserts text by synthesizing Unicode key events instead of pasting via the
/// clipboard. Unlike `ClipboardInserter` it never touches the user's pasteboard
/// and works in fields that block programmatic paste (terminals, some password
/// and remote-desktop fields). Trade-off: marginally slower for long text and no
/// rich content — fine for dictation.
public final class KeystrokeInserter: TextInserting, @unchecked Sendable {
    private let chunkSize: Int
    private let interChunkDelayNanoseconds: UInt64

    /// `chunkSize` caps how many UTF-16 units ride one key event — CGEvent's
    /// Unicode buffer shouldn't be fed an unbounded string at once.
    public init(chunkSize: Int = 20, interChunkDelayNanoseconds: UInt64 = 1_500_000) {
        self.chunkSize = max(1, chunkSize)
        self.interChunkDelayNanoseconds = interChunkDelayNanoseconds
    }

    public func insert(_ text: String) async throws {
        guard !text.isEmpty else { return }
        for chunk in Self.chunks(of: text, size: chunkSize) {
            try Self.postUnicode(chunk)
            try await Task.sleep(nanoseconds: interChunkDelayNanoseconds)
        }
    }

    /// Splits text into UTF-16 chunks of at most `size`. Pure + exposed for tests.
    public static func chunks(of text: String, size: Int) -> [[UInt16]] {
        let units = Array(text.utf16)
        guard !units.isEmpty else { return [] }
        let step = max(1, size)
        var result: [[UInt16]] = []
        var i = 0
        while i < units.count {
            var end = min(i + step, units.count)
            // Never split a UTF-16 surrogate pair across chunks: if the boundary
            // lands right after a high surrogate, pull its low surrogate in too.
            if end < units.count, (0xD800...0xDBFF).contains(units[end - 1]) {
                end += 1
            }
            result.append(Array(units[i..<end]))
            i = end
        }
        return result
    }

    private static func postUnicode(_ utf16: [UInt16]) throws {
        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        else {
            throw PasteInsertionError.keystrokeFailed
        }
        utf16.withUnsafeBufferPointer { buffer in
            keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
        }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
