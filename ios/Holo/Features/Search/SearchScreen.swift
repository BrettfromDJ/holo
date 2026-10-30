import SwiftUI

// MARK: - The search box (one look everywhere)

/// The app's search box: a Liquid Glass capsule with a magnifier, your text, a spinner while it
/// looks, and a clear button. Every search in the app uses it, so they all look the same.
struct HoloSearchField: View {
    @Binding var text: String
    var prompt: String
    var focus: FocusState<Bool>.Binding
    var loading = false
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.muted)
            TextField("", text: $text, prompt: Text(prompt).foregroundColor(Theme.subtle))
                .font(.geist(16))
                .foregroundStyle(.white)
                .tint(Theme.lime)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused(focus)
                .onSubmit(onSubmit)
            if loading {
                ProgressView().controlSize(.small).tint(Theme.muted)
            }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background { Color.clear.liquidGlass(in: Capsule()).allowsHitTesting(false) }
        .contentShape(Capsule())
        .onTapGesture { focus.wrappedValue = true }
    }
}

/// The same box as a button, for pages where tapping it opens search (with the keyboard up).
struct SearchFieldButton: View {
    var prompt: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.muted)
                Text(prompt).font(.geist(16)).foregroundStyle(Theme.subtle).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background { Color.clear.liquidGlass(in: Capsule()).allowsHitTesting(false) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recent searches and recently viewed

/// What you searched for and opened lately, kept on the phone.
@Observable
final class SearchHistory {
    static let shared = SearchHistory()

    private(set) var queries: [String] = []
    private(set) var viewed: [SearchHit] = []

    private let queriesKey = "search.recentQueries"
    private let viewedKey = "search.recentlyViewed"

    private init() {
        queries = UserDefaults.standard.stringArray(forKey: queriesKey) ?? []
        if let data = UserDefaults.standard.data(forKey: viewedKey), let hits = try? JSONDecoder().decode([SearchHit].self, from: data) {
            viewed = hits
        }
    }

    func remember(query: String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return }
        queries = Array(([q] + queries.filter { $0.caseInsensitiveCompare(q) != .orderedSame }).prefix(8))
        UserDefaults.standard.set(queries, forKey: queriesKey)
    }

    func remember(viewed hit: SearchHit) {
        viewed = Array(([hit] + viewed.filter { $0.id != hit.id }).prefix(12))
        if let data = try? JSONEncoder().encode(viewed) { UserDefaults.standard.set(data, forKey: viewedKey) }
    }

    func forget(query: String) {
        queries.removeAll { $0 == query }
        UserDefaults.standard.set(queries, forKey: queriesKey)
    }

    func clear() {
        queries = []
        viewed = []
        UserDefaults.standard.removeObject(forKey: queriesKey)
        UserDefaults.standard.removeObject(forKey: viewedKey)
    }
}

// MARK: - The search screen

/// Search, everywhere in the app: it opens ready to type. Before you type it shows your recent
/// searches and what you looked at lately; as you type, matches from your own collection come
/// up instantly, then every card and sealed product in the catalog with filters. Tap a result
/// to open it, or + to add it to your collection straight away.
struct SearchScreen: View {
    enum Mode {
        /// Results open their card page; + adds.
        case browse
        /// Tapping a result goes straight to adding it.
        case add
    }

    var mode: Mode = .browse
    @Environment(\.dismiss) private var dismiss
    @Environment(CollectionStore.self) private var store
    @State private var query = ""
    @State private var results: [SearchHit] = []
    /// How many match in all (results holds the pages loaded so far).
    @State private var total = 0
    @State private var loadingMore = false
    /// Pages already fetched, by query, so going back to a query (or deleting a letter) is instant.
    @State private var cache: [String: (hits: [SearchHit], total: Int, fetched: Int)] = [:]
    /// How far into the server's list we've read (results can be shorter: code cards are left out).
    @State private var fetched = 0
    @State private var searchedFor = ""
    /// The query we last asked TCG API about live (a paid call, so only on request).
    @State private var liveFor = ""
    @State private var liveSearching = false
    @State private var searching = false
    @State private var error: String?
    @State private var filters = SearchFilters()
    @State private var adding: SearchHit?
    @State private var path = NavigationPath()
    @State private var history = SearchHistory.shared
    @FocusState private var focused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    HoloSearchField(text: $query, prompt: mode == .add ? "Add a card or sealed product" : "Search any card or sealed product",
                                    focus: $focused, loading: searching || liveSearching) {
                        history.remember(query: query)
                        // Pressing Search with nothing found looks in the live catalog.
                        if results.isEmpty && searchedFor == trimmed { Task { await searchLive() } }
                    }
                    Button("Cancel") { dismiss() }
                        .font(.geist(16, .medium)).foregroundStyle(Theme.lime)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if trimmed.count < 2 {
                            idle
                        } else {
                            found
                        }
                    }
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.immediately)
                // Thumbnails, decoded off the main thread: scrolling never decodes full-size photos.
                .imageMaxPixel(360)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
            .task(id: trimmed) { await search() }
            .task {
                // Ready to type the moment it opens.
                try? await Task.sleep(nanoseconds: 80_000_000)
                focused = true
            }
            .sheet(item: $adding) { hit in AddPurchaseSheet(hit: hit, onDone: { if mode == .add { dismiss() } }) }
        }
    }

    // MARK: Before typing

    @ViewBuilder private var idle: some View {
        if !history.queries.isEmpty {
            header("Recent searches") {
                Button("Clear") { withAnimation(.snappy) { history.clear() } }
                    .font(.geist(13, .medium)).foregroundStyle(Theme.muted)
            }
            ForEach(history.queries, id: \.self) { q in
                Button { query = q } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 14)).foregroundStyle(Theme.subtle).frame(width: 22)
                        Text(q).font(.geist(16)).foregroundStyle(.white).lineLimit(1)
                        Spacer()
                        Image(systemName: "arrow.up.left").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.subtle)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { Button("Remove", role: .destructive) { history.forget(query: q) } }
            }
        }
        if !history.viewed.isEmpty {
            header("Recently viewed").padding(.top, history.queries.isEmpty ? 0 : 18)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(history.viewed) { hit in
                        Button { open(hit) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HoldingArt(product: hit.product, identity: nil, cornerRadius: 5, caption: false)
                                    .frame(width: 84, height: 116)
                                Text(hit.product.name).font(.geist(12, .medium)).foregroundStyle(.white).lineLimit(2)
                                    .frame(height: 32, alignment: .topLeading)
                                Text(Format.money(hit.market)).font(.geist(12, .semibold)).monospacedDigit().foregroundStyle(Theme.muted)
                            }
                            .frame(width: 84, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: While typing

    private var mine: [HoldingView] {
        let q = trimmed.lowercased()
        return Array(store.holdings.filter { h in
            guard let p = h.product else { return false }
            return p.name.lowercased().contains(q) || (p.setName ?? "").lowercased().contains(q) || (p.number ?? "").lowercased().hasPrefix(q)
        }.prefix(4))
    }

    @ViewBuilder private var found: some View {
        // Worked out once per update, not once per row.
        let owned = Set(store.holdings.map(\.identity.productId))
        let watched = Set(store.watchlist.map(\.product_id))
        let shown = filters.apply(results, owned: owned, watched: watched)
        let mineNow = mine
        let lastId = shown.last?.id
        // Your own copies first: instant, no waiting on the catalog.
        if !mineNow.isEmpty {
            header("In your collection")
            ForEach(mineNow) { h in
                Button {
                    if let p = h.product { open(SearchHit(product: p, printing: h.identity.printing, market: h.price, priceUpdatedAt: nil, gameName: nil)) }
                } label: {
                    HStack(spacing: 12) {
                        HoldingArt(product: h.product, identity: h.identity, cornerRadius: 4, caption: false).frame(width: 40, height: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.product?.name ?? "").font(.geist(15, .medium)).foregroundStyle(.white).lineLimit(1)
                            Text("×\(Int(h.quantity))" + (h.identity.gradeLabel.map { " · \($0)" } ?? "") + (h.product?.setName.map { " · \($0)" } ?? ""))
                                .font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                        Spacer()
                        Text(Format.money(h.price.map { $0 * h.quantity })).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }

        header(searching && results.isEmpty ? "Searching the catalog…" : (shown.count == results.count ? "\(total) in the catalog" : "\(shown.count) of \(results.count) loaded match"))
            .padding(.top, mineNow.isEmpty ? 0 : 14)
        if !results.isEmpty {
            FilterBar(items: results, filters: $filters).padding(.bottom, 8)
        }
        if let error, results.isEmpty {
            Text(error).font(.geist(14)).foregroundStyle(Theme.warn).padding(16)
        } else if searching && results.isEmpty {
            ForEach(0 ..< 5, id: \.self) { _ in SkeletonRow() }
        } else if results.isEmpty && searchedFor == trimmed {
            VStack(alignment: .leading, spacing: 12) {
                Text(liveFor == trimmed ? "Nothing found for \u{201C}\(trimmed)\u{201D}, even live" : "Nothing in Holo's catalog for \u{201C}\(trimmed)\u{201D}")
                    .font(.geist(16, .semibold))
                Text("Try fewer words, the set name, or the card number (like 215/203).").font(.geist(14)).foregroundStyle(Theme.muted)
                if liveFor != trimmed {
                    // The live catalog has things not synced yet, but each look is a paid TCG API call.
                    Button { Task { await searchLive() } } label: {
                        HStack(spacing: 8) {
                            if liveSearching { ProgressView().controlSize(.small).tint(.white) } else { Image(systemName: "bolt.fill") }
                            Text("Search the live catalog")
                        }
                    }
                    .buttonStyle(Button3D(kind: .dark, fullWidth: false, height: 42))
                    .disabled(liveSearching)
                }
            }
            .padding(16)
        } else if shown.isEmpty && !results.isEmpty {
            Button("No results match these filters. Clear filters") { filters = SearchFilters(sort: filters.sort) }
                .font(.geist(14)).foregroundStyle(Theme.muted).padding(16)
        }
        ForEach(shown) { hit in
            ResultRow(hit: hit, owned: owned.contains(hit.product.id), onOpen: { open(hit) }, onAdd: {
                history.remember(query: query)
                store.seed(hit)
                adding = hit
            })
            .equatable()
            // At the end of what's loaded, fetch the next batch.
            .onAppear { if hit.id == lastId { Task { await loadMore() } } }
        }
        if fetched < total {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(Theme.muted)
                Text("Loading more · \(results.count) of \(total)").font(.geist(13)).foregroundStyle(Theme.muted).monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .onAppear { Task { await loadMore() } }
        }
    }

    private func header(_ title: String) -> some View {
        header(title) { EmptyView() }
    }

    private func header<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            MonoLabel(text: title)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func open(_ hit: SearchHit) {
        history.remember(query: query)
        history.remember(viewed: hit)
        store.seed(hit)
        focused = false
        if mode == .add { adding = hit } else { path.append(hit.product.id) }
    }

    private static let pageSize = 40

    private func search() async {
        let q = trimmed
        guard q.count >= 2 else {
            results = []
            total = 0
            fetched = 0
            error = nil
            searchedFor = ""
            return
        }
        // Seen this query already: show it at once.
        if let hit = cache[q.lowercased()] {
            results = hit.hits
            total = hit.total
            fetched = hit.fetched
            error = nil
            searchedFor = q
            return
        }
        // Debounced: a short pause in typing; the old results stay up meanwhile.
        try? await Task.sleep(nanoseconds: 180_000_000)
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        do {
            let page = try await Backend.shared.api.searchPage(q, offset: 0, limit: Self.pageSize)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.2)) {
                results = page.hits
                total = page.total
            }
            fetched = page.count
            cache[q.lowercased()] = (page.hits, page.total, page.count)
            error = nil
            searchedFor = q
        } catch {
            guard !Task.isCancelled else { return }
            self.error = "Couldn't search right now. Check your connection."
            searchedFor = q
        }
    }

    /// Look for the query in TCG API live (one paid call), when the stored catalog had nothing.
    @MainActor
    private func searchLive() async {
        let q = trimmed
        guard q.count >= 2, !liveSearching, liveFor != q else { return }
        liveSearching = true
        defer { liveSearching = false }
        let hits = (try? await Backend.shared.api.liveSearch(q)) ?? []
        guard q == trimmed else { return }
        liveFor = q
        withAnimation(.snappy(duration: 0.2)) {
            results = hits
            total = hits.count
        }
        fetched = hits.count
        cache[q.lowercased()] = (hits, hits.count, hits.count)
    }

    /// The next batch of results for the same query.
    @MainActor
    private func loadMore() async {
        let q = trimmed
        guard !loadingMore, !searching, fetched < total, q == searchedFor else { return }
        loadingMore = true
        defer { loadingMore = false }
        guard let page = try? await Backend.shared.api.searchPage(q, offset: fetched, limit: Self.pageSize), q == trimmed else { return }
        let seen = Set(results.map(\.id))
        results += page.hits.filter { !seen.contains($0.id) }
        // A short page means we've reached the end, whatever the total said.
        fetched += page.count
        if page.count == 0 { total = fetched }
        cache[q.lowercased()] = (results, total, fetched)
    }
}

/// One catalog result: its picture, name, brand · set · number, price, an "Owned" mark, and +.
/// Equatable, so a row only redraws when its own result changes, not on every list update.
private struct ResultRow: View, Equatable {
    var hit: SearchHit
    var owned: Bool
    var onOpen: () -> Void
    var onAdd: () -> Void

    static func == (a: ResultRow, b: ResultRow) -> Bool { a.hit == b.hit && a.owned == b.owned }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    HoldingArt(product: hit.product, identity: nil, cornerRadius: 4, caption: false).frame(width: 44, height: 62)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(hit.product.name).font(.geist(15, .medium)).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.leading)
                        Text([hit.gameName, hit.product.setName, hit.product.number.map { "#\($0)" }].compactMap { $0 }.joined(separator: " · "))
                            .font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1)
                        HStack(spacing: 6) {
                            Text(Format.money(hit.market)).font(.geist(14, .semibold)).monospacedDigit().foregroundStyle(.white)
                            if owned {
                                Label("Owned", systemImage: "checkmark").font(.geist(11, .semibold)).foregroundStyle(Theme.lime)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: onAdd) {
                Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.lime))
            }
            .buttonStyle(ShutterStyle())
            .accessibilityLabel("Add \(hit.product.name) to your collection")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// A placeholder row while the catalog answers.
private struct SkeletonRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4).fill(Theme.surface2).frame(width: 44, height: 62)
            VStack(alignment: .leading, spacing: 8) {
                Capsule().fill(Theme.surface2).frame(width: 180, height: 12)
                Capsule().fill(Theme.surface2).frame(width: 120, height: 10)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .opacity(dim ? 0.5 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { dim = true }
        }
    }
}

/// A row of filter menus over search results; options come from the results themselves.
struct FilterBar: View {
    var items: [SearchHit]
    @Binding var filters: SearchFilters
    @State private var pricing = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                menu(filters.kind == .all ? "Type" : (filters.kind == .single ? "Cards" : "Sealed"), on: filters.kind != .all) {
                    ForEach(SearchFilters.Kind.allCases, id: \.self) { k in Button(k.rawValue) { filters.kind = k } }
                }
                let languages = SearchFilters.facet(items) { SearchFilters.language(of: $0.gameName) }
                menu(filters.language ?? "Language", on: filters.language != nil) {
                    Button("Any language") { filters.language = nil }
                    ForEach(languages, id: \.value) { l in Button("\(l.value) (\(l.count))") { filters.language = l.value } }
                }
                let brands = SearchFilters.facet(items) { SearchFilters.brand(of: $0.gameName) }
                if brands.count > 1 || filters.brand != nil {
                    menu(filters.brand ?? "Brand", on: filters.brand != nil) {
                        Button("Every brand") { filters.brand = nil }
                        ForEach(brands, id: \.value) { b in Button("\(b.value) (\(b.count))") { filters.brand = b.value } }
                    }
                }
                menu(filters.owned == .owned ? "Owned" : (filters.owned == .notOwned ? "Not owned" : "Owned"), on: filters.owned != .any) {
                    ForEach(SearchFilters.Owned.allCases, id: \.self) { o in Button(o.rawValue) { filters.owned = o } }
                }
                chip("Watchlist", icon: "eye", on: filters.watchlist) { filters.watchlist.toggle() }
                chip(priceLabel, icon: nil, on: filters.min != nil || filters.max != nil) { pricing = true }
                menu(filters.sort.rawValue, on: false, icon: "arrow.up.arrow.down") {
                    ForEach(SearchFilters.Sort.allCases, id: \.self) { s in Button(s.rawValue) { filters.sort = s } }
                }
                if filters.activeCount > 0 {
                    chip("Clear", icon: "xmark", on: false) { filters = SearchFilters(sort: filters.sort) }
                }
            }
            .padding(.horizontal, 16)
        }
        .sheet(isPresented: $pricing) { PriceRangeSheet(filters: $filters) }
    }

    private var priceLabel: String {
        guard filters.min != nil || filters.max != nil else { return "Price" }
        return "\(filters.min.map { Format.moneyWhole($0) } ?? "$0")–\(filters.max.map { Format.moneyWhole($0) } ?? "any")"
    }

    private func menu<Content: View>(_ title: String, on: Bool, icon: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        Menu { content() } label: { chipLabel(title, icon: icon ?? "chevron.down", on: on, trailingIcon: icon == nil) }
    }

    private func chip(_ title: String, icon: String?, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(title, icon: icon, on: on, trailingIcon: false) }
    }

    private func chipLabel(_ title: String, icon: String?, on: Bool, trailingIcon: Bool) -> some View {
        HStack(spacing: 5) {
            if let icon, !trailingIcon { Image(systemName: icon).font(.caption2.weight(.bold)) }
            Text(title).monospacedDigit()
            if let icon, trailingIcon { Image(systemName: icon).font(.caption2.weight(.bold)) }
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 12)
        .frame(height: 34)
        .foregroundStyle(on ? Theme.ink : .white)
        .background { if on { Capsule().fill(Theme.lime) } else { Color.clear.liquidGlass(in: Capsule()).allowsHitTesting(false) } }
    }
}

struct PriceRangeSheet: View {
    @Binding var filters: SearchFilters
    @Environment(\.dismiss) private var dismiss
    @State private var min = ""
    @State private var max = ""

    var body: some View {
        NavigationStack {
            Form {
                MoneyField(title: "Minimum", text: $min, hint: "Any")
                MoneyField(title: "Maximum", text: $max, hint: "Any")
                Section { Text("Items without a price are left out when a range is set.").font(.footnote).foregroundStyle(Theme.muted) }
            }
            .navigationTitle("Price range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Clear") { filters.min = nil; filters.max = nil; dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        filters.min = MoneyField.value(min)
                        filters.max = MoneyField.value(max)
                        dismiss()
                    }
                }
            }
            .onAppear {
                min = filters.min.map { String(format: "%.0f", $0) } ?? ""
                max = filters.max.map { String(format: "%.0f", $0) } ?? ""
            }
        }
        .presentationDetents([.medium])
    }
}

