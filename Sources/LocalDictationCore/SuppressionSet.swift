import Foundation

/// The set of built-in correction identities the user has rejected (toggled off in
/// the Learn tab). The deterministic apply path consults it before applying a
/// built-in `MishearingCorrections` / `CommandModeCorrections` rule, so a rejected
/// swap is skipped on future dictations.
///
/// Persisted as a JSON-encoded `[String]` in a single settings string (UserDefaults
/// can't store a `Set` directly; JSON mirrors the `textReplacements` string pattern
/// and stays forward-compatible). All entry points are total — blank/invalid JSON
/// decodes to an empty set rather than throwing into the dictation pipeline.
public enum SuppressionSet {
    /// Decode the stored JSON string to a set of identities. Empty/invalid → `[]`.
    public static func decode(_ json: String) -> Set<String> {
        guard let data = json.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(array)
    }

    /// Encode identities to a stable JSON string (sorted, so the persisted value
    /// doesn't churn between runs for the same set).
    public static func encode(_ identities: Set<String>) -> String {
        guard let data = try? JSONEncoder().encode(identities.sorted()),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    /// Whether `identity` is currently rejected, given the stored JSON string.
    public static func isSuppressed(_ identity: String, in json: String) -> Bool {
        decode(json).contains(identity)
    }

    /// Return a new JSON string with `identity` added (`on: true`) or removed
    /// (`on: false`); other entries untouched.
    public static func toggling(_ identity: String, in json: String, on: Bool) -> String {
        var set = decode(json)
        if on { set.insert(identity) } else { set.remove(identity) }
        return encode(set)
    }
}
