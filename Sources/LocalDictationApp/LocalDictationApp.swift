import ApplicationServices
@preconcurrency import KeyboardShortcuts
import LocalDictationCore
import SwiftUI

/// Opens the Settings window reliably from anywhere (menu + overlay error
/// action). For an accessory app `NSApp.sendAction(showSettingsWindow:)` is
/// flaky, so we capture SwiftUI's `openSettings` action at launch and call that;
/// the selector is only a last-resort fallback.
@MainActor
enum SettingsLauncher {
    static var openAction: (() -> Void)?

    static func open() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let openAction {
            openAction()
        } else {
            let sel = NSApp.responds(to: Selector(("showSettingsWindow:")))
                ? Selector(("showSettingsWindow:"))
                : Selector(("showPreferencesWindow:"))
            NSApp.sendAction(sel, to: nil, from: nil)
        }
    }
}

/// Opens the History window (captured `openWindow` action, same pattern).
@MainActor
enum HistoryWindowLauncher {
    static var openAction: (() -> Void)?

    static func open() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openAction?()
    }
}

/// External control surface for scripting/automation. AppModel registers these;
/// the SIGUSR1/SIGUSR2 handlers (AppDelegate) and any future hooks call them.
@MainActor
enum DictationControl {
    static var toggle: (() -> Void)?
    static var cancel: (() -> Void)?
}

@main
struct LocalDictationApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @StateObject private var updater = UpdaterModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model, updater: updater)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Window("Dictation History", id: "history") {
            HistoryView()
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }
}

/// The menu-bar icon. Also the earliest always-present SwiftUI view, so it's
/// where we capture the `openSettings` / `openWindow` actions for the launchers.
private struct MenuBarLabel: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "mic")
            .onAppear {
                SettingsLauncher.openAction = { openSettings() }
                HistoryWindowLauncher.openAction = { openWindow(id: "history") }
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shotWindow: NSWindow?
    private var signalSources: [DispatchSourceSignal] = []

    /// Scriptable control: SIGUSR1 toggles dictation, SIGUSR2 cancels it, so the
    /// app can be driven headlessly (e.g. `kill -USR1 $(pgrep -f LocalDictation)`)
    /// from Raycast/Alfred/shell without a hotkey. DispatchSource delivers the
    /// signal on the main queue, where it's safe to touch UI/AppModel.
    @MainActor
    private func installSignalControls() {
        for (sig, handler) in [(SIGUSR1, { DictationControl.toggle?() }),
                               (SIGUSR2, { DictationControl.cancel?() })] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { handler() } }
            source.resume()
            signalSources.append(source)
        }
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Diagnostic (release-available, env-gated): verify the live AX context
        // pipeline at runtime without a microphone — see runContextProbe. No-op
        // unless LD_CONTEXT_PROBE is set, so it's inert in normal use.
        if let path = ProcessInfo.processInfo.environment["LD_CONTEXT_PROBE"] {
            runContextProbe(to: path)
            return
        }

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

        // New-install defaults (no-op for existing users).
        FirstRunSetup.applyIfNeeded()

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

        installSignalControls()
    }

    /// Diagnostic (env LD_CONTEXT_PROBE=<file>): lets the context pipeline be
    /// verified at runtime WITHOUT a microphone. Logs accessibility/OCR-permission
    /// state, then polls ~20s recording, per tick, the frontmost app, its class,
    /// the caret-preceding text, and how much AX window text (`visibleText`) was
    /// read. On the first non-self app with any context it records the extracted
    /// candidates and the command-mode result for a sample "me" — proving the
    /// gather → classify → substitute chain on real input. With LD_PROBE_OCR set it
    /// also runs the opt-in OCR fallback and logs what it read. The spoken-ASR step
    /// still needs a person; everything before it does not.
    @MainActor
    private func runContextProbe(to path: String) {
        let wantOCR = ProcessInfo.processInfo.environment["LD_PROBE_OCR"] != nil
        if ProcessInfo.processInfo.environment["LD_PROBE_OCR_REQUEST"] != nil {
            ScreenOCR.requestPermission()  // diagnostic: prompt for Screen Recording
        }
        Task { @MainActor in
            var log = "AXIsProcessTrusted=\(AXIsProcessTrusted()) screenRecordingPermission=\(ScreenOCR.hasPermission)\n"
            func flush() { try? log.write(toFile: path, atomically: true, encoding: .utf8) }
            flush()
            for tick in 0..<40 {
                let ctx = AccessibilityContextProvider.gather()
                let app = ctx.activeApplicationName ?? "nil"
                let cls = ContextBias.classify(appName: ctx.activeApplicationName)
                let pre = ctx.precedingText
                let vis = ctx.visibleText
                log += "tick \(tick): app=\(app) class=\(cls.rawValue) preceding=\(pre.map { "\"\($0)\"" } ?? "nil") visibleChars=\(vis?.count ?? 0)\n"
                let hasContext = (pre?.isEmpty == false) || (vis?.isEmpty == false)
                if app != "nil", app != "LocalDictation", hasContext {
                    let candidates = ContextBias.candidates(precedingText: pre, visibleText: vis)
                    log += "CAPTURE candidates(\(candidates.count)): \(candidates.prefix(12).joined(separator: ", "))\n"
                    log += "CAPTURE command_mode: \"me\" -> \"\(CommandModeCorrections.apply(to: "me", appClass: cls, precedingText: pre))\"\n"
                    if wantOCR {
                        let ocr = await ScreenOCR.recognizeFocusedWindow()
                        log += "CAPTURE ocr_capture: \(ocr.map { "\"\(String($0.prefix(240)))\"" } ?? "nil (no Screen Recording permission / no text)")\n"
                        // Verify the Vision recognition step on a synthetic image —
                        // proves OCR reads text even when the (permission-gated)
                        // screen capture can't run.
                        let sample = "git push origin main feature/context-aware UserStore.swift"
                        if let image = Self.renderTextImage(sample) {
                            log += "CAPTURE ocr_selftest: \(ScreenOCR.recognize(image).map { "\"\($0)\"" } ?? "nil")\n"
                        }
                    }
                    flush()
                    exit(0)
                }
                flush()
                try? await Task.sleep(for: .milliseconds(500))
            }
            log += "DONE (no non-self focused context captured)\n"
            flush()
            exit(1)
        }
    }

    /// Render text to a white-on-black image, for the OCR self-test (verifies the
    /// Vision recognition step without Screen Recording). Diagnostic-only.
    @MainActor
    private static func renderTextImage(_ text: String) -> CGImage? {
        let size = NSSize(width: 900, height: 120)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        text.draw(at: NSPoint(x: 20, y: 44), withAttributes: [
            .font: NSFont.systemFont(ofSize: 34),
            .foregroundColor: NSColor.black,
        ])
        image.unlockFocus()
        var rect = NSRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
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
        let size = NSSize(width: 520, height: 1320)
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
                cell(.listening, "She sells sea shells by the sea shore, and the shells she sells are surely seashells, so I'm sure she sells seashore shells.", 0.6, 284)
                cell(.transcribing, "", 0, 210)
                cell(.done, "She sells sea shells by the sea shore.", 0, 300)
                errorCell()
                cell(.cancelled, "", 0, 200)
            }
            .padding(24)
        }
        .frame(width: 520, height: 1320)
    }

    @MainActor
    private func cell(_ phase: DictationPhase, _ detail: String, _ level: Double, _ height: CGFloat) -> some View {
        let state = OverlayState()
        state.phase = phase
        state.title = title(for: phase)
        state.detail = detail
        state.level = level
        return OverlayView(state: state).frame(width: 464, height: height)
    }

    @MainActor
    private func errorCell() -> some View {
        let state = OverlayState()
        state.phase = .error
        state.title = "Microphone is off"
        state.detail = "Local Dictation needs the microphone to transcribe. Grant access in System Settings — it stays on your Mac."
        state.actionTitle = "Open Settings"
        return OverlayView(state: state).frame(width: 464, height: 274)
    }

    private func title(for phase: DictationPhase) -> String {
        switch phase {
        case .listening: "Listening"
        case .transcribing: "Transcribing"
        case .done: "Inserted"
        case .error: "Error"
        case .cancelled: "Cancelled"
        }
    }
}
#endif

extension KeyboardShortcuts.Name {
    @MainActor
    static let holdToDictate = Self("holdToDictate", default: .init(.space, modifiers: [.control]))
    /// Opens the review panel for the last dictation (Door #1). Pressing it while
    /// the "Typed" card is up — or any time after — reviews the most recent result.
    @MainActor
    static let reviewLastDictation = Self("reviewLastDictation", default: .init(.z, modifiers: [.option]))
}
