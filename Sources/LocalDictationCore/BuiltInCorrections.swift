import Foundation

/// The catalog of built-in deterministic swaps with their stable suppression
/// identities. Drives the Learn tab's on/off toggles and the apply-path suppression
/// consult, so both speak the same identity strings as `RuleDerivation` produces
/// when the user reverts a swap.
public enum BuiltInCorrections {
    public struct Entry: Identifiable, Sendable, Equatable {
        public let identity: String
        public let from: String
        public let to: String
        public let source: Edit.Source
        public var id: String { identity }
    }

    public static let all: [Entry] = {
        var entries: [Entry] = []
        func add(from: String, to: String, source: Edit.Source) {
            guard let identity = RuleDerivation.suppressionIdentity(source: source, from: from, to: to) else { return }
            entries.append(Entry(identity: identity, from: from, to: to, source: source))
        }
        for rule in MishearingCorrections.rules { add(from: rule.pattern, to: rule.replacement, source: .mishearing) }
        // `clot` is a separate regex pass, not a Rule — list it explicitly.
        add(from: "clot", to: "Claude", source: .mishearing)
        for rule in CommandModeCorrections.branchRules { add(from: rule.pattern, to: rule.replacement, source: .command) }
        return entries
    }()
}
