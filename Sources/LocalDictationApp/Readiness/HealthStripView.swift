import SwiftUI

struct HealthStripView: View {
    var readiness: ReadinessModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: readiness.allReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(readiness.allReady ? Brand.emerald : Color.orange)
                Text(readiness.allReady ? "Ready to dictate" : "Setup needed")
                    .font(.headline)
            }

            FlowLayout(spacing: 8) {
                ForEach(readiness.items) { item in
                    pill(item)
                }
            }

            let issues = readiness.items.filter { $0.state != .ok && $0.detail != nil }
            if !issues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(issues) { item in
                        Text("\(item.label): \(item.detail ?? "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(readiness.allReady ? Brand.emerald.opacity(0.25) : Color.orange.opacity(0.35))
        )
    }

    private func pill(_ item: ReadinessItem) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol(item.state))
                .font(.caption)
                .foregroundStyle(tint(item.state))
            Text(item.label)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(Capsule().strokeBorder(.separator))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.label): \(item.state.spokenStatus)")
    }

    private func symbol(_ state: ReadinessState) -> String {
        switch state {
        case .ok: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .fail: "xmark.circle.fill"
        }
    }

    private func tint(_ state: ReadinessState) -> Color {
        switch state {
        case .ok: Brand.emerald
        case .warn: .orange
        case .fail: .red
        }
    }
}

/// Lays children left-to-right, wrapping to the next row when they don't fit —
/// so the readiness pills flow instead of one pill breaking its text mid-word.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    /// Vertical gap between wrapped rows. Defaults to `spacing` (square gaps); set it
    /// to give prose-like leading without widening the gap between words on a line.
    var lineSpacing: CGFloat?

    private var rowGap: CGFloat { lineSpacing ?? spacing }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + rowGap
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + rowGap
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
