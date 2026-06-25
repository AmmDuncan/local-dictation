import SwiftUI

struct ModelManagerView: View {
    var store: ModelStore
    var onModelChanged: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(ModelCatalog.all.enumerated()), id: \.element.id) { index, model in
                if index > 0 {
                    Divider()
                }
                ModelRow(model: model, store: store, onModelChanged: onModelChanged)
                    .padding(.vertical, 8)
            }
        }
    }
}

private struct ModelRow: View {
    let model: WhisperModel
    var store: ModelStore
    var onModelChanged: () -> Void
    @State private var confirmingRemove = false

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
                            .foregroundStyle(Brand.emerald)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Brand.emerald.opacity(0.15)))
                    }
                }
                HStack(spacing: 5) {
                    metaChip(model.sizeLabel)
                    metaChip(model.speed)
                    metaChip(model.accuracy)
                    metaChip(model.language)
                }
                if let error = store.errors[model.id] {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer(minLength: 8)

            control
        }
        .confirmationDialog("Remove \(model.displayName)?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove (frees \(model.sizeLabel))", role: .destructive) {
                store.remove(model)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Deletes the model file from disk. You can re-download it anytime.")
        }
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12)))
    }

    @ViewBuilder
    private var control: some View {
        if store.isActive(model) {
            Label("Active", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Brand.emerald)
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
            HStack(spacing: 8) {
                Button("Use") {
                    store.select(model)
                    onModelChanged()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button(role: .destructive) {
                    confirmingRemove = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
                .help("Remove from disk to free \(model.sizeLabel)")
            }
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
