@preconcurrency import KeyboardShortcuts
import SwiftUI

struct GeneralTab: View {
    var readiness: ReadinessModel
    @Binding var transcriptionEngine: String
    @Binding var pasteOnRelease: Bool
    @Binding var showOverlay: Bool
    @Binding var overlayStyle: String
    @Binding var cleanUpTranscript: Bool
    @Binding var polishWithAI: Bool
    var polishStore: PolishModelStore
    @Binding var language: String
    @Binding var saveHistory: Bool
    @Binding var contextSubstitutionEnabled: Bool
    @Binding var contextSubstitutionCountdown: Double
    var refresh: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HealthStripView(readiness: readiness)
                .padding([.horizontal, .top], 16)

            Form {
                Section {
                    KeyboardShortcuts.Recorder("Hold to talk", name: .holdToDictate)
                        .help("Record while this key is held down, release to insert. ⌃Space by default. Note: macOS also uses ⌃Space to switch input sources — if you have more than one, pick a different key here.")
                    KeyboardShortcuts.Recorder("Tap to start / stop", name: .toggleDictate)
                        .help("Hands-free: tap once to start, tap again to stop. Leave empty if you only want hold-to-talk. Esc cancels either way.")
                    KeyboardShortcuts.Recorder("Review last dictation", name: .reviewLastDictation)
                        .help("Opens the review panel for your most recent dictation, where you can revert a correction or teach a fix. ⌃⌥Z by default — rebind it if it clashes with another app (e.g. a screenshot tool on ⌥Z).")
                } header: {
                    Text("Shortcuts")
                } footer: {
                    Text("Set either or both — pick the dictation key by feel: hold-to-talk for a quick burst, tap-to-toggle for hands-free.")
                }

                if #available(macOS 26, *) {
                    Section {
                        Picker("Engine", selection: $transcriptionEngine) {
                            Text("Whisper — local model").tag("whisper")
                            Text("Apple — built-in, no download").tag("apple")
                        }
                        .help("Whisper runs a local whisper.cpp model you download. Apple uses macOS's built-in on-device speech recognition: nothing to download, and it streams as you speak. Both are fully on-device.")
                    } header: {
                        Text("Recognition")
                    } footer: {
                        Text(transcriptionEngine == "apple"
                            ? "Using Apple's on-device recognition. The Models tab (Whisper) doesn't apply while this is selected."
                            : "Using a local Whisper model. Pick or download one in the Models tab.")
                    }
                }

                Section("Output") {
                    Toggle("Paste on release", isOn: $pasteOnRelease)
                        .help("When on, your spoken words are typed into whatever you're writing. Requires Accessibility permission.")
                    Toggle("Show overlay", isOn: $showOverlay)
                        .help("Show a floating panel while you dictate.")
                    if showOverlay {
                        Picker("Overlay style", selection: $overlayStyle) {
                            Text("Compact — waveform only").tag("compact")
                            Text("Standard — live transcript").tag("standard")
                        }
                        .help("Compact shows just a waveform pill and injects the final text (no flickering partial text). Standard shows the live transcript as you speak.")
                    }
                    Toggle("Clean up dictation", isOn: $cleanUpTranscript)
                        .help("Before typing, remove filler words (um, uh) and fix capitalization & spacing. Never changes your wording.")
                    Toggle(isOn: $polishWithAI) {
                        ExperimentalLabel("Polish with AI")
                    }
                    .help("Run a small on-device model (Qwen 3B) to fix punctuation, capitalization, fillers, and misheard names/terms — using your vocabulary (e.g. \"clot\" → \"Claude\"). Keeps a resident process (extra RAM). All on-device.")

                    if polishWithAI {
                        polishModelRow
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

                Section("Experimental") {
                    Toggle(isOn: $contextSubstitutionEnabled) {
                        ExperimentalLabel("Context substitution")
                    }
                    .help("Fix misheard tech terms using what's on your screen. Each swap is held in the overlay with a countdown — you confirm or undo before it's typed. Uses your selected AI model (Models tab). On-device.")
                    if contextSubstitutionEnabled {
                        HStack {
                            Text("Countdown")
                            Slider(value: $contextSubstitutionCountdown, in: 2...10, step: 0.5)
                            Text("\(contextSubstitutionCountdown, specifier: "%.1f")s").monospacedDigit()
                        }
                    }
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
                .foregroundStyle(Brand.emerald)
        } else {
            Text("No polish model installed — choose & download one in the Models tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
