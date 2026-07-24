import Foundation
import LocalDictationCore

/// Real-recordings before/after harness (task b). Runs every kept recording through
/// the user's ACTUAL pipeline and emits a review doc — so a proposed correction/
/// substitution change can be checked against Ammiel's own speech before it ships.
///
/// Usage: `LocalDictation --recordings-ab`
///   BEFORE = raw ASR → the current deterministic chain (mishearing + phonetic snap).
///   AFTER  = BEFORE → the proposed vocab-scoped substitution (STUB = identity until
///            that pass is designed; the framework is what we're building first).
///
/// No ground truth exists for these recordings, so this is a human-review diff, not
/// a WER score: it surfaces every line the new pass would CHANGE so Ammiel can veto.
///
/// KNOWN LIMITATION: BEFORE covers only the DETERMINISTIC chain. It does NOT include
/// the LLM polish (`polishWithAI`, needs a resident llama-server) or context
/// substitution (`contextSubstitutionEnabled`, needs live on-screen context that
/// archived clips can't replay). With those settings on, the live app corrects MORE
/// than this harness shows — so treat BEFORE as a floor, not a faithful replay.
enum RecordingsAB {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--recordings-ab") else { return }
        let sem = DispatchSemaphore(value: 0)
        Task.detached {
            await run()
            sem.signal()
        }
        sem.wait()
        exit(0)
    }

    private struct Row {
        let name: String
        let raw: String
        let before: String
        let after: String
    }

    private static func run() async {
        let recDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/dev.ammiel.local-dictation/recent-recordings")
        let wavs = ((try? FileManager.default.contentsOfDirectory(at: recDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "wav" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !wavs.isEmpty else {
            FileHandle.standardError.write(Data("No recordings under \(recDir.path)\n".utf8))
            return
        }

        let defaults = UserDefaults.standard
        let modelPath = (defaults.string(forKey: "modelPath") ?? "~/models/ggml-large-v3-turbo-q5_0.bin")
            .expandingTildeInPath
        let config = WhisperCLIConfiguration(
            executablePath: WhisperLocator.resolved(configured: ""),
            modelPath: modelPath,
            language: "en",
            timeoutSeconds: 120,
            vadModelPath: WhisperLocator.resolvedVadModel(),
            prompt: nil
        )
        let engine = WhisperCLITranscriptionEngine(configuration: config)

        // The user's real vocabulary + suppression set — the same inputs the live
        // correction chain uses (minus live on-screen context, which archived
        // recordings don't have).
        let customVocab = defaults.string(forKey: "customVocabulary") ?? ""
        let useDefaultVocab = (defaults.object(forKey: "useDefaultVocabulary") as? Bool) ?? true
        let candidates = ContextBias.substitutionCandidates(
            customVocabulary: customVocab,
            defaults: useDefaultVocab ? DefaultVocabulary.terms : [],
            context: nil
        )
        let suppressed = SuppressionSet.decode(defaults.string(forKey: "rejectedBuiltInSwaps") ?? "")

        FileHandle.standardError.write(Data("Transcribing \(wavs.count) recordings (model=\(URL(fileURLWithPath: modelPath).lastPathComponent))…\n".utf8))
        var rows: [Row] = []
        for wav in wavs {
            let raw: String
            do {
                raw = WhisperTranscriptParser.strippedForInsertion(try await engine.transcribe(audioFile: wav))
            } catch {
                raw = "<transcribe error: \(error.localizedDescription)>"
            }
            let before = currentChain(raw, candidates: candidates, suppressed: suppressed)
            let after = proposedChain(before, candidates: candidates, suppressed: suppressed)
            rows.append(Row(name: wav.lastPathComponent, raw: raw, before: before, after: after))
            FileHandle.standardError.write(Data("  \(wav.lastPathComponent)\n".utf8))
        }
        writeReport(rows)
    }

    /// The current shipped deterministic chain (order mirrors AppModel.preCorrect,
    /// minus command-mode which needs live app context).
    private static func currentChain(_ text: String, candidates: [String], suppressed: Set<String>) -> String {
        var result = text
        result = MishearingCorrections.applyTracked(to: result, suppressing: suppressed).0
        if !candidates.isEmpty {
            result = PhoneticSnapCorrections.applyTracked(to: result, vocabulary: candidates, suppressing: suppressed).0
        }
        return result
    }

    /// The PROPOSED pass. STUB = identity for now — this is where the vocab-scoped
    /// substitution will plug in, so the harness diffs before vs after once it exists.
    private static func proposedChain(_ before: String, candidates: [String], suppressed: Set<String>) -> String {
        before
    }

    private static func writeReport(_ rows: [Row]) {
        let dir = URL(fileURLWithPath: NSString(string: "~/Desktop/local-dictation-recordings-ab").expandingTildeInPath)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let changed = rows.filter { $0.before != $0.after }

        var md = "# Recordings before/after review\n\n"
        md += "\(rows.count) real recordings. **\(changed.count)** would be changed by the proposed pass.\n\n"
        md += "- **RAW** = whisper output · **BEFORE** = current shipped chain · **AFTER** = proposed pass (stub = identity for now).\n"
        md += "- Review every AFTER that differs from BEFORE: is it an improvement or a regression?\n\n---\n\n"
        for r in rows {
            let flag = r.before == r.after ? "" : "  ⚠️ CHANGED"
            md += "### \(r.name)\(flag)\n\n"
            md += "- RAW:    \(r.raw)\n"
            md += "- BEFORE: \(r.before)\n"
            md += "- AFTER:  \(r.after)\n\n"
        }
        let out = dir.appendingPathComponent("report.md")
        try? md.write(to: out, atomically: true, encoding: .utf8)
        FileHandle.standardError.write(Data("\nReport → \(out.path)\n".utf8))
        print(out.path)
    }
}
