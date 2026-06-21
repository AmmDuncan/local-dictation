import Foundation
import LocalDictationCore

/// Persists the correction log (dictations + their attributed edits, text only, no
/// audio) in UserDefaults. Pure list operations live in `CorrectionLog`; this is the
/// app-layer load/append/clear around it. More sensitive than `TranscriptHistory`
/// (it keeps raw + corrected text), so the Learn tab exposes clear + per-row delete.
enum CorrectionLogStore {
    private static let key = "correctionLog"

    static func load() -> [CorrectionRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([CorrectionRecord].self, from: data) else {
            return []
        }
        return records
    }

    static func append(_ record: CorrectionRecord) {
        save(CorrectionLog.appending(record, to: load()))
    }

    static func delete(id: UUID) {
        save(load().filter { $0.id != id })
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func save(_ records: [CorrectionRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
