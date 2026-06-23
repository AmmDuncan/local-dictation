import AppKit
import Foundation
import os

/// Collects the macOS-generated crash reports (`.ips`) for LocalDictation and,
/// once the user has opted in, uploads new ones to the crash-collector Worker so
/// crashes can be diagnosed without anyone digging through Console.
///
/// Privacy: only the macOS diagnostic report is sent — the app version, your
/// macOS version, and a technical backtrace. Never dictation text, audio, or
/// transcripts. Off until you opt in (a one-time prompt); revocable any time in
/// Settings → Advanced. The fallback `Copy last crash report` menu item works
/// regardless and uploads nothing.
enum CrashReporter {
    private static let endpoint = URL(string: "https://ld-crash-collector.ammielgyanyawson.workers.dev/crash")!
    /// Shared upload token. Embedded by design: it only permits uploading crash
    /// reports (no user data flows out through it) and is rotatable server-side.
    private static let uploadSecret = "3c750969bd11fb094e27b3f9b69c3c14e1585f620e6ac0a2ab75b32120e2cd54"

    private static let handledKey = "crashReportsHandled"
    private static let maxBacklog = 20
    private static let maxReportBytes = 4 * 1024 * 1024
    private static let reportPrefix = "LocalDictation"

    private static let log = Logger(subsystem: "dev.ammiel.local-dictation", category: "crashreporter")

    /// Where macOS writes `.ips` diagnostic reports (user-readable, no permission).
    private static var reportsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    }

    // MARK: - Launch entry point

    /// Called once at launch. Finds crash reports we haven't handled, prompts for
    /// consent the first time one appears, and uploads when enabled. Best-effort
    /// and non-blocking — any failure just leaves the report to retry next launch.
    @MainActor
    static func checkForReports() {
        let pending = unhandledReports()
        guard !pending.isEmpty else { return }

        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: AppSettingsKeys.crashReportConsentAsked) else {
            promptForConsent(reportCount: pending.count) { granted in
                defaults.set(true, forKey: AppSettingsKeys.crashReportConsentAsked)
                defaults.set(granted, forKey: AppSettingsKeys.crashReportingEnabled)
                if granted { startUpload(pending) }
            }
            return
        }

        if defaults.bool(forKey: AppSettingsKeys.crashReportingEnabled) {
            startUpload(pending)
        }
        // Disabled: leave reports unhandled so they upload if the user later
        // re-enables. Re-scanning a handful of files each launch is cheap.
    }

    // MARK: - Menu fallback

    /// Whether any LocalDictation crash report exists (handled or not) — drives
    /// the "Copy last crash report" menu item's visibility.
    static func hasAnyReport() -> Bool { !reportEntries().isEmpty }

    /// Copy the most recent crash report's full text to the clipboard. Returns
    /// false if there is none. Uploads nothing — a pure local hand-off.
    @MainActor
    @discardableResult
    static func copyLatestReport() -> Bool {
        guard let url = latestReport(), let text = readReport(url) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return true
    }

    // MARK: - Consent

    @MainActor
    private static func promptForConsent(reportCount: Int, completion: (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = reportCount > 1
            ? "Send crash reports to the developer?"
            : "Send crash report to the developer?"
        alert.informativeText = """
        LocalDictation crashed recently. You can send the macOS crash report to help fix it. \
        It includes the app version, your macOS version, and a technical backtrace — never your \
        dictation text, audio, or transcripts. You can change this any time in Settings → Advanced.
        """
        alert.addButton(withTitle: "Send & Remember")
        alert.addButton(withTitle: "Not Now")
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        completion(alert.runModal() == .alertFirstButtonReturn)
    }

    // MARK: - Discovery

    /// Unhandled LocalDictation reports, newest first.
    private static func unhandledReports() -> [URL] {
        let handled = Set(UserDefaults.standard.stringArray(forKey: handledKey) ?? [])
        return allReports().filter { !handled.contains($0.lastPathComponent) }
    }

    private static func latestReport() -> URL? { allReports().first }

    /// All LocalDictation `.ips` reports, newest first. Reads each file's creation
    /// date exactly once rather than inside the sort comparator.
    private static func allReports() -> [URL] {
        reportEntries()
            .map { (url: $0, created: creationDate($0)) }
            .sorted { $0.created > $1.created }
            .map(\.url)
    }

    /// LocalDictation `.ips` files in the diagnostics dir, unsorted.
    private static func reportEntries() -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: reportsDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.filter { $0.pathExtension == "ips" && $0.lastPathComponent.hasPrefix(reportPrefix) }
    }

    // MARK: - Upload

    private static func startUpload(_ reports: [URL]) {
        let batch = Array(reports.prefix(maxBacklog))
        if reports.count > batch.count {
            log.info("crash backlog \(reports.count) exceeds cap \(maxBacklog) — uploading newest \(batch.count)")
        }
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        Task.detached { await uploadAll(batch, version: version, build: build, os: os) }
    }

    nonisolated private static func uploadAll(
        _ reports: [URL], version: String, build: String, os: String
    ) async {
        for url in reports {
            guard let report = readReport(url) else { continue }
            let body: [String: String] = [
                "app": reportPrefix,
                "version": version,
                "build": build,
                "os": os,
                "reportName": url.lastPathComponent,
                "ts": isoCreationDate(url),
                "report": report,
            ]
            guard let payload = try? JSONSerialization.data(withJSONObject: body) else { continue }

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("Bearer \(uploadSecret)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = payload

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                if status == 200 {
                    markHandled(url)
                    log.info("uploaded crash report \(url.lastPathComponent, privacy: .public)")
                } else {
                    log.error("crash upload got status \(status) — will retry next launch")
                }
            } catch {
                log.error("crash upload failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Helpers

    /// Read a report as text, skipping anything over the size cap. Lossy UTF-8 so
    /// an odd byte never drops the whole report.
    nonisolated private static func readReport(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), data.count <= maxReportBytes else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    nonisolated private static func markHandled(_ url: URL) {
        let defaults = UserDefaults.standard
        var handled = defaults.stringArray(forKey: handledKey) ?? []
        let name = url.lastPathComponent
        guard !handled.contains(name) else { return }
        handled.append(name)
        defaults.set(handled, forKey: handledKey)
    }

    nonisolated private static func creationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }

    nonisolated private static func isoCreationDate(_ url: URL) -> String {
        ISO8601DateFormatter().string(from: creationDate(url))
    }
}
