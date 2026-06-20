import SwiftUI

private enum SettingsTab: Hashable {
    case general, models, audio, advanced
}

struct SettingsView: View {
    @AppStorage(AppSettingsKeys.whisperExecutablePath) private var whisperExecutablePath = AppSettingsSnapshot.Defaults.whisperExecutablePath
    @AppStorage(AppSettingsKeys.modelPath) private var modelPath = AppSettingsSnapshot.Defaults.modelPath
    @AppStorage(AppSettingsKeys.language) private var language = AppSettingsSnapshot.Defaults.language
    @AppStorage(AppSettingsKeys.pasteOnRelease) private var pasteOnRelease = AppSettingsSnapshot.Defaults.pasteOnRelease
    @AppStorage(AppSettingsKeys.showOverlay) private var showOverlay = AppSettingsSnapshot.Defaults.showOverlay
    @AppStorage(AppSettingsKeys.inputDeviceUID) private var inputDeviceUID = AppSettingsSnapshot.Defaults.inputDeviceUID
    @AppStorage(AppSettingsKeys.cleanUpTranscript) private var cleanUpTranscript = AppSettingsSnapshot.Defaults.cleanUpTranscript
    @AppStorage(AppSettingsKeys.polishWithAI) private var polishWithAI = AppSettingsSnapshot.Defaults.polishWithAI
    @AppStorage(AppSettingsKeys.customVocabulary) private var customVocabulary = AppSettingsSnapshot.Defaults.customVocabulary
    @AppStorage(AppSettingsKeys.useHistoryContext) private var useHistoryContext = AppSettingsSnapshot.Defaults.useHistoryContext

    @State private var readiness = ReadinessModel()
    @State private var store = ModelStore()
    @State private var polishStore = PolishModelStore()
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab(
                readiness: readiness,
                pasteOnRelease: $pasteOnRelease,
                showOverlay: $showOverlay,
                cleanUpTranscript: $cleanUpTranscript,
                polishWithAI: $polishWithAI,
                polishStore: polishStore,
                language: $language,
                refresh: refresh
            )
            .tabItem { Label("General", systemImage: "gearshape") }
            .tag(SettingsTab.general)

            ModelsTab(store: store, onModelChanged: refresh)
                .tabItem { Label("Models", systemImage: "cpu") }
                .badge(store.installedIDs.isEmpty ? Text("!") : nil)
                .tag(SettingsTab.models)

            AudioTab(deviceUID: $inputDeviceUID, isActive: selectedTab == .audio)
                .tabItem { Label("Audio", systemImage: "mic") }
                .tag(SettingsTab.audio)

            AdvancedTab(
                whisperExecutablePath: $whisperExecutablePath,
                modelPath: $modelPath,
                customVocabulary: $customVocabulary,
                useHistoryContext: $useHistoryContext
            )
            .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
            .tag(SettingsTab.advanced)
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
        polishStore.refresh()
        readiness.refresh()
    }
}
