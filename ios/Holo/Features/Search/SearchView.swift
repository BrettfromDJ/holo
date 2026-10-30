import SwiftUI

/// Find any card or sealed product and add it to your collection.
struct SearchView: View {
    var asSheet = false
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [SearchHit] = []
    @State private var searching = false
    @State private var error: String?
    @State private var picked: SearchHit?

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Text(error).foregroundStyle(Theme.down)
                } else if query.count >= 2 && !searching && results.isEmpty {
                    Text("Nothing found. Try the set name or card number too.").foregroundStyle(Theme.muted)
                }
                ForEach(results) { hit in
                    Button { picked = hit } label: { SearchRow(hit: hit) }
                        .listRowBackground(Theme.background)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .overlay { if searching && results.isEmpty { ProgressView() } }
            .navigationTitle(asSheet ? "Add to collection" : "Search")
            .navigationBarTitleDisplayMode(asSheet ? .inline : .large)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Card, set or sealed product")
            .toolbar {
                if asSheet {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                }
            }
            // Debounced: waits for a pause in typing, and cancels when the query changes.
            .task(id: query) { await search() }
            .sheet(item: $picked) { hit in AddPurchaseSheet(hit: hit, onDone: { if asSheet { dismiss() } }) }
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            results = []
            error = nil
            return
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        do {
            let hits = try await Backend.shared.api.search(q)
            guard !Task.isCancelled else { return }
            results = hits
            error = nil
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
}

struct SearchRow: View {
    var hit: SearchHit

    var body: some View {
        HStack(spacing: 12) {
            ProductImage(product: hit.product, cornerRadius: 5).frame(width: 42, height: 58)
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.product.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                Text([hit.gameName, hit.product.setName, hit.product.number.map { "#\($0)" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            Text(Format.money(hit.market)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
    }
}
