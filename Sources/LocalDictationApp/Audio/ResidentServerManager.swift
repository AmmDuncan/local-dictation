import Darwin
import Foundation
import LocalDictationCore
import Observation

/// Shared on-disk record of helper PIDs this app spawns, so a crash/force-quit
/// orphan can be reaped on next launch even when it lives outside the bundle (a
/// dev build's Homebrew fallback). Keyed on the fixed bundle id (not the bundle
/// API), so dev and installed builds share it and reap each other's leftovers.
enum SpawnedHelpers {
    static let pidFile: String = {
        let dir = NSHomeDirectory() + "/Library/Application Support/dev.ammiel.local-dictation"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir + "/spawned-helpers.pids"
    }()
}

/// Owns a long-lived llama.cpp-family subprocess (whisper-server or llama-server)
/// so the model stays resident — no per-call reload. Starts lazily, restarts when
/// the model changes, and reports readiness so callers can wait out a cold load
/// (or fall back). The only per-server differences — launch args and the health
/// check — live in `Config`; everything else (process lifecycle, free port,
/// readiness polling) is shared.
@MainActor
@Observable
final class ResidentServerManager {
    struct Config {
        /// Builds the process arguments for a given model path + chosen port.
        let arguments: (_ modelPath: String, _ port: Int) -> [String]
        /// Path polled for readiness, e.g. "/" (whisper-server) or "/health".
        let healthPath: String
        /// When true, readiness requires HTTP 200 (llama-server); when false, any
        /// response counts (whisper-server answers "/" once the model is loaded).
        let requireHTTPOK: Bool

        /// whisper-server: beam-1, no-timestamps, optional bundled VAD tuned for
        /// short dictation (see WhisperVAD.dictationTuningArguments); "/" ready.
        static var whisper: Config {
            Config(
                arguments: { model, port in
                    var args = ["-m", model, "--host", "127.0.0.1", "--port", String(port), "-nt", "-bs", "1"]
                        + WhisperDecoding.maxContextArguments
                    if let vad = WhisperLocator.resolvedVadModel() {
                        args.append(contentsOf: ["--vad", "-vm", vad] + WhisperVAD.dictationTuningArguments)
                    }
                    return args
                },
                healthPath: "/",
                requireHTTPOK: false
            )
        }

        /// llama-server: 2k context, full GPU offload, no web UI; "/health" 200.
        static var llama: Config {
            Config(
                arguments: { model, port in
                    ["-m", model, "--host", "127.0.0.1", "--port", String(port), "-c", "2048", "-ngl", "99", "--no-webui"]
                },
                healthPath: "/health",
                requireHTTPOK: true
            )
        }
    }

    private(set) var isReady = false

    private let config: Config
    private var process: Process?
    private var port = 0
    private var modelPath: String?
    private var readinessTask: Task<Void, Never>?

    init(config: Config) {
        self.config = config
    }

    var baseURL: URL? {
        guard isReady, port > 0 else { return nil }
        return URL(string: "http://127.0.0.1:\(port)")
    }

    /// Wait until the server is ready (model loaded) or the deadline passes.
    /// Returns the ready base URL, or nil if no server is coming up — lets a
    /// caller wait out a cold model load instead of racing a cold fallback.
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

    /// Ensure a server is running for `modelPath`. Cheap to call repeatedly; only
    /// (re)starts when nothing is running or the model changed.
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

    /// Terminate the child and wait briefly for it to actually exit, escalating to
    /// SIGKILL if it doesn't. Use on app termination: `stop()`'s SIGTERM is async,
    /// so if the app exits first the signal can be lost and the child orphaned.
    func shutdown() {
        if let proc = process, proc.isRunning {
            proc.terminate()
            let deadline = Date().addingTimeInterval(1)
            while proc.isRunning, Date() < deadline {
                usleep(50_000)
            }
            if proc.isRunning {
                kill(proc.processIdentifier, SIGKILL)
            }
        }
        stop()
    }

    private func start(modelPath newModel: String, executablePath: String) {
        stop()
        modelPath = newModel
        WhisperLocator.ensureBackendsLinked()

        let chosenPort = Self.freePort()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.arguments = config.arguments(newModel, chosenPort)
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            return
        }
        process = proc
        port = chosenPort
        HelperProcessReaper.recordSpawnedPID(proc.processIdentifier, toFile: SpawnedHelpers.pidFile)

        readinessTask = Task { [weak self] in
            await self?.pollUntilReady(port: chosenPort)
        }
    }

    private func pollUntilReady(port: Int) async {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(config.healthPath)") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        // Up to ~90s — large models take a while to load into VRAM.
        for _ in 0..<360 {
            if Task.isCancelled { return }
            if let (_, response) = try? await URLSession.shared.data(for: request) {
                if !config.requireHTTPOK || (response as? HTTPURLResponse)?.statusCode == 200 {
                    isReady = true
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Asks the kernel for an unused TCP port on localhost.
    private static func freePort() -> Int {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return 8470 }
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
        guard bindResult == 0 else { return 8470 }

        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(sock, $0, &len)
            }
        }
        return Int(UInt16(bigEndian: addr.sin_port))
    }
}
