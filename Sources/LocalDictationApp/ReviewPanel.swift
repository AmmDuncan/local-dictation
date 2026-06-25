import AppKit
import LocalDictationCore
import SwiftUI

/// The shared review + teach surface, rendered in the dictation brand language
/// (glass card, emerald accent, flat underlines) so it reads as one app with the
/// overlay HUD. Shows the dictation in context with its swaps flat-underlined and
/// listed as removable change chips; tap a word (or adjacent words) to teach a fix.
/// Writes through `RuleDerivation` to the same stores the apply path consults:
/// `textReplacements` (teach), `rejectedBuiltInSwaps` (revert built-ins),
/// `customVocabulary` (also-bias).
struct ReviewPanel: View {
    let record: CorrectionRecord
    var onClose: () -> Void
    /// Lets the host panel resize to the card's natural height as the sentence
    /// measurement and selection state settle. No-op for the Learn-tab sheet.
    var onSizeChange: (CGSize) -> Void = { _ in }
    /// Render the sentence at its natural height with no scroll wrapper — set by the
    /// off-screen `ImageRenderer` design-shot path, which can't render a `ScrollView`.
    var staticHeight = false
    /// Seeds a selection for the design-shot path (so the editor state can be
    /// rendered off-screen, where gestures don't run). Nil in normal use.
    var previewSelectedRange: ClosedRange<Int>?

    @AppStorage(AppSettingsKeys.textReplacements) private var textReplacements = AppSettingsSnapshot.Defaults.textReplacements
    @AppStorage(AppSettingsKeys.rejectedBuiltInSwaps) private var rejectedBuiltInSwaps = AppSettingsSnapshot.Defaults.rejectedBuiltInSwaps
    @AppStorage(AppSettingsKeys.rejectedContextSubSwaps) private var rejectedContextSubSwaps = AppSettingsSnapshot.Defaults.rejectedContextSubSwaps
    @AppStorage(AppSettingsKeys.customVocabulary) private var customVocabulary = AppSettingsSnapshot.Defaults.customVocabulary

    @Environment(\.colorScheme) private var scheme

    @State private var anchor: Int?
    @State private var head: Int?
    @State private var editValue = ""
    @State private var alsoBias = true  // opt-out; defaults on (rationale at appendTeach)
    /// Transient "✓ Learned X → Y" confirmation after an apply, so saving a fix —
    /// especially from a past (history) dictation, where it only teaches forward and
    /// rewrites nothing on screen — isn't silent.
    @State private var savedNote: String?
    /// Indices into `swaps` the user has reverted this session — drops the chip and
    /// updates the count without mutating the persisted record.
    @State private var reverted: Set<Int> = []
    /// The running corrected full text as the user makes fixes — copied to the
    /// clipboard so they can paste it over what was typed. Nil until a first fix.
    @State private var correctedText: String?
    /// Natural height of the sentence content, measured so the box can cap + scroll.
    @State private var sentenceHeight: CGFloat = 0
    private let sentenceMaxHeight: CGFloat = 184

    private var displayText: String { record.prePolish }
    private var swaps: [Edit] { record.segmentA }

    private var ink: Color { Brand.ink(scheme) }
    private var inkDim: Color { ink.opacity(0.6) }
    private var isDark: Bool { scheme == .dark }

    var body: some View {
        card
            .padding(20)
            .frame(width: 480)
            .background(halo)
            // Report the card's intrinsic size so the host panel can match it
            // (the card drives the panel, never the reverse — avoids a fill loop).
            .background(
                GeometryReader { geo in
                    Color.clear.onChange(of: geo.size, initial: true) { _, size in onSizeChange(size) }
                }
            )
            // Escape closes the panel (Return is bound to Done).
            .overlay(
                Button("", action: onClose).keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0)
            )
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            sentenceCard
            detailRegion
            footer
        }
        .padding(24)
        .background(glass)
        .overlay(alignment: .top) {
            Capsule().fill(Brand.signal).frame(height: 3).padding(.horizontal, 1)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.07))
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
    }

    private var glass: some View {
        ZStack {
            VisualEffectView(cornerRadius: 24)
            LinearGradient(
                colors: isDark
                    ? [Color(hex: 0x1E262A, alpha: 0.74), Color(hex: 0x0E1316, alpha: 0.86)]
                    : [Color.white.opacity(0.90), Color.white.opacity(0.84)],
                startPoint: .top, endPoint: .bottom
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var halo: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(
                RadialGradient(
                    colors: [Brand.emerald.opacity(0.18), Brand.teal.opacity(0.05), .clear],
                    center: .init(x: 0.5, y: 0.10), startRadius: 4, endRadius: 170
                )
            )
            .blur(radius: 34)
            .opacity(0.55)
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Brand.signal)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Brand.onSignal)
                )
                .shadow(color: Brand.emerald.opacity(0.5), radius: 10, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Review this dictation")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(ink)
                Text("Here's what I typed — corrections highlighted.")
                    .font(.system(size: 13))
                    .foregroundStyle(inkDim)
                polishProvenanceLine
            }
            Spacer(minLength: 8)
        }
    }

    /// One quiet, always-present line stating what the LLM polish did this dictation
    /// — the on-demand answer to "is it actually doing anything?" on the one screen
    /// opened to scrutinise a result. Glyph SHAPE (not colour) distinguishes the
    /// states, and each carries a VoiceOver label. `guardRejected` is framed as the
    /// faithfulness guard working FOR the user, not a failure.
    @ViewBuilder
    private var polishProvenanceLine: some View {
        let p = polishProvenance
        HStack(spacing: 5) {
            Image(systemName: p.glyph).font(.system(size: 11))
            Text(p.text).font(.system(size: 12))
        }
        .foregroundStyle(p.positive ? Brand.emerald : inkDim)
        .padding(.top, 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(p.spoken)
    }

    private struct PolishProvenance {
        let glyph: String
        let text: String
        let positive: Bool
        let spoken: String
    }

    private var polishProvenance: PolishProvenance {
        switch record.polishOutcome {
        case .applied:
            return PolishProvenance(glyph: "checkmark.circle.fill", text: "Polished on-device", positive: true, spoken: "Polished on device")
        case .unchanged:
            return PolishProvenance(glyph: "checkmark.circle", text: "Polished on-device — nothing to change", positive: false, spoken: "Polished on device, nothing to change")
        case .guardRejected:
            return PolishProvenance(glyph: "exclamationmark.shield", text: "Polish held back — kept your exact words", positive: false, spoken: "Polish held back, kept your exact words")
        case .unavailable:
            return PolishProvenance(glyph: "circle", text: "Polish unavailable — model not loaded", positive: false, spoken: "Polish unavailable, model not loaded")
        case .none:
            return PolishProvenance(glyph: "minus", text: "Polish off", positive: false, spoken: "Polish off")
        }
    }

    // MARK: sentence

    /// The dictated sentence as tappable word tokens. Tight inter-word spacing reads
    /// as prose; `lineSpacing` gives leading without widening the gaps between words.
    private var sentenceFlow: some View {
        FlowLayout(spacing: 1, lineSpacing: 6) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                tokenView(index: index, text: token.text)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var sentenceCard: some View {
        Group {
            if staticHeight {
                sentenceFlow
            } else {
                // Hug the content until it exceeds the cap, then fix the height + scroll
                // so a long dictation can't grow the panel off-screen.
                ScrollView(.vertical, showsIndicators: true) {
                    sentenceFlow.background(
                        GeometryReader { geo in
                            Color.clear.preference(key: SentenceHeightKey.self, value: geo.size.height)
                        }
                    )
                }
                .frame(height: sentenceScrolls ? sentenceMaxHeight : nil)
                .fixedSize(horizontal: false, vertical: !sentenceScrolls)
                .onPreferenceChange(SentenceHeightKey.self) { sentenceHeight = $0 }
            }
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(ink.opacity(isDark ? 0.06 : 0.04)))
    }

    private var sentenceScrolls: Bool { sentenceHeight > sentenceMaxHeight }

    @ViewBuilder
    private func tokenView(index: Int, text: String) -> some View {
        let isSwap = activeSwap(forTokenAt: index) != nil
        let isSelected = selectedRange.map { $0.contains(index) } ?? false
        Text(text)
            .font(.system(size: 16))
            .foregroundStyle(isSwap ? Brand.emerald : ink)
            // Flat (non-rounded) underline on swapped words.
            .overlay(alignment: .bottom) {
                if isSwap { Rectangle().fill(Brand.emerald).frame(height: 1.5).offset(y: 1) }
            }
            .padding(.horizontal, 2).padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 4).fill(isSelected ? Brand.emerald.opacity(0.28) : .clear))
            .contentShape(Rectangle())
            .onTapGesture { tap(index) }
    }

    // MARK: detail region (editor · changes · hint)

    @ViewBuilder
    private var detailRegion: some View {
        if selectedRange != nil {
            editor
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if let savedNote {
                    Label(savedNote, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Brand.emerald)
                }
                if !visibleChanges.isEmpty {
                    changesSection
                } else if savedNote == nil {
                    Text("No corrections — tap any word to teach a fix.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(inkDim)
                }
            }
        }
    }

    /// Swaps not yet reverted in this session, paired with their `swaps` index.
    private var visibleChanges: [(index: Int, edit: Edit)] {
        swaps.enumerated().compactMap { reverted.contains($0.offset) ? nil : (index: $0.offset, edit: $0.element) }
    }

    private var changesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(changesLabel)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(inkDim)
            ForEach(visibleChanges, id: \.index) { change in
                changeChip(index: change.index, edit: change.edit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var changesLabel: String {
        let n = visibleChanges.count
        return "\(n) CHANGE\(n == 1 ? "" : "S") — REMOVE ANY TO REVERT"
    }

    private func changeChip(index: Int, edit: Edit) -> some View {
        let isContextSub = edit.source == .contextSub
        return HStack(spacing: 9) {
            Text(isContextSub ? "CONTEXT" : "HEARD")
                .font(.system(size: 9.5, weight: .bold)).tracking(0.5)
                .foregroundStyle(isContextSub ? Brand.emerald : inkDim)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(isContextSub ? Brand.emerald.opacity(0.15) : ink.opacity(0.10)))
            Text(edit.from).strikethrough().foregroundStyle(inkDim)
            Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(inkDim)
            Text(edit.to).fontWeight(.semibold).foregroundStyle(Brand.emerald)
            Button { revertChange(index: index, edit: edit) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(inkDim)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(ink.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .help("Revert this change")
        }
        .font(.system(size: 13))
        .padding(.leading, 10).padding(.trailing, 6).padding(.vertical, 6)
        .background(Capsule().fill(Brand.emerald.opacity(0.10)))
        .overlay(Capsule().strokeBorder(Brand.emerald.opacity(0.30)))
    }

    // MARK: footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done", action: onClose)
                .buttonStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(inkDim)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: tokens

    // Compiled once, not per redraw (the view's `body`/helpers read `tokens` often).
    private static let tokenRegex = try? NSRegularExpression(pattern: "\\S+")

    private var tokens: [(text: String, range: NSRange)] {
        let ns = displayText as NSString
        guard let regex = Self.tokenRegex else { return [] }
        return regex.matches(in: displayText, range: NSRange(location: 0, length: ns.length))
            .map { (ns.substring(with: $0.range), $0.range) }
    }

    private func swap(forTokenAt index: Int) -> Edit? {
        guard index < tokens.count else { return nil }
        let r = tokens[index].range
        return swaps.first { NSIntersectionRange($0.range, r).length > 0 }
    }

    /// Like `swap(forTokenAt:)` but nil once that swap has been reverted — so the
    /// underline disappears from the sentence in step with the chip.
    private func activeSwap(forTokenAt index: Int) -> Edit? {
        guard index < tokens.count else { return nil }
        let r = tokens[index].range
        for (offset, edit) in swaps.enumerated() where !reverted.contains(offset) {
            if NSIntersectionRange(edit.range, r).length > 0 { return edit }
        }
        return nil
    }

    // MARK: selection

    private var selectedRange: ClosedRange<Int>? {
        guard let a = anchor, let h = head else { return previewSelectedRange }
        return min(a, h)...max(a, h)
    }

    /// Tap to build a contiguous selection — see `SpanSelection.tap` for the grow /
    /// shrink / toggle / adjacent / separated rules (factored out + unit-tested).
    private func tap(_ index: Int) {
        savedNote = nil
        let next = SpanSelection.tap(current: selectedRange, index: index)
        anchor = next?.lowerBound
        head = next?.upperBound
        resetEditor()
    }

    private func resetEditor() {
        alsoBias = true
        guard let range = selectedRange else { editValue = ""; return }
        if let edit = singleSwap(in: range) {
            editValue = edit.to  // pre-fill a change with the current value to tweak
        } else {
            editValue = ""  // teach: empty so the placeholder prompts for the correction
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
                Text("Correct “\(selectedText(range))” to:")
                    .font(.system(size: 13)).foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    TextField(range.count > 1 ? "the right words" : "the right word", text: $editValue)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") { applyEditor(range) }
                        .buttonStyle(SignalButtonStyle())
                        .disabled(trimmed(editValue).isEmpty)
                }
                Toggle("Also bias recognition toward this word", isOn: $alsoBias)
                    .font(.system(size: 12))
                    .tint(Brand.emerald)
                Text("Teaches it for next time and copies the corrected text — ⌘V to paste it over what you typed.")
                    .font(.system(size: 11)).foregroundStyle(inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Brand.emerald.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Brand.emerald.opacity(0.38)))
        }
    }

    // MARK: apply

    /// Revert a built-in swap from its change chip's × button: suppress it for next
    /// time, copy the original back over the swapped text, and drop the chip.
    private func revertChange(index: Int, edit: Edit) {
        if edit.source == .contextSub {
            // Persist the rejected swap so future context-sub passes skip this pair.
            let id = "\(edit.from) -> \(edit.to)"
            rejectedContextSubSwaps = SuppressionSet.toggling(id, in: rejectedContextSubSwaps, on: true)
        } else if let id = RuleDerivation.suppressionIdentity(for: edit) {
            rejectedBuiltInSwaps = SuppressionSet.toggling(id, in: rejectedBuiltInSwaps, on: true)
        }
        copyCorrection(expecting: edit.to, replacement: edit.from)
        reverted.insert(index)
        clearSelection()
        savedNote = "Reverted “\(edit.from)” → “\(edit.to)” · copied, ⌘V to replace"
    }

    /// Apply the editor for the selected span: re-point a built-in swap to the user's
    /// value, or teach a fix for a plain span. Both teach for next time and copy the
    /// corrected text to the clipboard (see `copyCorrection`).
    private func applyEditor(_ range: ClosedRange<Int>) {
        if let edit = singleSwap(in: range) {
            applyChange(edit, to: editValue)
        } else {
            applyTeach(heard: selectedText(range), correction: editValue)
        }
    }

    private func applyChange(_ edit: Edit, to newValue: String) {
        // Stop the built-in from re-applying, and teach the user's preferred result.
        if let id = RuleDerivation.suppressionIdentity(for: edit) {
            rejectedBuiltInSwaps = SuppressionSet.toggling(id, in: rejectedBuiltInSwaps, on: true)
        }
        appendTeach(heard: edit.from, correction: newValue)
        copyCorrection(expecting: edit.to, replacement: trimmed(newValue))
        clearSelection()
        savedNote = "Learned “\(edit.from)” → “\(trimmed(newValue))” · copied, ⌘V to replace"
    }

    private func applyTeach(heard: String, correction: String) {
        appendTeach(heard: heard, correction: correction)
        copyCorrection(expecting: heard, replacement: trimmed(correction))
        clearSelection()
        savedNote = "Learned “\(heard)” → “\(trimmed(correction))” · copied, ⌘V to replace"
    }

    /// Copy the running corrected full text to the clipboard so the user can paste it
    /// over what was typed (⌘V) — universal, unlike an AX in-place replace which only
    /// landed in some apps. Each fix composes onto the previous via a first-match
    /// replacement; the clipboard ends holding the latest fully-corrected text.
    private func copyCorrection(expecting: String, replacement: String) {
        guard !replacement.isEmpty else { return }
        let text = CorrectionApply.apply(replacement, for: expecting, to: correctedText ?? record.inserted)
        correctedText = text
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func appendTeach(heard: String, correction: String) {
        if let rule = RuleDerivation.teach(heard: heard, correction: correction) {
            let rules = TextReplacements.parse(textReplacements) + [rule]
            textReplacements = TextReplacements.serialize(rules)
        }
        // Default on: feed the corrected term into the recognition bias prompt so the
        // decoder stops mishearing it next time, not just rewriting it after the fact.
        if alsoBias {
            customVocabulary = CustomVocabulary.appending(correction, to: customVocabulary)
        }
    }

    private func clearSelection() {
        anchor = nil; head = nil; editValue = ""; alsoBias = true
    }

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }
}

/// Reports the sentence content's natural height so the box can cap it and scroll.
private struct SentenceHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
