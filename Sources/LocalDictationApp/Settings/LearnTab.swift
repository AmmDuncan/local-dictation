import LocalDictationCore
import SwiftUI

/// The Learn tab: review recent dictations + their corrections, and manage the
/// rules the app applies — taught rules (structured rows) and built-in swaps
/// (on/off toggles → suppression set). Tapping a dictation to open the review panel
/// arrives with the panel (P3); built-in toggles take effect once the apply path
/// consults the suppression set (also P3).
struct LearnTab: View {
    @Binding var logCorrections: Bool
    @Binding var textReplacements: String
    @Binding var rejectedBuiltInSwaps: String

    @State private var records: [CorrectionRecord] = []
    @State private var newFrom = ""
    @State private var newTo = ""
    @State private var reviewing: CorrectionRecord?

    private var userRules: [TextReplacements.Rule] { TextReplacements.parse(textReplacements) }

    /// Dictations worth surfacing in the queue — only those that got a correction,
    /// newest first. Zero-change dictations stay in the log but aren't shown here.
    private var reviewable: [CorrectionRecord] { CorrectionLog.pending(records) }

    private func builtIns(_ source: Edit.Source) -> [BuiltInCorrections.Entry] {
        BuiltInCorrections.all.filter { $0.source == source }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Log corrections for review", isOn: $logCorrections)
            } footer: {
                Text("Record each dictation and what was corrected, so you can review and teach below. On-device only — never sent anywhere.")
            }

            Section("Recent dictations") {
                if reviewable.isEmpty {
                    Text("No corrections to review yet.").foregroundStyle(.secondary)
                } else {
                    // Bounded + scrolls internally so the log can't push the settings
                    // below it off-screen, however many dictations pile up.
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(reviewable) { recordRow($0) }
                        }
                    }
                    .frame(maxHeight: 220)
                }
                if !records.isEmpty {
                    Button("Clear all", role: .destructive) {
                        CorrectionLogStore.clear()
                        reload()
                    }
                }
            }

            Section {
                ForEach(Array(userRules.enumerated()), id: \.offset) { _, rule in
                    HStack {
                        ruleLabel(from: rule.pattern, to: rule.replacement)
                        Spacer()
                        Button { deleteRule(rule) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    TextField("heard", text: $newFrom)
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                    TextField("correction", text: $newTo)
                    Button("Add", action: addRule)
                        .disabled(newFrom.trimmingCharacters(in: .whitespaces).isEmpty
                            || newTo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Your corrections")
            } footer: {
                Text("Words you've taught. Applied after transcription. (Raw `find => replace` editing lives in Advanced.)")
            }

            Section {
                DisclosureGroup {
                    ForEach(builtIns(.mishearing)) { entry in
                        Toggle(isOn: builtInBinding(entry)) {
                            ruleLabel(from: entry.from, to: entry.to)
                        }
                    }
                } label: {
                    builtInDisclosureLabel("Mishearings", count: builtIns(.mishearing).count)
                }
            } footer: {
                Text("Built-in fixes for commonly misheard words — applied everywhere. Turn off any you don't want.")
            }

            Section {
                DisclosureGroup {
                    ForEach(builtIns(.command)) { entry in
                        Toggle(isOn: builtInBinding(entry)) {
                            ruleLabel(from: entry.from, to: entry.to)
                        }
                    }
                } label: {
                    builtInDisclosureLabel("Command mode (terminal git)", count: builtIns(.command).count)
                }
            } footer: {
                Text("Applied only inside a terminal when you're typing a git command — “main” is often misheard as “me”. Left alone everywhere else.")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
        .sheet(item: $reviewing) { record in
            ReviewPanel(record: record, onClose: {
                reviewing = nil
                reload()
            })
        }
    }

    private func builtInDisclosureLabel(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(count) fixes")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func ruleLabel(from: String, to: String) -> some View {
        HStack(spacing: 6) {
            Text(from).foregroundStyle(.secondary)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
            Text(to).fontWeight(.medium)
        }
    }

    @ViewBuilder
    private func recordRow(_ record: CorrectionRecord) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(record.inserted).lineLimit(1)
                Spacer()
                if record.changeCount > 0 {
                    Text("\(record.changeCount) change\(record.changeCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Brand.emerald.opacity(0.15)))
                        .foregroundStyle(Brand.emerald)
                }
                Button { CorrectionLogStore.delete(id: record.id); reload() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            let swaps = (record.segmentA + record.segmentB).filter { !$0.to.isEmpty }
            if !swaps.isEmpty {
                Text(swaps.map { "\($0.from) → \($0.to)" }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { reviewing = record }
    }

    private func builtInBinding(_ entry: BuiltInCorrections.Entry) -> Binding<Bool> {
        Binding(
            get: { !SuppressionSet.isSuppressed(entry.identity, in: rejectedBuiltInSwaps) },
            set: { enabled in
                rejectedBuiltInSwaps = SuppressionSet.toggling(entry.identity, in: rejectedBuiltInSwaps, on: !enabled)
            }
        )
    }

    private func addRule() {
        let from = newFrom.trimmingCharacters(in: .whitespaces)
        let to = newTo.trimmingCharacters(in: .whitespaces)
        guard !from.isEmpty, !to.isEmpty else { return }
        textReplacements = TextReplacements.serialize(userRules + [TextReplacements.Rule(pattern: from, replacement: to)])
        newFrom = ""
        newTo = ""
    }

    private func deleteRule(_ rule: TextReplacements.Rule) {
        textReplacements = TextReplacements.serialize(userRules.filter { $0 != rule })
    }

    private func reload() {
        records = CorrectionLogStore.load().sorted { $0.date > $1.date }
    }
}
