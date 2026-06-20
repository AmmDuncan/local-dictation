import AppKit
import LocalDictationCore
import SwiftUI

/// Browse, search, and re-copy past dictations (text only — no audio is ever
/// stored). Backed by `TranscriptHistoryStore`.
struct HistoryView: View {
    @State private var records: [TranscriptRecord] = TranscriptHistoryStore.load()
    @State private var query = ""

    private var filtered: [TranscriptRecord] {
        TranscriptHistory.search(records, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 440, minHeight: 380)
        .onAppear { records = TranscriptHistoryStore.load() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            records = TranscriptHistoryStore.load()
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search transcripts", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            ContentUnavailableView(
                records.isEmpty ? "No dictation history yet" : "No matches",
                systemImage: "text.bubble",
                description: Text(records.isEmpty ? "Your dictations will appear here." : "Try a different search.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(filtered) { record in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.text)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(record.date, format: .dateTime.month().day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button { copy(record.text) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .help("Copy")
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset)
        }
    }

    private var footer: some View {
        HStack {
            Text("\(records.count) saved")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear All", role: .destructive) {
                TranscriptHistoryStore.clear()
                records = []
            }
            .disabled(records.isEmpty)
        }
        .padding(12)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
