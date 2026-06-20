import AppKit
import ScreenCaptureKit
import Vision

/// Opt-in fallback for apps that expose no accessibility text (canvas / GPU-drawn
/// / some Chromium): screenshot the focused window and read it with Vision OCR.
/// This is the ONE path that needs Screen Recording permission, which is why it's
/// off by default — AX-first stays the norm. Async and run off the mic-critical
/// path; the image is OCR'd and discarded (transient, never stored).
enum ScreenOCR {
    /// Screen Recording permission state, checked without prompting.
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Prompt for Screen Recording permission. No-op if already granted; the user
    /// must then restart the app for the grant to take effect (macOS behaviour).
    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    /// OCR the frontmost app's focused window. Returns recognized text (bounded),
    /// or nil if permission is missing, capture fails, or nothing is recognized.
    /// Never call on the mic-critical path — it's hundreds of ms.
    static func recognizeFocusedWindow(maxChars: Int = 1600) async -> String? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        let main = await MainActor.run {
            (NSWorkspace.shared.frontmostApplication?.processIdentifier, NSScreen.main?.backingScaleFactor ?? 2)
        }
        guard let pid = main.0, let window = await focusedWindow(pid: pid),
              let image = await captureImage(of: window, scale: main.1) else { return nil }
        return recognizeText(in: image, maxChars: maxChars)
    }

    /// The frontmost, on-screen, normal-layer window of the given app — the one
    /// the user is looking at. Largest by area when several qualify.
    private static func focusedWindow(pid: pid_t) async -> SCWindow? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        ) else { return nil }
        return content.windows
            .filter { $0.owningApplication?.processID == pid && $0.isOnScreen && $0.windowLayer == 0 }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    private static func captureImage(of window: SCWindow, scale: CGFloat) async -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        // Capture at the display's native (Retina) resolution — small UI / terminal
        // text is unreadable to OCR at 1x.
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Run Vision text recognition on an already-captured image. Exposed so the
    /// recognition step can be verified on a synthetic image without Screen
    /// Recording permission (the capture step is what the permission gates).
    static func recognize(_ image: CGImage, maxChars: Int = 1600) -> String? {
        recognizeText(in: image, maxChars: maxChars)
    }

    private static func recognizeText(in image: CGImage, maxChars: Int) -> String? {
        let request = VNRecognizeTextRequest()
        // .accurate over .fast — OCR is async + cached, so the extra time is fine,
        // and small text needs it. Language correction OFF to keep identifiers
        // (branch names, filenames) verbatim.
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let joined = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { return nil }
        return joined.count > maxChars ? String(joined.suffix(maxChars)) : joined
    }
}
