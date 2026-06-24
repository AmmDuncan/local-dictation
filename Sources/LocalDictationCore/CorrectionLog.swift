import Foundation

/// One reviewable dictation: what was heard, the deterministic pre-polish result
/// the swaps highlight against, the text actually inserted, and the attributed
/// edits split by the opaque polish boundary. Text only (no audio) — and a more
/// sensitive trail than `TranscriptRecord`, so the Learn tab must expose clear.
public struct CorrectionRecord: Equatable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var date: Date
    /// The raw whisper transcript.
    public var raw: String
    /// The deterministic pre-polish result — the space `segmentA` ranges point into.
    public var prePolish: String
    /// The text actually inserted (post-polish, post-replacement). `segmentB` ranges
    /// point into this. (Named `inserted` rather than `final` to dodge the keyword.)
    public var inserted: String
    /// Pre-polish swaps (mishearing / command), in `prePolish` space.
    public var segmentA: [Edit]
    /// Post-polish replacements, in `inserted` space.
    public var segmentB: [Edit]
    /// What the optional LLM polish pass did this dictation (nil when polish is off).
    /// Drives the review-panel provenance line + the menu-bar lifetime tally.
    public var polishOutcome: PolishOutcome?

    public var changeCount: Int { segmentA.count + segmentB.count }

    public init(
        id: UUID = UUID(),
        raw: String,
        prePolish: String,
        inserted: String,
        segmentA: [Edit],
        segmentB: [Edit],
        polishOutcome: PolishOutcome? = nil,
        date: Date = Date()
    ) {
        self.id = id
        self.raw = raw
        self.prePolish = prePolish
        self.inserted = inserted
        self.segmentA = segmentA
        self.segmentB = segmentB
        self.polishOutcome = polishOutcome
        self.date = date
    }
}

/// Pure operations over the correction log. Persistence (UserDefaults) and the
/// Learn-tab UI live in the app layer — mirrors `TranscriptHistory`.
public enum CorrectionLog {
    public static let defaultMaxEntries = 200

    /// Append a record (newest last), dropping the oldest beyond `maxEntries`. Every
    /// dictation is logged — even zero-change ones, since the user can still teach a
    /// correction it missed.
    public static func appending(
        _ record: CorrectionRecord,
        to records: [CorrectionRecord],
        maxEntries: Int = defaultMaxEntries
    ) -> [CorrectionRecord] {
        var updated = records
        updated.append(record)
        if updated.count > maxEntries {
            updated.removeFirst(updated.count - maxEntries)
        }
        return updated
    }

    /// Records that made at least one attributed change, newest first — the review
    /// queue's "pending" set (drives the count badge).
    public static func pending(_ records: [CorrectionRecord]) -> [CorrectionRecord] {
        records.filter { $0.changeCount > 0 }.sorted { $0.date > $1.date }
    }
}
