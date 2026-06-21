import Foundation

/// Folds a chain of correction passes into a single edit list expressed in the
/// final pass's coordinate space. Each pass reports its edits in its OWN output
/// space; when several run in sequence (e.g. mishearing then command), an earlier
/// pass's ranges must be rebased through every later pass's length changes so they
/// still point at the right span of the final string.
///
/// Used to assemble Segment A (the pre-polish deterministic swaps). Polish is an
/// opaque rewrite and is never folded across — see the spec's coordinate-space note.
public enum EditFold {
    /// Fold `passes` (earliest first, each in its own output space) into one edit
    /// list in the LAST pass's output space.
    public static func combine(_ passes: [[Edit]]) -> [Edit] {
        var result: [Edit] = []
        for pass in passes {
            result = Edit.shifting(result, by: Edit.inputDeltas(pass))
            result.append(contentsOf: pass)
        }
        return result
    }
}
