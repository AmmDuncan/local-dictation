@preconcurrency import KeyboardShortcuts
import LocalDictationCore
import SwiftUI

struct GeneralTab: View {
    var readiness: ReadinessModel
    @Binding var pasteOnRelease: Bool
    @Binding var showOverlay: Bool
    @Binding var cleanUpTranscript: Bool
    @Binding var polishWithAI: Bool
    var polishStore: PolishModelStore
    @Binding var language: String
    @Binding var dictationMode: String
    @Binding var activationMode: String
    @Binding var saveHistory: Bool
    var refresh: () -> Void

    private var selectedMode: DictationMode { DictationMode(rawValue: dictationMode) ?? .clean }

    var body: some View {
        VStack(spacing: 0) {
            HealthStripView(readiness: readiness)
                .padding([.horizontal, .top], 16)

            Form {
                Section("Shortcut") {
                    KeyboardShortcuts.Recorder("Dictation key", name: .holdToDictate)
                        .help("⌃Space is the default. Note: macOS also uses ⌃Space to switch input sources — if you have more than one input source, pick a different key here.")
                    Picker("Activation", selection: $activationMode) {
                        Text("Hold to talk").tag(ActivationMode.hold.rawValue)
                        Text("Tap to start / stop").tag(ActivationMode.toggle.rawValue)
                    }
                    .help("Hold: record while the key is down. Toggle: tap once to start, again to stop. Esc cancels either way.")
                }

                Section("Output") {
                    Toggle("Paste on release", isOn: $pasteOnRelease)
                        .help("When on, your spoken words are typed into whatever you're writing. Requires Accessibility permission.")
                    Toggle("Show live preview", isOn: $showOverlay)
                        .help("Show a floating panel with your words as you speak.")
                    Toggle("Clean up dictation", isOn: $cleanUpTranscript)
                        .help("Before typing, remove filler words (um, uh) and fix capitalization & spacing. Never changes your wording.")
                    Toggle("Polish with AI (experimental)", isOn: $polishWithAI)
                        .help("Run a small on-device model (Qwen 3B) to fix punctuation, capitalization, and remove fillers — never changing your meaning. Keeps a resident process (extra RAM). All on-device.")

                    if polishWithAI {
                        polishModelRow
                        Picker("Mode", selection: $dictationMode) {
                            ForEach(DictationMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode.rawValue)
                            }
                        }
                        .help("How the AI shapes your text. Corrector may fix misheard words; the others keep your exact wording.")
                        Text(selectedMode.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Picker("Language", selection: $language) {
                        Text("Auto-detect").tag("auto")
                        Text("English").tag("en")
                        Text("Spanish").tag("es")
                        Text("French").tag("fr")
                        Text("German").tag("de")
                        Text("Italian").tag("it")
                        Text("Portuguese").tag("pt")
                    }
                    .help("Pick the language you speak, or let Whisper detect it.")
                }

                Section("History") {
                    Toggle("Save dictation history", isOn: $saveHistory)
                        .help("Keep a searchable, text-only history of your dictations (no audio). Open it from the menu-bar icon.")
                }
            }
            .formStyle(.grouped)
        }
        .onChange(of: pasteOnRelease) { refresh() }
    }

    @ViewBuilder
    private var polishModelRow: some View {
        if polishStore.activeModelInstalled {
            Label("Polish model: \(polishStore.activeModelName)", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            Text("No polish model installed — choose & download one in the Models tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
