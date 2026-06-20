@preconcurrency import KeyboardShortcuts
import LocalDictationCore
import SwiftUI

@main
struct LocalDictationApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @StateObject private var updater = UpdaterModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("Local Dictation", systemImage: "mic") {
            MenuBarView(model: model, updater: updater)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shotWindow: NSWindow?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["LD_METER_TEST"] != nil {
            runMeterTest()
            return
        }
        if ProcessInfo.processInfo.environment["LD_DICTATE_TEST"] != nil {
            runDictateTest()
            return
        }
        if let path = ProcessInfo.processInfo.environment["LD_SCREENSHOT"] {
            captureSettingsWindow(to: path)
            return
        }
        if let path = ProcessInfo.processInfo.environment["LD_OVERLAY_SHOT"] {
            captureOverlay(to: path)
            return
        }
        #endif

        // Point the bundled whisper-cli at its bundled ggml backend plugins.
        WhisperLocator.ensureBackendsLinked()

        // Accessibility is requested in-context the first time the user dictates
        // (see AppModel.beginHold) — not on cold launch, which reads as spyware.

        // Opening Settings flips the app to .regular so the window can come
        // forward; revert to menu-bar-only once no normal window remains.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                let stillOpen = NSApp.windows.contains {
                    $0.isVisible && $0.styleMask.contains(.titled) && $0.frame.width > 300
                }
                if !stillOpen {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    #if DEBUG
    private var testMeter: AudioLevelMeter?

    /// Dev-only: exercises the recorder start/stop path (the source of any
    /// "Audio…" error in the dictation overlay). Triggered by LD_DICTATE_TEST.
    @MainActor
    private func runDictateTest() {
        Task { @MainActor in
            let recorder = AudioFileRecorder()
            do {
                try await recorder.startRecording()
                try? await Task.sleep(for: .milliseconds(800))
                let url = try await recorder.stopRecording()
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int ?? -1
                FileHandle.standardError.write(Data("DICTATE_TEST_OK wav=\(url.lastPathComponent) bytes=\(size) level=\(recorder.currentLevel)\n".utf8))
                try? FileManager.default.removeItem(at: url)
            } catch {
                FileHandle.standardError.write(Data("DICTATE_TEST_FAIL: \(error)\n".utf8))
            }
            exit(0)
        }
    }

    /// Dev-only: runs the live audio-level meter (the path that crashed) for a
    /// few seconds, then exits 0. A SIGTRAP means the tap closure is still
    /// main-actor-isolated. Triggered by LD_METER_TEST.
    @MainActor
    private func runMeterTest() {
        let meter = AudioLevelMeter()
        testMeter = meter
        meter.start(deviceUID: "")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            FileHandle.standardError.write(Data("METER_TEST_OK isRunning=\(meter.isRunning) level=\(meter.level)\n".utf8))
            exit(0)
        }
    }

    /// Dev-only: renders the real `SettingsView` in a window to a PNG, then
    /// exits. Triggered by the LD_SCREENSHOT env var. In-process `cacheDisplay`,
    /// so no screen-recording permission is involved. Compiled out of release.
    @MainActor
    private func captureSettingsWindow(to path: String) {
        NSApp.setActivationPolicy(.regular)
        let hosting = NSHostingView(rootView: SettingsView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 700),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        shotWindow = window
        NSApp.activate(ignoringOtherApps: true)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            let view = hosting
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                exit(1)
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
            exit(0)
        }
    }

    /// Dev-only: renders all four overlay states over a backdrop to a PNG.
    @MainActor
    private func captureOverlay(to path: String) {
        NSApp.setActivationPolicy(.regular)
        let hosting = NSHostingView(rootView: OverlayPreview())
        let size = NSSize(width: 460, height: 880)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        shotWindow = window
        NSApp.activate(ignoringOtherApps: true)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { exit(1) }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
            exit(0)
        }
    }
    #endif
}

#if DEBUG
/// Dev-only composite of all four overlay states for screenshot verification.
private struct OverlayPreview: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.15, green: 0.20, blue: 0.29), Color(red: 0.06, green: 0.08, blue: 0.12)],
                startPoint: .top, endPoint: .bottom
            )
            VStack(spacing: 16) {
                cell(.listening, "She sells sea shells by the sea shore, and the shells she sells are surely seashells, so I'm sure she sells seashore shells.", 0.6, 196)
                cell(.transcribing, "", 0, 150)
                cell(.done, "She sells sea shells by the sea shore.", 0, 240)
                errorCell()
            }
            .padding(24)
        }
        .frame(width: 460, height: 880)
    }

    @MainActor
    private func cell(_ phase: DictationPhase, _ detail: String, _ level: Double, _ height: CGFloat) -> some View {
        let state = OverlayState()
        state.phase = phase
        state.title = title(for: phase)
        state.detail = detail
        state.level = level
        return OverlayView(state: state).frame(width: 404, height: height)
    }

    @MainActor
    private func errorCell() -> some View {
        let state = OverlayState()
        state.phase = .error
        state.title = "Microphone is off"
        state.detail = "Local Dictation needs the microphone to transcribe. Grant access in System Settings — it stays on your Mac."
        state.actionTitle = "Open Settings"
        return OverlayView(state: state).frame(width: 404, height: 214)
    }

    private func title(for phase: DictationPhase) -> String {
        switch phase {
        case .listening: "Listening"
        case .transcribing: "Transcribing"
        case .done: "Inserted"
        case .error: "Error"
        }
    }
}
#endif

extension KeyboardShortcuts.Name {
    @MainActor
    static let holdToDictate = Self("holdToDictate", default: .init(.space, modifiers: [.control]))
}
