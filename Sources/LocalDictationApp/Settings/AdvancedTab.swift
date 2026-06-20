import SwiftUI

struct AdvancedTab: View {
    @Binding var whisperExecutablePath: String
    @Binding var modelPath: String

    var body: some View {
        Form {
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
