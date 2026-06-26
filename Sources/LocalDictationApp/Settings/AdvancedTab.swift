import LocalDictationCore
import SwiftUI

struct AdvancedTab: View {
    @Binding var whisperExecutablePath: String
    @Binding var modelPath: String
    @Binding var customVocabulary: String
    @Binding var useDefaultVocabulary: Bool
    @Binding var useContextAwareness: Bool
    @Binding var useScreenOCR: Bool
    @Binding var insertionMethod: String
    @Binding var smartSpacing: Bool
    @Binding var useTextReplacements: Bool
    @Binding var textReplacements: String
    @AppStorage(AppSettingsKeys.crashReportingEnabled) private var crashReportingEnabled = false
    @AppStorage(AppSettingsKeys.keepRecentRecordings) private var keepRecentRecordings = false

    var body: some View {
        Form {
            Section("Recognition") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom vocabulary")
                        .font(.callout)
                    TextEditor(text: $customVocabulary)
                        .font(.body.monospaced())
                        .frame(minHeight: 64)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.3)))
                    Text("Names, jargon, and terms you use — whisper leans toward these, so they're mis-heard less.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Use built-in vocabulary", isOn: $useDefaultVocabulary)
                    .help("Bias toward common terms (Claude, GitHub, TypeScript, …) so they transcribe correctly without adding them yourself. Your own vocabulary always takes priority.")
                Toggle("Use context around your cursor", isOn: $useContextAwareness)
                    .help("Read the focused app and the text just before your cursor (Accessibility — no screen recording) to bias recognition and fix context-only mishearings, e.g. \"me\" → \"main\" when you dictate a branch after `git push origin`. On-device and transient; secure fields are never read.")
                if useContextAwareness {
                    Toggle("Read on-screen text (OCR) for context", isOn: $useScreenOCR)
                        .help("Always screenshot the focused window and read it with on-device OCR, so what's on screen biases recognition toward what you're working on — not just a fallback when Accessibility text is missing. Needs Screen Recording permission. Off by default; the image is read and discarded, never stored.")
                        .onChange(of: useScreenOCR) { _, enabled in
                            if enabled { ScreenOCR.requestPermission() }
                        }
                }
            }

            Section("Insertion") {
                Picker("Insert text by", selection: $insertionMethod) {
                    Text("Pasting (fast)").tag(InsertionMethod.paste.rawValue)
                    Text("Typing keystrokes").tag(InsertionMethod.keystroke.rawValue)
                }
                .help("Keystroke typing works in terminals, password fields, and apps that block paste — and never touches your clipboard. Pasting is faster for long text.")
                Toggle("Smart spacing & capitalization", isOn: $smartSpacing)
                    .help("Read the text around your cursor (Accessibility) to lowercase a mid-sentence continuation and add a leading space automatically.")
            }

            Section {
                Toggle("Enable text replacements", isOn: $useTextReplacements)
                if useTextReplacements {
                    TextEditor(text: $textReplacements)
                        .font(.body.monospaced())
                        .frame(minHeight: 80)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.3)))
                }
            } header: {
                Text("Text replacements")
            } footer: {
                Text("One rule per line, e.g. `teh => the` or `my address => 12 Oak Street`. Whole-word, case-insensitive; applied after transcription. Distinct from vocabulary (which biases recognition).")
            }

            Section {
                Toggle("Send crash reports to the developer", isOn: $crashReportingEnabled)
                    .help("If LocalDictation crashes, send the macOS crash report (app version, your macOS version, and a technical backtrace — never your dictation text, audio, or transcripts) so it can be fixed. Uploaded on the next launch after a crash.")
                Toggle("Keep recent recordings for troubleshooting", isOn: $keepRecentRecordings)
                    .help("Save a copy of each dictation recording locally. Handy when a transcription seems cut short — you can replay the audio to see what was captured. The last 10 recordings are kept; older ones are deleted automatically after 7 days.")
                if keepRecentRecordings {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Stores the last 10 recordings (auto-deleted after 7 days). Audio is never sent anywhere.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Reveal in Finder") { RecentRecordings.revealInFinder() }
                            .buttonStyle(.bordered)
                    }
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("You can also grab the latest report yourself from the menu-bar icon → Copy Last Crash Report.")
            }

            Section {
                DisclosureGroup("Overrides") {
                    TextField("whisper-cli path", text: $whisperExecutablePath)
                    TextField("Model path", text: $modelPath)
                }
            } footer: {
                Text("Override the binary or model file directly. Normally the Models tab manages the model for you.")
            }
        }
        .formStyle(.grouped)
    }
}
