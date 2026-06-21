import Foundation

/// Shared primitive for the deterministic correction passes: apply a set of
/// non-overlapping replacements to a string and report exactly what changed.
/// Every tracked corrector (`TextReplacements`, `MishearingCorrections`,
/// `CommandModeCorrections`, `TranscriptCleaner`, the whisper strip) routes its
/// per-match substitutions through here so range tracking lives in one place.
public enum EditTracking {
    /// Rebuild `text` by applying `replacements` (each an `NSRange` in `text` plus
    /// the literal text to insert). Replacements MUST be non-overlapping and sorted
    /// by location. Returns:
    /// - the new string,
    /// - one `Edit` per replacement, its range in the OUTPUT string, tagged `source`
    ///   (`from` is captured from `text`, `to` is the inserted literal), and
    /// - the per-replacement `(location-in-input, length-delta)` pairs, so a caller
    ///   can rebase edits made by an earlier pass through this one.
    public static func rebuild(
        _ text: String,
        replacements: [(range: NSRange, to: String)],
        source: Edit.Source
    ) -> (String, [Edit], [(at: Int, delta: Int)]) {
        guard !replacements.isEmpty else { return (text, [], []) }
        let ns = text as NSString
        var newResult = ""
        var edits: [Edit] = []
        var deltas: [(at: Int, delta: Int)] = []
        var lastEnd = 0
        for replacement in replacements {
            let r = replacement.range
            newResult += ns.substring(with: NSRange(location: lastEnd, length: r.location - lastEnd))
            let fromText = ns.substring(with: r)
            let outLocation = (newResult as NSString).length
            newResult += replacement.to
            let outLength = (replacement.to as NSString).length
            edits.append(Edit(location: outLocation, length: outLength, from: fromText, to: replacement.to, source: source))
            deltas.append((at: r.location, delta: outLength - r.length))
            lastEnd = r.location + r.length
        }
        newResult += ns.substring(from: lastEnd)
        return (newResult, edits, deltas)
    }
}
