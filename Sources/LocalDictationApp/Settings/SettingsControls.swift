import SwiftUI

/// A toggle label whose title sits above a small "Experimental" caption — the
/// app's standard treatment for experimental settings, so the tag reads as
/// secondary metadata rather than part of the control's name.
struct ExperimentalLabel: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            Text("Experimental")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
