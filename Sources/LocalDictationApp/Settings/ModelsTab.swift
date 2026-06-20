import SwiftUI

struct ModelsTab: View {
    var store: ModelStore
    var onModelChanged: () -> Void

    var body: some View {
        Form {
            Section {
                ModelManagerView(store: store, onModelChanged: onModelChanged)
            } footer: {
                Text("Larger models are more accurate; your Mac runs even the largest in well under a second. Smaller models are faster to download and run.")
            }
        }
        .formStyle(.grouped)
    }
}
