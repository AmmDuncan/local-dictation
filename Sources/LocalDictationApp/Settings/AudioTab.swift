import SwiftUI

struct AudioTab: View {
    @Binding var deviceUID: String

    var body: some View {
        Form {
            Section("Microphone") {
                AudioInputSection(deviceUID: $deviceUID)
            }
        }
        .formStyle(.grouped)
    }
}
