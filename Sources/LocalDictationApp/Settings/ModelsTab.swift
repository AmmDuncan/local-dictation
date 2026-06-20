import SwiftUI

struct ModelsTab: View {
    var store: ModelStore
    var polishStore: PolishModelStore
    var onModelChanged: () -> Void

    var body: some View {
        Form {
            Section {
                ModelManagerView(store: store, onModelChanged: onModelChanged)
            } header: {
                Text("Transcription (Whisper)")
            } footer: {
                Text("Larger models are more accurate; your Mac runs even the largest in well under a second. Smaller models are faster to download and run.")
            }

            Section {
                PolishModelManagerView(store: polishStore, onModelChanged: onModelChanged)
            } header: {
                Text("Polish (AI cleanup)")
            } footer: {
                Text("Used only when “Polish with AI” is on (General tab). Runs locally via llama-server. Qwen 2.5-3B is recommended.")
            }
        }
        .formStyle(.grouped)
    }
}
