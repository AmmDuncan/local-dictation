import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettingsKeys.whisperExecutablePath) private var whisperExecutablePath = AppSettingsSnapshot.Defaults.whisperExecutablePath
    @AppStorage(AppSettingsKeys.modelPath) private var modelPath = AppSettingsSnapshot.Defaults.modelPath
    @AppStorage(AppSettingsKeys.language) private var language = AppSettingsSnapshot.Defaults.language
    @AppStorage(AppSettingsKeys.pasteOnRelease) private var pasteOnRelease = AppSettingsSnapshot.Defaults.pasteOnRelease
    @AppStorage(AppSettingsKeys.showOverlay) private var showOverlay = AppSettingsSnapshot.Defaults.showOverlay
    @AppStorage(AppSettingsKeys.inputDeviceUID) private var inputDeviceUID = AppSettingsSnapshot.Defaults.inputDeviceUID
    @AppStorage(AppSettingsKeys.cleanUpTranscript) private var cleanUpTranscript = AppSettingsSnapshot.Defaults.cleanUpTranscript

    @State private var readiness = ReadinessModel()
    @State private var store = ModelStore()

    var body: some View {
        TabView {
            GeneralTab(
                readiness: readiness,
                pasteOnRelease: $pasteOnRelease,
                showOverlay: $showOverlay,
                cleanUpTranscript: $cleanUpTranscript,
                language: $language,
                refresh: refresh
            )
            .tabItem { Label("General", systemImage: "gearshape") }

            ModelsTab(store: store, onModelChanged: refresh)
                .tabItem { Label("Models", systemImage: "cpu") }
                .badge(store.installedIDs.isEmpty ? Text("!") : nil)

            AudioTab(deviceUID: $inputDeviceUID)
                .tabItem { Label("Audio", systemImage: "mic") }

            AdvancedTab(whisperExecutablePath: $whisperExecutablePath, modelPath: $modelPath)
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 540, height: 540)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
        .onChange(of: modelPath) { refresh() }
    }

    private func refresh() {
        store.refresh()
        readiness.refresh()
    }
}
