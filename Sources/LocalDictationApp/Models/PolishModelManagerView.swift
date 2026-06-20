import SwiftUI

/// Picker for the optional polish LLM — same row layout as the whisper
/// `ModelManagerView` (Download / Use / Active), driven by `PolishModelCatalog`.
struct PolishModelManagerView: View {
    var store: PolishModelStore
    var onModelChanged: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(PolishModelCatalog.all.enumerated()), id: \.element.id) { index, model in
                if index > 0 {
                    Divider()
                }
                PolishModelRow(model: model, store: store, onModelChanged: onModelChanged)
                    .padding(.vertical, 8)
            }
        }
    }
}

private struct PolishModelRow: View {
    let model: PolishModel
    var store: PolishModelStore
    var onModelChanged: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .fontWeight(.semibold)
                    if let note = model.note {
                        Text(note)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    }
                }
                Text("\(model.sizeLabel) · \(model.detail)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = store.errors[model.id] {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer(minLength: 8)

            control
        }
    }

    @ViewBuilder
    private var control: some View {
        if store.isActive(model) {
            Label("Active", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else if let progress = store.progress[model.id] {
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .frame(width: 80)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button(role: .cancel) {
                    store.cancel(model)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        } else if store.isInstalled(model) {
            Button("Use") {
                store.select(model)
                onModelChanged()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else {
            Button {
                store.download(model)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }
}
