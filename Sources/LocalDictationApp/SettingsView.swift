import LocalDictationCore
import SwiftUI

private enum SettingsTab: Hashable {
    case general, models, audio, apps, advanced
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
    @AppStorage(AppSettingsKeys.dictationMode) private var dictationMode = AppSettingsSnapshot.Defaults.dictationMode
    @AppStorage(AppSettingsKeys.activationMode) private var activationMode = AppSettingsSnapshot.Defaults.activationMode
    @AppStorage(AppSettingsKeys.saveHistory) private var saveHistory = AppSettingsSnapshot.Defaults.saveHistory
    @AppStorage(AppSettingsKeys.insertionMethod) private var insertionMethod = AppSettingsSnapshot.Defaults.insertionMethod
    @AppStorage(AppSettingsKeys.smartSpacing) private var smartSpacing = AppSettingsSnapshot.Defaults.smartSpacing
    @AppStorage(AppSettingsKeys.useTextReplacements) private var useTextReplacements = AppSettingsSnapshot.Defaults.useTextReplacements
    @AppStorage(AppSettingsKeys.textReplacements) private var textReplacements = AppSettingsSnapshot.Defaults.textReplacements
    @AppStorage(AppSettingsKeys.useAppProfiles) private var useAppProfiles = AppSettingsSnapshot.Defaults.useAppProfiles

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
                dictationMode: $dictationMode,
                activationMode: $activationMode,
                saveHistory: $saveHistory,
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

            AppsTab(useAppProfiles: $useAppProfiles, defaultMode: $dictationMode)
                .tabItem { Label("Apps", systemImage: "app.badge") }
                .tag(SettingsTab.apps)

            AdvancedTab(
                whisperExecutablePath: $whisperExecutablePath,
                modelPath: $modelPath,
                customVocabulary: $customVocabulary,
                useHistoryContext: $useHistoryContext,
                insertionMethod: $insertionMethod,
                smartSpacing: $smartSpacing,
                useTextReplacements: $useTextReplacements,
                textReplacements: $textReplacements
            )
            .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
            .tag(SettingsTab.advanced)
        }
        .frame(width: 560, height: 580)
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
