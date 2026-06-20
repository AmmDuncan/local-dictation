import Darwin
import Foundation
import LocalDictationCore
import Observation

/// Owns a long-lived `llama-server` subprocess for the optional LLM polish pass,
/// keeping the model resident (no per-call reload). Mirrors `WhisperServerManager`
/// but launches llama-server and polls `/health`. Starts lazily, restarts when
/// the model changes, and reports readiness so the polisher can wait it out.
///
/// NOTE: near-identical to WhisperServerManager — a shared resident-server helper
/// is the natural next refactor once both are settled.
@MainActor
@Observable
final class LlamaServerManager {
    private(set) var isReady = false

    private var process: Process?
    private var port: Int = 0
    private var modelPath: String?
    private var readinessTask: Task<Void, Never>?

    var baseURL: URL? {
        guard isReady, port > 0 else { return nil }
        return URL(string: "http://127.0.0.1:\(port)")
    }

    /// Ensure a server is running for `modelPath`. Cheap to call repeatedly.
    func ensureRunning(modelPath newModel: String, executablePath: String) {
        if process?.isRunning == true, modelPath == newModel {
            return
        }
        start(modelPath: newModel, executablePath: executablePath)
    }

    func stop() {
        readinessTask?.cancel()
        readinessTask = nil
        process?.terminate()
        process = nil
        isReady = false
    }

    /// Wait until the server is ready (model loaded) or the deadline passes.
    /// Returns the ready base URL, or nil if no server is coming up.
    func awaitReady(timeout: TimeInterval) async -> URL? {
        if let url = baseURL { return url }
        guard process?.isRunning == true else { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(150))
            if let url = baseURL { return url }
            if process?.isRunning != true { return nil }
        }
        return baseURL
    }

    private func start(modelPath newModel: String, executablePath: String) {
        stop()
        modelPath = newModel
        WhisperLocator.ensureBackendsLinked()

        let chosenPort = Self.freePort()
        let args = [
            "-m", newModel,
            "--host", "127.0.0.1", "--port", String(chosenPort),
            "-c", "2048", "-ngl", "99", "--no-webui",
        ]
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            return
        }
        process = proc
        port = chosenPort

        readinessTask = Task { [weak self] in
            await self?.pollUntilReady(port: chosenPort)
        }
    }

    private func pollUntilReady(port: Int) async {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        // Up to ~90s — model load into VRAM can take a while on first run.
        for _ in 0..<360 {
            if Task.isCancelled { return }
            if let (_, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse, http.statusCode == 200 {
                isReady = true
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Asks the kernel for an unused TCP port on localhost.
    private static func freePort() -> Int {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return 8480 }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { return 8480 }

        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(sock, $0, &len)
            }
        }
        return Int(UInt16(bigEndian: addr.sin_port))
    }
}
