import AppKit
import LocalDictationCore
import SwiftUI
import UniformTypeIdentifiers

/// Per-app dictation profiles: pick a mode (and cleanup/polish) that activates
/// automatically when you dictate into a given app. Stored as JSON under the
/// `appProfiles` key; resolution happens in AppModel via `AppProfileResolver`.
@MainActor
@Observable
final class ProfilesModel {
    var profiles: [AppProfile] = []

    init() { load() }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: AppSettingsKeys.appProfiles),
              let decoded = try? JSONDecoder().decode([AppProfile].self, from: data) else {
            profiles = []
            return
        }
        profiles = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: AppSettingsKeys.appProfiles)
    }

    // add/remove are pure mutations; persistence is owned by the view's
    // onChange(of: profiles), which also covers in-place row edits.
    func add(bundleID: String, name: String) {
        guard !profiles.contains(where: { $0.bundleIdentifier.caseInsensitiveCompare(bundleID) == .orderedSame }) else { return }
        profiles.append(AppProfile(bundleIdentifier: bundleID, appName: name, mode: .clean, cleanUp: true, polish: false))
    }

    func remove(_ bundleID: String) {
        profiles.removeAll { $0.bundleIdentifier == bundleID }
    }
}

struct AppsTab: View {
    @Binding var useAppProfiles: Bool
    @Binding var defaultMode: String
    @State private var model = ProfilesModel()

    private var defaultModeName: String {
        (DictationMode(rawValue: defaultMode) ?? .clean).displayName
    }

    var body: some View {
        Form {
            Section {
                Toggle("Switch mode automatically per app", isOn: $useAppProfiles)
                    .help("When on, dictating into a listed app uses that app's mode; everything else uses the default mode (General tab).")
            } footer: {
                Text("Match the frontmost app you're dictating INTO. Unlisted apps fall back to your default mode (\(defaultModeName)).")
            }

            Section("Per-app modes") {
                if model.profiles.isEmpty {
                    Text("No apps configured. Add one to give it its own mode (e.g. Xcode → Code, Mail → Email).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($model.profiles, id: \.bundleIdentifier) { $profile in
                        profileRow($profile)
                    }
                }
                Button { addApp() } label: { Label("Add app…", systemImage: "plus") }
                    .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .disabled(!useAppProfiles)
        .onChange(of: model.profiles) { model.save() }
        .onAppear { model.load() }
    }

    @ViewBuilder
    private func profileRow(_ profile: Binding<AppProfile>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.wrappedValue.appName).fontWeight(.medium)
                    Text(profile.wrappedValue.bundleIdentifier)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) { model.remove(profile.wrappedValue.bundleIdentifier) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            Picker("Mode", selection: profile.mode) {
                ForEach(DictationMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            HStack(spacing: 16) {
                Toggle("Clean up", isOn: profile.cleanUp)
                Toggle("Polish", isOn: profile.polish)
            }
            .toggleStyle(.checkbox)
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bundleID = Bundle(url: url)?.bundleIdentifier ?? url.deletingPathExtension().lastPathComponent
        let name = FileManager.default.displayName(atPath: url.path)
        model.add(bundleID: bundleID, name: name)
    }
}
