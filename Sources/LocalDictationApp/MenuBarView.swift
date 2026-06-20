@preconcurrency import KeyboardShortcuts
import LocalDictationCore
import SwiftUI

struct MenuBarView: View {
    var model: AppModel
    @ObservedObject var updater: UpdaterModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @AppStorage(AppSettingsKeys.polishWithAI) private var polishWithAI = AppSettingsSnapshot.Defaults.polishWithAI
    @AppStorage(AppSettingsKeys.dictationMode) private var dictationMode = AppSettingsSnapshot.Defaults.dictationMode

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            // Quick mode switch — only meaningful when AI polish is on (modes
            // shape the polish pass). Per-app profiles still override per app.
            if polishWithAI {
                Picker("Mode", selection: $dictationMode) {
                    ForEach(DictationMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }

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
                Text(model.lastTranscript)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
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
