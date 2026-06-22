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

            // Full-width menu rows (not bordered buttons) so the popover reads as
            // a menu, and tinted with Brand emerald to match the dictation HUD.
            menuGroup {
                MenuRow(title: "Dictation History…", systemImage: "clock.arrow.circlepath") {
                    openHistoryWindow()
                }
                MenuRow(title: "Check for Updates…",
                        systemImage: "arrow.triangle.2.circlepath",
                        disabled: !updater.canCheckForUpdates) {
                    updater.checkForUpdates()
                }
            }

            Divider()

            menuGroup {
                MenuRow(title: "Settings…", systemImage: "gearshape", shortcut: "⌘,") {
                    openSettingsWindow()
                }
                MenuRow(title: "Quit", systemImage: "power", shortcut: "⌘Q") {
                    NSApplication.shared.terminate(nil)
                }
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
        HStack(spacing: 11) {
            Image(systemName: model.isRecording ? "record.circle.fill" : "mic.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(model.isRecording ? AnyShapeStyle(.red) : AnyShapeStyle(Brand.signal))
            VStack(alignment: .leading, spacing: 2) {
                Text("Local Dictation")
                    .font(.headline)
                HStack(spacing: 5) {
                    Text(model.status)
                        .foregroundStyle(statusColor)
                        .fontWeight(.medium)
                    Text("·").foregroundStyle(.tertiary)
                    Text(shortcutLabel)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }

    /// A tight stack of menu rows whose hover highlight bleeds slightly toward the
    /// popover edges (negative inset) while the row text stays aligned with the header.
    @ViewBuilder
    private func menuGroup<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 2) { content() }
            .padding(.horizontal, -10)
    }

    private var statusColor: Color {
        switch model.status {
        case "Inserted": Brand.emerald
        case "Error": .red
        case "Listening", "Transcribing": .primary
        default: .secondary
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

/// A full-width, left-aligned menu row with a leading SF Symbol and an emerald
/// hover highlight — the popover's menu items, styled to match the dictation HUD
/// rather than rendering as default bordered buttons.
private struct MenuRow: View {
    let title: String
    let systemImage: String
    var shortcut: String? = nil
    var disabled = false
    let action: () -> Void

    @State private var hovering = false

    private var highlighted: Bool { hovering && !disabled }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .frame(width: 16)
                Text(title)
                Spacer(minLength: 8)
                if let shortcut {
                    Text(shortcut)
                        .foregroundStyle(highlighted ? Brand.onSignal.opacity(0.75) : Color.secondary)
                }
            }
            .font(.callout)
            .foregroundStyle(highlighted ? Brand.onSignal : .primary)
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Brand.signal)
                    .opacity(highlighted ? 1 : 0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .onHover { hovering = $0 }
    }
}
