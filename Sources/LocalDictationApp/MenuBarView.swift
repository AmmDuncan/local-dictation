@preconcurrency import KeyboardShortcuts
import SwiftUI

struct MenuBarView: View {
    var model: AppModel
    @ObservedObject var updater: UpdaterModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !model.readiness.allReady {
                setupCallout
            }

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !model.lastTranscript.isEmpty {
                lastTranscriptPreview
            }

            Divider()

            Button("Dictation History…") { openHistoryWindow() }
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)

            HStack {
                Button("Settings") { openSettingsWindow() }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .onAppear { model.readiness.refresh() }
    }

    /// A tappable preview of the most recent dictation. Clicking opens Dictation
    /// History (where it sits at the top with its own copy button) rather than
    /// expanding selectable text inline, which clashed with the popup's controls.
    private var lastTranscriptPreview: some View {
        Button { openHistoryWindow() } label: {
            HStack(alignment: .center, spacing: 6) {
                Text(model.lastTranscript)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open in Dictation History")
        .accessibilityHint("Opens Dictation History")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.isRecording ? "record.circle.fill" : "mic.circle")
                .font(.system(size: 28))
                .foregroundStyle(model.isRecording ? .red : .accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.status)
                    .font(.headline)
                Text(shortcutLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var setupCallout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Finish setup to start dictating", systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .fontWeight(.medium)
                .foregroundStyle(.orange)

            ForEach(model.readiness.items.filter { $0.state != .ok }) { item in
                Text("• \(item.detail ?? item.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Open Settings") { openSettingsWindow() }
                .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }

    private var shortcutLabel: String {
        if let shortcut = KeyboardShortcuts.getShortcut(for: .holdToDictate) {
            return "Hold \(shortcut) to dictate"
        }
        return "Set a shortcut in Settings to begin"
    }

    private func openSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        openSettings()
        NSApp.activate()
    }

    private func openHistoryWindow() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "history")
        NSApp.activate()
    }
}
