import Darwin
import Foundation

/// Finds and kills orphaned bundled helper servers (whisper-server / llama-server)
/// left behind when the app exits without running its termination cleanup — a
/// force-quit, crash, or a diagnostic path that calls `exit()`. macOS has no
/// parent-death signal and the helpers are prebuilt binaries we can't modify, so
/// a reap-on-launch sweep is the safety net that stops orphans accumulating.
///
/// Strictly scoped to executables living inside a given Helpers directory, so a
/// Homebrew install (`/opt/homebrew/bin/whisper-server`) or any unrelated copy is
/// never touched.
public enum HelperProcessReaper {
    public static let helperNames = ["whisper-server", "llama-server"]

    /// True when `executablePath` is exactly `<helpersDir>/<helper>` for one of the
    /// known helper names. Exact match by design: a Homebrew path, the `whisper-cli`
    /// helper, or a sibling dir like `Helpers-evil/` never matches.
    public static func isBundledHelper(executablePath: String, helpersDir: String) -> Bool {
        // Resolve symlinks on both sides before comparing, so a bundle installed
        // under a symlinked path still matches the path captured at exec time.
        let dir = (helpersDir as NSString).resolvingSymlinksInPath
        let exe = (executablePath as NSString).resolvingSymlinksInPath
        return helperNames.contains { exe == dir + "/" + $0 }
    }

    /// PIDs of running bundled helpers under `helpersDir`, excluding `keeping`
    /// (our own live children, so a sweep never kills the servers we just started).
    public static func orphanPIDs(helpersDir: String, keeping: Set<pid_t> = []) -> [pid_t] {
        allPIDs().filter { pid in
            guard pid > 0, !keeping.contains(pid) else { return false }
            guard let path = executablePath(of: pid) else { return false }
            return isBundledHelper(executablePath: path, helpersDir: helpersDir)
        }
    }

    /// Kill orphaned helpers: SIGTERM, a short grace, then SIGKILL any survivors.
    /// Returns the PIDs it signalled (empty when nothing matched).
    @discardableResult
    public static func reap(helpersDir: String, keeping: Set<pid_t> = []) -> [pid_t] {
        let orphans = orphanPIDs(helpersDir: helpersDir, keeping: keeping)
        guard !orphans.isEmpty else { return [] }
        for pid in orphans { kill(pid, SIGTERM) }
        usleep(300_000)
        for pid in orphans where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        return orphans
    }

    /// Append a helper PID we just spawned to `path`, so a later launch can reap it
    /// even when it lives OUTSIDE the bundle (a dev build's Homebrew fallback) — the
    /// case `reap(helpersDir:)` deliberately can't touch. Best-effort; never throws.
    public static func recordSpawnedPID(_ pid: pid_t, toFile path: String) {
        guard pid > 0 else { return }
        let line = "\(pid)\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    /// Reap helpers previously recorded in `path` via `recordSpawnedPID`: for each
    /// recorded PID still alive whose executable is STILL a known helper — the
    /// basename check guards against the PID being recycled by an unrelated process
    /// — SIGTERM then SIGKILL. Only PIDs we recorded are ever touched, so a Homebrew
    /// whisper-server the user started themselves is never killed. Clears the file
    /// afterwards. Returns the PIDs signalled.
    @discardableResult
    public static func reapTracked(file path: String, keeping: Set<pid_t> = []) -> [pid_t] {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        let recorded = Set(contents.split(whereSeparator: \.isNewline).compactMap {
            pid_t($0.trimmingCharacters(in: .whitespaces))
        })
        var signalled: [pid_t] = []
        for pid in recorded where pid > 0 && !keeping.contains(pid) {
            guard kill(pid, 0) == 0, isHelperProcess(pid: pid) else { continue }
            kill(pid, SIGTERM)
            signalled.append(pid)
        }
        usleep(300_000)
        for pid in signalled where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        try? "".write(toFile: path, atomically: true, encoding: .utf8)
        return signalled
    }

    /// True when `pid`'s launch executable basename is a known helper — guards
    /// against killing a PID that has been recycled by some other process.
    private static func isHelperProcess(pid: pid_t) -> Bool {
        guard let path = executablePath(of: pid) else { return false }
        return helperNames.contains((path as NSString).lastPathComponent)
    }

    /// The executable path a process was launched from, read from its saved argv
    /// via KERN_PROCARGS2. We deliberately avoid `proc_pidpath`: it resolves the
    /// live executable vnode and returns ENOENT once that file is unlinked — which
    /// is exactly what happens to a leftover helper after a Sparkle update or
    /// rebuild replaces the .app bundle, i.e. the orphans we most need to find.
    /// argv is captured at exec time and survives the binary being replaced.
    private static func executablePath(of pid: pid_t) -> String? {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return nil
        }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return nil }
        // Layout: [argc: Int32][exec_path\0]…  — the path follows the argc word.
        return buf.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return nil }
            return String(cString: base.advanced(by: MemoryLayout<Int32>.size))
        }
    }

    private static func allPIDs() -> [pid_t] {
        let cap = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard cap > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(cap) / MemoryLayout<pid_t>.size)
        let written = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, cap)
        guard written > 0 else { return [] }
        let count = Int(written) / MemoryLayout<pid_t>.size
        return Array(pids.prefix(count)).filter { $0 != 0 }
    }
}
