import SwiftUI

private enum SettingsTab: Hashable {
    case general, models, audio, advanced, learn
}

struct SettingsView: View {
    @AppStorage(AppSettingsKeys.whisperExecutablePath) private var whisperExecutablePath = AppSettingsSnapshot.Defaults.whisperExecutablePath
    @AppStorage(AppSettingsKeys.modelPath) private var modelPath = AppSettingsSnapshot.Defaults.modelPath
    @AppStorage(AppSettingsKeys.language) private var language = AppSettingsSnapshot.Defaults.language
    @AppStorage(AppSettingsKeys.pasteOnRelease) private var pasteOnRelease = AppSettingsSnapshot.Defaults.pasteOnRelease
    @AppStorage(AppSettingsKeys.showOverlay) private var showOverlay = AppSettingsSnapshot.Defaults.showOverlay
    @AppStorage(AppSettingsKeys.overlayStyle) private var overlayStyle = AppSettingsSnapshot.Defaults.overlayStyle
    @AppStorage(AppSettingsKeys.inputDeviceUID) private var inputDeviceUID = AppSettingsSnapshot.Defaults.inputDeviceUID
    @AppStorage(AppSettingsKeys.cleanUpTranscript) private var cleanUpTranscript = AppSettingsSnapshot.Defaults.cleanUpTranscript
    @AppStorage(AppSettingsKeys.polishWithAI) private var polishWithAI = AppSettingsSnapshot.Defaults.polishWithAI
    @AppStorage(AppSettingsKeys.customVocabulary) private var customVocabulary = AppSettingsSnapshot.Defaults.customVocabulary
    @AppStorage(AppSettingsKeys.useDefaultVocabulary) private var useDefaultVocabulary = AppSettingsSnapshot.Defaults.useDefaultVocabulary
    @AppStorage(AppSettingsKeys.useContextAwareness) private var useContextAwareness = AppSettingsSnapshot.Defaults.useContextAwareness
    @AppStorage(AppSettingsKeys.useScreenOCR) private var useScreenOCR = AppSettingsSnapshot.Defaults.useScreenOCR
    @AppStorage(AppSettingsKeys.saveHistory) private var saveHistory = AppSettingsSnapshot.Defaults.saveHistory
    @AppStorage(AppSettingsKeys.insertionMethod) private var insertionMethod = AppSettingsSnapshot.Defaults.insertionMethod
    @AppStorage(AppSettingsKeys.smartSpacing) private var smartSpacing = AppSettingsSnapshot.Defaults.smartSpacing
    @AppStorage(AppSettingsKeys.useTextReplacements) private var useTextReplacements = AppSettingsSnapshot.Defaults.useTextReplacements
    @AppStorage(AppSettingsKeys.textReplacements) private var textReplacements = AppSettingsSnapshot.Defaults.textReplacements
    @AppStorage(AppSettingsKeys.logCorrections) private var logCorrections = AppSettingsSnapshot.Defaults.logCorrections
    @AppStorage(AppSettingsKeys.rejectedBuiltInSwaps) private var rejectedBuiltInSwaps = AppSettingsSnapshot.Defaults.rejectedBuiltInSwaps
    @AppStorage(AppSettingsKeys.contextSubstitutionEnabled) private var contextSubstitutionEnabled = AppSettingsSnapshot.Defaults.contextSubstitutionEnabled
    @AppStorage(AppSettingsKeys.phoneticSnapEnabled) private var phoneticSnapEnabled = AppSettingsSnapshot.Defaults.phoneticSnapEnabled
    @AppStorage(AppSettingsKeys.contextSubstitutionCountdown) private var contextSubstitutionCountdown = AppSettingsSnapshot.Defaults.contextSubstitutionCountdown

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
                overlayStyle: $overlayStyle,
                cleanUpTranscript: $cleanUpTranscript,
                polishWithAI: $polishWithAI,
                polishStore: polishStore,
                language: $language,
                saveHistory: $saveHistory,
                contextSubstitutionEnabled: $contextSubstitutionEnabled,
                contextSubstitutionCountdown: $contextSubstitutionCountdown,
                refresh: refresh
            )
            .tabItem { Label("General", systemImage: "gearshape") }
            .tag(SettingsTab.general)

            ModelsTab(store: store, polishStore: polishStore, onModelChanged: refresh)
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
                useDefaultVocabulary: $useDefaultVocabulary,
                useContextAwareness: $useContextAwareness,
                useScreenOCR: $useScreenOCR,
                insertionMethod: $insertionMethod,
                smartSpacing: $smartSpacing,
                useTextReplacements: $useTextReplacements,
                textReplacements: $textReplacements
            )
            .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
            .tag(SettingsTab.advanced)

            LearnTab(
                logCorrections: $logCorrections,
                textReplacements: $textReplacements,
                rejectedBuiltInSwaps: $rejectedBuiltInSwaps,
                phoneticSnapEnabled: $phoneticSnapEnabled
            )
            .tabItem { Label("Learn", systemImage: "brain") }
            .tag(SettingsTab.learn)
        }
        .frame(width: 560, height: 580)
        .tint(Brand.emerald)
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
