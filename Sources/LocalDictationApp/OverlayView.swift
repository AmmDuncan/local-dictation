import AppKit
import Combine
import SwiftUI

// MARK: - Overlay

struct OverlayView: View {
    var state: OverlayState
    @Environment(\.colorScheme) private var scheme
    @State private var breathe = false

    private var isDark: Bool { scheme == .dark }
    private var ink: Color { Brand.ink(scheme) }
    private var inkDim: Color { ink.opacity(0.62) }
    private var isError: Bool { state.phase == .error }

    var body: some View {
        ZStack {
            halo
            content
                .padding(.init(top: 22, leading: 24, bottom: 22, trailing: 24))
                .background(glass)
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(isError ? Brand.error : Brand.signal)
                        .frame(height: 3)
                        .padding(.horizontal, 1)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.07))
                )
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        }
        // Transparent breathing room so the shadow + halo render fully instead of
        // being clipped to a hard box by the panel bounds. Matches the panel size
        // computed in OverlayController (shadowMargin on every edge).
        .padding(OverlayController.shadowMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { breathe = true }
    }

    private var glass: some View {
        ZStack {
            VisualEffectView()
            LinearGradient(
                colors: isDark
                    ? [Color(hex: 0x1E262A, alpha: 0.72), Color(hex: 0x0E1316, alpha: 0.80)]
                    : [Color.white.opacity(0.86), Color.white.opacity(0.80)],
                startPoint: .top, endPoint: .bottom
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var halo: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(
                RadialGradient(
                    colors: isError
                        ? [Color(hex: 0xFF6B6B, alpha: 0.30), .clear]
                        : [Brand.emerald.opacity(0.40), Brand.teal.opacity(0.08), .clear],
                    center: .init(x: 0.5, y: 0.3), startRadius: 4, endRadius: 150
                )
            )
            .blur(radius: 26)
            .scaleEffect(isError ? 1.0 : (breathe ? 1.04 : 0.97))
            .opacity(isError ? 0.6 : (breathe ? 0.9 : 0.55))
            .animation(isError ? nil : .easeInOut(duration: 3.4).repeatForever(autoreverses: true), value: breathe)
    }

    // MARK: chrome

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            body(for: state.phase)
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isError ? Brand.error : Brand.signal)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: headerIcon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Brand.onSignal)
                )
                .shadow(color: (isError ? Color(hex: 0xFF6B6B) : Brand.emerald).opacity(0.5), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text(state.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(ink)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(inkDim)
            }
            Spacer(minLength: 8)

            if !isError {
                privacyPill
            }
        }
        .padding(.bottom, 18)
    }

    private var privacyPill: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 10))
            Text("On-device")
                .font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(Brand.emerald)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(Brand.emerald.opacity(0.12)))
        .overlay(Capsule().strokeBorder(Brand.emerald.opacity(0.22)))
    }

    private var headerIcon: String {
        switch state.phase {
        case .error: "exclamationmark.triangle.fill"
        case .cancelled: "xmark"
        default: "waveform"
        }
    }

    private var subtitle: String {
        switch state.phase {
        case .listening: "Speak now — I'm hearing you"
        case .transcribing: "Processing your words locally"
        case .done: "Typed at your cursor"
        case .error: "Can't continue yet"
        case .cancelled: "Discarded — nothing typed"
        }
    }

    // MARK: bodies

    @ViewBuilder
    private func body(for phase: DictationPhase) -> some View {
        switch phase {
        case .listening: listeningBody
        case .transcribing: transcribingBody
        case .done: doneBody
        case .error: errorBody
        case .cancelled: cancelledBody
        }
    }

    private var cancelledBody: some View {
        HStack(spacing: 10) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(inkDim)
            Text("Recording discarded")
                .font(.system(size: 14))
                .foregroundStyle(inkDim)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var listeningBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            WaveBars(level: state.level)
                .frame(height: 60)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 6)
            // The live text is a fast partial; the final insertion re-transcribes
            // and runs corrections/polish, so it can differ. Mark it as a draft
            // so the change on release reads as expected, not a glitch.
            VStack(alignment: .leading, spacing: 4) {
                if !state.detail.isEmpty {
                    draftEyebrow
                }
                TailingTranscript(text: state.detail, ink: ink, inkDim: inkDim)
            }
        }
    }

    private var draftEyebrow: some View {
        HStack(spacing: 5) {
            Image(systemName: "pencil.and.outline")
                .font(.system(size: 9, weight: .semibold))
            Text("Draft · refining…")
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.6)
        }
        .foregroundStyle(inkDim)
    }

    private var transcribingBody: some View {
        VStack(spacing: 16) {
            ProcessingDots()
                .frame(height: 24)
            IndeterminateBar()
                .frame(height: 3)
        }
        .frame(maxWidth: .infinity)
    }

    private var doneBody: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Brand.onSignal)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Brand.signal))
                .shadow(color: Brand.emerald.opacity(0.5), radius: 14, y: 4)
                .transition(.scale.combined(with: .opacity))

            if !state.detail.isEmpty {
                Text(doneAttributed)
                    .font(.system(size: 15))
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(13)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 14).fill(ink.opacity(0.05)))
                if !state.swappedRanges.isEmpty {
                    Text("⌥Z to review")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(inkDim)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The typed text with swapped words flat-underlined in the brand emerald.
    private var doneAttributed: AttributedString {
        let text = "“\(state.detail)”"
        let ranges = state.swappedRanges
        guard !ranges.isEmpty else { return AttributedString(text) }
        // The display string has a leading curly quote, so swap ranges (in `detail`)
        // are offset by one UTF-16 unit.
        let ns = text as NSString
        let valid = ranges
            .map { NSRange(location: $0.location + 1, length: $0.length) }
            .filter { $0.location >= 0 && $0.location + $0.length <= ns.length }
            .sorted { $0.location < $1.location }
        var result = AttributedString()
        var cursor = 0
        for range in valid {
            // Skip a range that overlaps an already-emitted one (defensive: a negative
            // gap length would crash; swap ranges are non-overlapping in practice).
            guard range.location >= cursor else { continue }
            if range.location > cursor {
                result += AttributedString(ns.substring(with: NSRange(location: cursor, length: range.location - cursor)))
            }
            var swapped = AttributedString(ns.substring(with: range))
            swapped.underlineStyle = .single
            swapped.foregroundColor = Brand.emerald
            result += swapped
            cursor = range.location + range.length
        }
        if cursor < ns.length {
            result += AttributedString(ns.substring(from: cursor))
        }
        return result
    }

    private var errorBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(state.detail)
                .font(.system(size: 13))
                .foregroundStyle(ink.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            if let title = state.actionTitle {
                HStack(spacing: 9) {
                    Spacer()
                    Button(title) { state.action?() }
                        .buttonStyle(SignalButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Tailing transcript

/// Live partial transcript that keeps the newest words in view: the text
/// bottom-aligns inside a fixed three-line window, and older lines scroll up and
/// fade out the top as you keep speaking — a tailing "scroll", never the default
/// tail-truncation that would hide the latest words behind a trailing "…".
///
/// The window shows ~3 lines (more recent context than the old 2-line cut), the
/// top line ghosts out through a soft gradient rather than clipping mid-glyph,
/// and growth is eased so new words glide up instead of snapping.
private struct TailingTranscript: View {
    var text: String
    var ink: Color
    var inkDim: Color

    private let windowHeight: CGFloat = 70  // ~three lines at 16.5pt + lineSpacing
    private var isEmpty: Bool { text.isEmpty }

    var body: some View {
        Text(isEmpty ? "…" : text)
            .font(.system(size: 16.5))
            .lineSpacing(3)
            .multilineTextAlignment(.leading)
            .foregroundStyle(isEmpty ? inkDim : ink)
            .frame(maxWidth: .infinity, alignment: .leading)  // fill width, wrap to N lines
            .fixedSize(horizontal: false, vertical: true)      // lock full height — no height-truncation
            .frame(maxWidth: .infinity, minHeight: windowHeight, maxHeight: windowHeight, alignment: .bottomLeading)
            .clipped()                                          // older lines overflow + clip out the top
            .mask(
                // Ghost the oldest visible line: fully transparent at the very top,
                // ramping to opaque over the first line so old context stays
                // legible-but-receding instead of being chopped at a hard edge.
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.35), location: 0.16),
                        .init(color: .black, location: 0.42),
                        .init(color: .black, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .animation(.easeOut(duration: 0.16), value: text)  // glide, don't snap
            .accessibilityLabel(isEmpty ? "Listening" : text)
    }
}

// MARK: - Waveform

private let waveBarCount = 24

private struct WaveBars: View {
    var level: Double
    private let count = waveBarCount
    @State private var levels: [Double] = (0..<waveBarCount).map { 0.14 + 0.34 * abs(sin(Double($0) * 0.7)) }

    /// Right→left scroll cadence for the bar history. Decoupled from the 30Hz
    /// mic-level sampling so the wave glides calmly instead of racing across.
    /// @State so the timer is created once and survives re-renders.
    @State private var scroll = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(Brand.signal)
                        .frame(width: 4, height: barHeight(i, maxHeight: geo.size.height))
                        .opacity(edgeOpacity(i))
                        .shadow(color: Brand.emerald.opacity(0.5), radius: 5)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onReceive(scroll) { _ in
            levels.removeFirst()
            levels.append(max(level, 0.04))
        }
    }

    private func barHeight(_ i: Int, maxHeight: CGFloat) -> CGFloat {
        let v = levels[i]
        return max(4, CGFloat(v) * (maxHeight - 8) + 6)
    }

    private func edgeOpacity(_ i: Int) -> Double {
        let d = min(i, count - 1 - i)
        if d == 0 { return 0.32 }
        if d == 1 { return 0.5 }
        if d == 2 { return 0.7 }
        return 1
    }
}

private struct ProcessingDots: View {
    @State private var animate = false
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(Brand.signal)
                    .frame(width: 9, height: 9)
                    .scaleEffect(animate ? 1.0 : 0.5)
                    .opacity(animate ? 1 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double(i) * 0.12),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

private struct IndeterminateBar: View {
    @State private var offset: CGFloat = -1
    var body: some View {
        GeometryReader { geo in
            Capsule().fill(Color.primary.opacity(0.08))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Brand.signal)
                        .frame(width: geo.size.width * 0.4)
                        .offset(x: offset * geo.size.width)
                }
                .clipShape(Capsule())
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: false)) {
                offset = 1.2
            }
        }
    }
}
