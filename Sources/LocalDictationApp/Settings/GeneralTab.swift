@preconcurrency import KeyboardShortcuts
import SwiftUI

struct GeneralTab: View {
    var readiness: ReadinessModel
    @Binding var pasteOnRelease: Bool
    @Binding var showOverlay: Bool
    @Binding var cleanUpTranscript: Bool
    @Binding var polishWithAI: Bool
    @Binding var language: String
    var refresh: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HealthStripView(readiness: readiness)
                .padding([.horizontal, .top], 16)

            Form {
                Section("Shortcut") {
                    KeyboardShortcuts.Recorder("Hold to dictate", name: .holdToDictate)
                }

                Section("Output") {
                    Toggle("Paste on release", isOn: $pasteOnRelease)
                        .help("When on, your spoken words are typed into whatever you're writing. Requires Accessibility permission.")
                    Toggle("Show live preview", isOn: $showOverlay)
                        .help("Show a floating panel with your words as you speak.")
                    Toggle("Clean up dictation", isOn: $cleanUpTranscript)
                        .help("Before typing, remove filler words (um, uh) and fix capitalization & spacing. Never changes your wording.")
                    Toggle("Polish with AI (experimental)", isOn: $polishWithAI)
                        .help("Run a small on-device model (Qwen 3B) to fix punctuation, capitalization, and remove fillers — never changing your meaning. Needs the model in ~/models and keeps a resident process (extra RAM). All on-device.")
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
            }
            .formStyle(.grouped)
        }
        .onChange(of: pasteOnRelease) { refresh() }
    }
}
