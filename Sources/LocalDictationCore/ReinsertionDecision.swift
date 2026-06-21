import Foundation

/// The safety check for experimental live re-insertion (AX select-verify-replace).
/// After selecting the span we believe we inserted, we read it back and only replace
/// if it's EXACTLY what we inserted (UTF-16 exact). Any drift — caret moved, the user
/// typed, the view reflowed, or the AX write was silently ignored — fails the check
/// and we abort rather than clobber the wrong text. Pure so it's unit-testable; the
/// actual AX I/O is the app layer's job.
public enum ReinsertionDecision {
    public static func canReplace(inserted: String, readBack: String?) -> Bool {
        guard let readBack, !inserted.isEmpty else { return false }
        return inserted == readBack
    }
}
