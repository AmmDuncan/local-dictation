import Foundation
import LocalDictationCore

/// Persists the searchable, text-only dictation history (no audio) in
/// UserDefaults. The pure list operations live in `TranscriptHistory`; this is
/// just the app-layer load/save/clear around it.
enum TranscriptHistoryStore {
    private static let key = "transcriptHistory"

    static func load() -> [TranscriptRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([TranscriptRecord].self, from: data) else {
            return []
        }
        return records
    }

    static func append(_ text: String) {
        let updated = TranscriptHistory.appending(text, to: load(), at: Date())
        save(updated)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func save(_ records: [TranscriptRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
