import LocalDictationCore
import SwiftUI

/// The shared review + teach surface. Shows a dictation in context with its swaps
/// flat-underlined; select a span (tap a word, tap another to extend) to revert a
/// swap or teach a correction. Reachable from the Learn tab (here) and the Door #1
/// hotkey (P4). Writes through `RuleDerivation` to the same stores the apply path
/// consults: `textReplacements` (teach), `rejectedBuiltInSwaps` (revert built-ins),
/// `customVocabulary` (also-bias).
struct ReviewPanel: View {
    let record: CorrectionRecord
    var onClose: () -> Void
    /// Provided only by the Door #1 floating panel: re-insert the corrected full text
    /// into the still-focused field (experimental). Nil from the Learn-tab sheet.
    var onReinsert: ((String) -> Void)?

    @AppStorage(AppSettingsKeys.textReplacements) private var textReplacements = AppSettingsSnapshot.Defaults.textReplacements
    @AppStorage(AppSettingsKeys.rejectedBuiltInSwaps) private var rejectedBuiltInSwaps = AppSettingsSnapshot.Defaults.rejectedBuiltInSwaps
    @AppStorage(AppSettingsKeys.customVocabulary) private var customVocabulary = AppSettingsSnapshot.Defaults.customVocabulary
    @AppStorage(AppSettingsKeys.liveReinsertionEnabled) private var liveReinsertionEnabled = AppSettingsSnapshot.Defaults.liveReinsertionEnabled

    @State private var anchor: Int?
    @State private var head: Int?
    @State private var editValue = ""
    @State private var alsoBias = false

    private static let emerald = Color(red: 0.18, green: 0.84, blue: 0.64)

    private var displayText: String { record.prePolish }
    private var swaps: [Edit] { record.segmentA }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Review this dictation").font(.headline)
                Text("Tap a word — tap another to extend — then fix it.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            FlowLayout(spacing: 6) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                    tokenView(index: index, text: token.text)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))

            if selectedRange != nil {
                editor
            } else {
                Text("No selection. Tap a highlighted word to revert it, or any word to teach a fix.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 380)
    }

    // MARK: tokens

    private var tokens: [(text: String, range: NSRange)] {
        let ns = displayText as NSString
        guard let regex = try? NSRegularExpression(pattern: "\\S+") else { return [] }
        return regex.matches(in: displayText, range: NSRange(location: 0, length: ns.length))
            .map { (ns.substring(with: $0.range), $0.range) }
    }

    private func swap(forTokenAt index: Int) -> Edit? {
        guard index < tokens.count else { return nil }
        let r = tokens[index].range
        return swaps.first { NSIntersectionRange($0.range, r).length > 0 }
    }

    @ViewBuilder
    private func tokenView(index: Int, text: String) -> some View {
        let isSwap = swap(forTokenAt: index) != nil
        let isSelected = selectedRange.map { $0.contains(index) } ?? false
        Text(text)
            .foregroundStyle(isSwap ? Self.emerald : Color.primary)
            // Flat (non-rounded) underline on swapped words.
            .overlay(alignment: .bottom) {
                if isSwap { Rectangle().fill(Self.emerald).frame(height: 1.5).offset(y: 2) }
            }
            .padding(.horizontal, 3).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(isSelected ? Self.emerald.opacity(0.28) : .clear))
            .contentShape(Rectangle())
            .onTapGesture { tap(index) }
    }

    // MARK: selection

    private var selectedRange: ClosedRange<Int>? {
        guard let a = anchor, let h = head else { return nil }
        return min(a, h)...max(a, h)
    }

    private func tap(_ index: Int) {
        if anchor == index, head == index {
            anchor = nil; head = nil  // tapping the lone selected word clears it
        } else if let a = anchor, head == a {
            head = index  // extend from the single anchor to a span
        } else {
            anchor = index; head = index  // start a fresh single selection
        }
        resetEditor()
    }

    private func resetEditor() {
        alsoBias = false
        guard let range = selectedRange else { editValue = ""; return }
        if let edit = singleSwap(in: range) {
            editValue = edit.to  // pre-fill a change with the current value
        } else {
            editValue = selectedText(range)  // teach starts from what was heard
        }
    }

    private func unionRange(_ range: ClosedRange<Int>) -> NSRange {
        let slice = tokens[range]
        guard let first = slice.first, let last = slice.last else { return NSRange(location: 0, length: 0) }
        return NSRange(location: first.range.location,
                       length: last.range.location + last.range.length - first.range.location)
    }

    private func selectedText(_ range: ClosedRange<Int>) -> String {
        (displayText as NSString).substring(with: unionRange(range))
    }

    /// The lone swap the selection sits within, or nil (no swap, or spans multiple).
    private func singleSwap(in range: ClosedRange<Int>) -> Edit? {
        let edits = Set(range.compactMap { swap(forTokenAt: $0).map(\.range.location) })
        guard edits.count == 1 else { return nil }
        return range.compactMap { swap(forTokenAt: $0) }.first
    }

    // MARK: editor

    @ViewBuilder
    private var editor: some View {
        if let range = selectedRange {
            VStack(alignment: .leading, spacing: 10) {
                if let edit = singleSwap(in: range) {
                    Text("Heard “\(edit.from)” → typed “\(edit.to)”").font(.callout)
                    HStack {
                        Button("Revert to “\(edit.from)”") { applyRevert(edit) }
                        Spacer()
                    }
                    HStack {
                        TextField("change to", text: $editValue)
                        Button("Save") { applyChange(edit, to: editValue) }
                            .disabled(trimmed(editValue).isEmpty)
                    }
                } else {
                    Text("Teach a fix for “\(selectedText(range))”").font(.callout)
                    HStack {
                        TextField("correction", text: $editValue)
                        Button("Teach") {
                            applyTeach(heard: selectedText(range), correction: editValue, span: unionRange(range))
                        }
                        .disabled(trimmed(editValue).isEmpty)
                    }
                }
                Toggle("Also bias recognition toward this word", isOn: $alsoBias)
                    .font(.caption)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Self.emerald.opacity(0.4)))
        }
    }

    // MARK: apply

    private func applyRevert(_ edit: Edit) {
        if let id = RuleDerivation.suppressionIdentity(for: edit) {
            rejectedBuiltInSwaps = SuppressionSet.toggling(id, in: rejectedBuiltInSwaps, on: true)
        }
        maybeReinsert(span: edit.range, expecting: edit.to, replacement: edit.from)
        clearSelection()
    }

    private func applyChange(_ edit: Edit, to newValue: String) {
        // Stop the built-in from re-applying, and teach the user's preferred result.
        if let id = RuleDerivation.suppressionIdentity(for: edit) {
            rejectedBuiltInSwaps = SuppressionSet.toggling(id, in: rejectedBuiltInSwaps, on: true)
        }
        appendTeach(heard: edit.from, correction: newValue)
        maybeReinsert(span: edit.range, expecting: edit.to, replacement: trimmed(newValue))
        clearSelection()
    }

    private func applyTeach(heard: String, correction: String, span: NSRange) {
        appendTeach(heard: heard, correction: correction)
        maybeReinsert(span: span, expecting: heard, replacement: trimmed(correction))
        clearSelection()
    }

    /// Experimental: re-insert the corrected full text into the current field, but
    /// only when the span still lines up with what was inserted (no polish/replacement
    /// drift) — otherwise it's learn-for-next-time only.
    private func maybeReinsert(span: NSRange, expecting: String, replacement: String) {
        guard liveReinsertionEnabled, let onReinsert, !replacement.isEmpty else { return }
        let ns = record.inserted as NSString
        guard span.location >= 0, span.location + span.length <= ns.length,
              ns.substring(with: span) == expecting else { return }
        onReinsert(ns.replacingCharacters(in: span, with: replacement))
    }

    private func appendTeach(heard: String, correction: String) {
        if let rule = RuleDerivation.teach(heard: heard, correction: correction) {
            let rules = TextReplacements.parse(textReplacements) + [rule]
            textReplacements = TextReplacements.serialize(rules)
        }
        if alsoBias {
            let term = trimmed(correction)
            if !term.isEmpty {
                customVocabulary = customVocabulary.isEmpty ? term : customVocabulary + "\n" + term
            }
        }
    }

    private func clearSelection() {
        anchor = nil; head = nil; editValue = ""; alsoBias = false
    }

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }
}
