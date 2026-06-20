import SwiftUI

struct AdvancedTab: View {
    @Binding var whisperExecutablePath: String
    @Binding var modelPath: String
    @Binding var customVocabulary: String
    @Binding var useHistoryContext: Bool

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
                Toggle("Use recent transcripts as context", isOn: $useHistoryContext)
                    .help("Bias recognition toward words from your recent dictations. All on-device.")
            }

            Section {
                TextField("whisper-cli path", text: $whisperExecutablePath)
                TextField("Model path", text: $modelPath)
            } footer: {
                Text("Override the binary or model file directly. Normally the Models tab manages the model for you.")
            }
        }
        .formStyle(.grouped)
    }
}
