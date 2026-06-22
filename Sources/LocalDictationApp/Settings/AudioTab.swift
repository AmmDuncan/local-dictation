import SwiftUI

struct AudioTab: View {
    @Binding var deviceUID: String
    /// True only while the Audio tab is selected. The level meter opens the mic,
    /// so it must run only while this tab is actually showing — otherwise the mic
    /// stays active after switching tabs (and Bluetooth headphones drop to
    /// low-quality call mode). macOS TabView keeps off-screen tabs alive, so
    /// onDisappear alone isn't enough.
    var isActive: Bool

    var body: some View {
        Form {
            Section {
                AudioInputSection(deviceUID: $deviceUID, isActive: isActive)
            } header: {
                Text("Microphone")
            } footer: {
                Text("“System Default” follows macOS but prefers your built-in mic over Bluetooth — a Bluetooth mic forces call mode (lower quality, slow to start). Pick a device above to override.")
            }
        }
        .formStyle(.grouped)
    }
}
