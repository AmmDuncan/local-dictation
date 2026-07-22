import SwiftUI

/// The compact dictation HUD — a small dark waveform pill with NO live transcript
/// text. Listening shows the live waveform; transcribing a brief status; done a
/// check. The final text injects at the cursor, so the flickering partial
/// hypotheses that read as inaccuracy never appear. Deliberately dark regardless
/// of system appearance so it reads over any underlying app (matching the
/// reference treatment), while `WaveBars` still honors Reduce Motion.
struct CompactOverlayView: View {
    var state: OverlayState

    private let pillBG = Color(hex: 0x14171A)
    private let pillStroke = Color.white.opacity(0.12)
    private let inkDim = Color(hex: 0xF4F8F6).opacity(0.6)
    private let doneInk = Color(hex: 0xCDD4D7)

    var body: some View {
        content
            .frame(height: 44)
            .background(
                Capsule(style: .continuous).fill(pillBG)
                    .overlay(Capsule(style: .continuous).strokeBorder(pillStroke))
                    .shadow(color: .black.opacity(0.55), radius: 18, y: 8)
            )
            // Breathing room so the pill's shadow renders in full instead of being
            // clipped to the panel's rectangular bounds (matches OverlayController).
            .padding(OverlayController.shadowMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var content: some View {
        switch state.phase {
        case .listening, .reviewSubstitution:
            WaveBars(level: state.level)
                .frame(width: 150, height: 22)
                .padding(.horizontal, 18)
        case .transcribing:
            HStack(spacing: 10) {
                ProcessingDots().frame(height: 9)
                Text("Transcribing").font(.system(size: 12)).foregroundStyle(inkDim)
            }
            .padding(.horizontal, 18)
        case .done:
            HStack(spacing: 9) {
                checkBadge
                Text("Inserted").font(.system(size: 12, weight: .medium)).foregroundStyle(doneInk)
            }
            .padding(.horizontal, 18)
        case .cancelled:
            HStack(spacing: 8) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(inkDim)
                Text("Discarded").font(.system(size: 12)).foregroundStyle(inkDim)
            }
            .padding(.horizontal, 18)
        case .error:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(Color(hex: 0xFF8A6B))
                Text(state.detail.isEmpty ? "Couldn't dictate" : state.detail)
                    .font(.system(size: 12)).foregroundStyle(inkDim).lineLimit(1)
            }
            .padding(.horizontal, 16)
        }
    }

    private var checkBadge: some View {
        ZStack {
            Circle().fill(Brand.emerald).frame(width: 18, height: 18)
            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                .foregroundStyle(Brand.onSignal)
        }
    }
}
