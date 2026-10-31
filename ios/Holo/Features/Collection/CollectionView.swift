import SwiftUI

/// Everything you hold, like the website's Collection: value, gain and holdings up top, then
/// search, sort, grid or list, and Sealed / Singles / Graded.
struct CollectionView: View {
    var onScan: () -> Void
    @Environment(CollectionStore.self) private var store
    @Environment(SessionModel.self) private var session
    @Environment(GroupsStore.self) private var groups
    @State private var adding = false
    @State private var shelfId: String?
    /// The name being typed for a new shelf or portfolio, and which one it's for.
    @State private var naming: Naming?
    @State private var name = ""
    @State private var groupError: String?

    enum Naming: Identifiable {
        case shelf, portfolio, renamePortfolio(String)
        var id: String {
            switch self {
            case .shelf: "shelf"
            case .portfolio: "portfolio"
            case let .renamePortfolio(id): "rename-\(id)"
            }
        }
    }
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var category: HoldingCategory?
    @State private var sort = Sort.value
    /// The website's extra filters: one set, one product type, and in profit or at a loss.
    @State private var setFilter: String?
    @State private var typeFilter: String?
    @State private var perf = Perf.all

    enum Perf: String, CaseIterable { case all = "All", profit = "In profit", loss = "At a loss" }
    @State private var grid = true
    @State private var router = Router.shared

    enum Sort: String, CaseIterable {
        case value = "Holding value", gain = "Gain", gainPct = "Gain %", day = "Today's move", recent = "Recently added", name = "Name"
    }

    private var shown: [HoldingView] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let shelf = groups.shelves.first { $0.id == shelfId }
        let filtered = store.holdings.filter { h in
            (shelf == nil || shelf!.product_ids.contains(h.identity.productId)) &&
            (category == nil || h.category == category) &&
            (setFilter == nil || h.product?.setName == setFilter) &&
            (typeFilter == nil || h.product.map(Analytics.category) == typeFilter) &&
            (perf == .all || (perf == .profit ? (h.gain ?? 0) > 0 : (h.gain ?? 0) < 0)) &&
                (q.isEmpty || (h.product?.name ?? "").lowercased().contains(q) || (h.product?.setName ?? "").lowercased().contains(q))
        }
        switch sort {
        case .value: return filtered.sorted { ($0.value ?? -1) > ($1.value ?? -1) }
        case .gain: return filtered.sorted { ($0.gain ?? -.infinity) > ($1.gain ?? -.infinity) }
        case .gainPct: return filtered.sorted { ($0.gainRatio ?? -.infinity) > ($1.gainRatio ?? -.infinity) }
        case .day: return filtered.sorted { ($0.change24hPct ?? -.infinity) > ($1.change24hPct ?? -.infinity) }
        case .recent: return filtered.sorted { ($0.lastAcquired ?? "") > ($1.lastAcquired ?? "") }
        case .name: return filtered.sorted { ($0.product?.name ?? "") < ($1.product?.name ?? "") }
        }
    }

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                switch store.status {
                case .idle, .loading:
                    ProgressView().padding(.top, 160)
                case let .failed(message):
                    VStack(spacing: 12) {
                        Text("Couldn't load your collection").font(.geist(17, .semibold))
                        Text(message).font(.geist(14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                        Button("Try again") { Task { await reload() } }.buttonStyle(Button3D(kind: .dark, fullWidth: false))
                    }
                    .padding(32)
                case .ready:
                    VStack(alignment: .leading, spacing: 20) {
                        portfolioSwitcher
                        if let groupError { Text(groupError).font(.geist(13)).foregroundStyle(Theme.muted) }
                        header
                        if store.holdings.isEmpty {
                            empty
                        } else {
                            controls
                            // Filtered and sorted once per redraw.
                            let shown = self.shown
                            if shown.isEmpty {
                                Text("Nothing matches.").font(.geist(15)).foregroundStyle(Theme.muted).padding(.vertical, 40).frame(maxWidth: .infinity)
                            } else if grid {
                                LazyVGrid(columns: columns, spacing: 28) {
                                    ForEach(shown) { h in
                                        NavigationLink(value: h.identity.productId) { HoldingTile(holding: h) }.buttonStyle(.plain)
                                    }
                                }
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(shown) { h in
                                        NavigationLink(value: h.identity.productId) { HoldingListRow(holding: h) }.buttonStyle(.plain)
                                        Divider().overlay(Theme.border)
                                    }
                                }
                                .surface(padding: nil)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
            .background(Theme.background)
            .imageMaxPixel(600)
            .replaysAnimations()
            .tabBarClearance()
            .refreshable { await reload() }
            .navigationBarTitleDisplayMode(.inline)
            .pageTitle("Collection")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { FreshnessChip(refreshedAt: store.pricesRefreshedAt) }
            }
            .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
            .fullScreenCover(isPresented: $adding) { SearchScreen(mode: .add) }
            .onAppear { applyRequest() }
            .onChange(of: router.collectionCategory) { _, _ in applyRequest() }
        }
    }

    /// All portfolios, Main, or one of yours: filters every number, like the website's switcher.
    private var portfolioSwitcher: some View {
        Menu {
            Picker("Portfolio", selection: Binding(get: { groups.selected }, set: { groups.select($0, store: store) })) {
                Text("All portfolios").tag(GroupsStore.all)
                Text("Main").tag(GroupsStore.main)
                ForEach(groups.portfolios) { Text($0.name).tag($0.id) }
            }
            Divider()
            Button { naming = .portfolio } label: { Label("New portfolio…", systemImage: "plus") }
            if groups.portfolios.contains(where: { $0.id == groups.selected }) {
                let id = groups.selected
                Button { name = groups.name(of: id); naming = .renamePortfolio(id) } label: { Label("Rename portfolio…", systemImage: "pencil") }
                Button(role: .destructive) {
                    Task { await groupRun { try await groups.removePortfolio(id, store: store) } }
                } label: { Label("Delete portfolio", systemImage: "trash") }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder").font(.system(size: 13, weight: .semibold))
                Text(groups.name(of: groups.selected)).font(.geist(14, .semibold))
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).frame(height: 36)
            .liquidGlass(in: Capsule())
        }
        .alert(namingTitle, isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) { name = "" }
            Button("Save") { saveName() }
        }
    }

    private var namingTitle: String {
        switch naming {
        case .shelf: "New shelf"
        case .portfolio: "New portfolio"
        case .renamePortfolio: "Rename portfolio"
        case nil: ""
        }
    }

    private func saveName() {
        let value = String(name.trimmingCharacters(in: .whitespaces).prefix(40))
        let what = naming
        name = ""
        naming = nil
        guard !value.isEmpty, let what else { return }
        Task {
            await groupRun {
                switch what {
                case .shelf: shelfId = try await groups.createShelf(value).id
                case .portfolio: try await groups.createPortfolio(value, store: store)
                case let .renamePortfolio(id): try await groups.renamePortfolio(id, to: value)
                }
            }
        }
    }

    @MainActor
    private func groupRun(_ work: () async throws -> Void) async {
        do {
            groupError = nil
            try await work()
        } catch {
            groupError = error.localizedDescription
        }
    }

    private func applyRequest() {
        if let c = router.collectionCategory {
            category = c
            router.collectionCategory = nil
        }
    }

    private var header: some View {
        let s = store.summary
        let month = Array(store.timeline.suffix(31))
        let monthChange = (month.last?.value ?? 0) - (month.first?.value ?? 0)
        let monthTone = monthChange < 0 ? Theme.planPink : Theme.lime
        return VStack(alignment: .leading, spacing: 18) {
            // The value, counting up, with the all-time gain under it.
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel(text: "Value")
                CountingText(value: s.value, format: { Format.money($0) })
                    .font(.display(56)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    .displayTrim(56)
                    .shadow(color: .white.opacity(0.12), radius: 18)
                HStack(spacing: 8) {
                    DeltaPill(ratio: s.gainRatio, size: 13)
                    Text(Format.signedMoney(s.gain)).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(Theme.tone(s.gain))
                    Text("all time").font(.geist(13)).foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            // The last 30 days, drawing itself in.
            if month.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Sparkline(points: month, color: monthTone).frame(height: 54)
                    HStack {
                        MonoLabel(text: "Last 30 days")
                        Spacer()
                        Text(Format.signedMoney(monthChange)).font(.geist(12, .semibold)).monospacedDigit().foregroundStyle(Theme.tone(monthChange))
                    }
                }
            }
            // Glass stat tiles.
            HStack(spacing: 8) {
                statTile("Today", Format.signedMoney(s.dayChange), Theme.tone(s.dayChange))
                statTile("Items", "\(Int(s.items))", .white)
                statTile("Paid", Format.money(s.totalCost), .white)
            }
            AllocationBar(holdings: store.holdings, total: s.value)
        }
        .background(alignment: .top) {
            CollectionBackdrop().padding(.horizontal, -16).padding(.top, -160).padding(.bottom, -40)
        }
    }

    private func statTile(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoLabel(text: label)
            Text(value).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                HoloSearchField(text: $query, prompt: "Search your collection", focus: $searchFocused)
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .menuStyle(.button)
                .buttonStyle(IconButton3D(size: 46))
                filterMenu
                HStack(spacing: 2) {
                    Button { grid = true } label: { Image(systemName: "square.grid.2x2") }.buttonStyle(IconButton3D(size: 40, active: grid, inTrack: true))
                    Button { grid = false } label: { Image(systemName: "list.bullet") }.buttonStyle(IconButton3D(size: 40, active: !grid, inTrack: true))
                }
                .padding(3)
                .liquidGlass(in: Capsule())
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    Chip(title: "All", selected: category == nil && shelfId == nil, count: store.holdings.count) { category = nil; shelfId = nil }
                    ForEach(HoldingCategory.allCases) { c in
                        let n = store.holdings.filter { $0.category == c }.count
                        if n > 0 { Chip(title: c.rawValue, selected: category == c && shelfId == nil, count: n) { category = c; shelfId = nil } }
                    }
                    // Your shelves (shared with the website); hold one to rename or delete it.
                    ForEach(groups.shelves) { shelf in
                        let n = store.holdings.filter { shelf.product_ids.contains($0.identity.productId) }.count
                        Chip(title: shelf.name, selected: shelfId == shelf.id, count: n) { shelfId = shelf.id; category = nil }
                            .contextMenu {
                                Button("Delete shelf", role: .destructive) {
                                    if shelfId == shelf.id { shelfId = nil }
                                    Task { await groupRun { try await groups.removeShelf(shelf.id) } }
                                }
                            }
                    }
                    Button { naming = .shelf } label: {
                        Label("Shelf", systemImage: "plus").font(.geist(14, .semibold)).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 14).frame(height: 36)
                    }
                    .buttonStyle(.plain)
                }
                .padding(4)
                .liquidGlass(in: Capsule())
                // Room for the selected chip's glow, which the scroll view would otherwise clip.
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)
            .padding(.vertical, -8)
            if sort != .value || filtersOn {
                HStack(spacing: 8) {
                    Text(filterSummary).font(.geist(13)).foregroundStyle(Theme.muted).lineLimit(1)
                    if filtersOn {
                        Button("Clear") { setFilter = nil; typeFilter = nil; perf = .all }
                            .font(.geist(13, .medium)).foregroundStyle(.white)
                    }
                }
            }
        }
    }

    private var filtersOn: Bool { setFilter != nil || typeFilter != nil || perf != .all }

    private var filterSummary: String {
        var parts: [String] = []
        if let setFilter { parts.append(setFilter) }
        if let typeFilter { parts.append(typeFilter) }
        if perf != .all { parts.append(perf.rawValue.lowercased()) }
        if sort != .value { parts.append("sorted by \(sort.rawValue.lowercased())") }
        let text = parts.joined(separator: " · ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Filter by set, product type and profit or loss, like the website's filter panel.
    private var filterMenu: some View {
        let sets = Array(Set(store.holdings.compactMap { $0.product?.setName })).sorted()
        let types: [String] = ["Card", "Booster Box", "Elite Trainer Box", "Ultra Premium Collection", "Booster Bundle", "Collection Box", "Tin", "Booster Pack", "Other Sealed"]
            .filter { t in store.holdings.contains { $0.product.map(Analytics.category) == t } }
        return Menu {
            Picker("Profit", selection: $perf) {
                ForEach(Perf.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Menu("Set: \(setFilter ?? "All")") {
                Picker("Set", selection: $setFilter) {
                    Text("All sets").tag(String?.none)
                    ForEach(sets, id: \.self) { Text($0).tag(String?.some($0)) }
                }
            }
            Menu("Type: \(typeFilter ?? "All")") {
                Picker("Type", selection: $typeFilter) {
                    Text("All types").tag(String?.none)
                    ForEach(types, id: \.self) { Text($0).tag(String?.some($0)) }
                }
            }
            if filtersOn {
                Button("Clear filters", role: .destructive) { setFilter = nil; typeFilter = nil; perf = .all }
            }
        } label: {
            Image(systemName: filtersOn ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
        }
        .menuStyle(.button)
        .buttonStyle(IconButton3D(size: 46, active: filtersOn))
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 44)).foregroundStyle(Theme.lime)
            Text("START YOUR COLLECTION").font(.display(28))
            Text("Scan your cards, or search for anything you own.").font(.geist(15)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Button { onScan() } label: { Label("Scan cards", systemImage: "viewfinder") }.buttonStyle(Button3D(kind: .lime))
            Button("Search instead") { adding = true }.font(.geist(15, .medium)).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 40)
    }

    private func reload() async {
        if case let .signedIn(userId, _) = session.state { await store.load(userId: userId) }
    }
}

/// The website's collection tile: the piece on a dark stage, then name, Anton value and gain.
struct HoldingTile: View {
    var holding: HoldingView

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // A fixed 5:7 stage the art is sized into. Sizing the image itself by aspect ratio let
            // photos fall back to their tiny pixel size.
            Color.clear
                .aspectRatio(0.72, contentMode: .fit)
                .overlay {
                    HoldingArt(product: holding.product, identity: holding.identity, cornerRadius: holding.product?.imageURL == nil ? 22 : 12)
                }
                .overlay(alignment: .topLeading) {
                    if holding.quantity > 1 {
                        Text("×\(Int(holding.quantity))").font(.geist(12, .semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Theme.background.opacity(0.85)))
                            .overlay(Capsule().strokeBorder(Theme.border))
                            .padding(10)
                    }
                }
            Text(holding.product?.name ?? "Unknown").font(.geist(16, .medium)).lineLimit(1).padding(.top, 8)
            Text(subtitle).font(.geist(13)).foregroundStyle(Theme.muted).lineLimit(1)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text((holding.isConditionEstimate ? "≈" : "") + Format.money(holding.value))
                        .font(.display(22)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    Text("\(Format.money(holding.price)) ea").font(.geist(12)).foregroundStyle(Theme.muted).monospacedDigit()
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    DeltaPill(ratio: holding.gainRatio, size: 12)
                    Delta(value: holding.gain, size: 12)
                }
            }
            .padding(.top, 2)
        }
    }

    private var subtitle: String {
        let type = holding.identity.isGraded ? (holding.label ?? "Graded") : (holding.product?.isSealed == true ? (holding.product?.productType ?? "Sealed") : (holding.label ?? "Card"))
        return [holding.product?.setName, type].compactMap { $0 }.joined(separator: " · ")
    }
}

/// The list view's row.
private struct HoldingListRow: View {
    var holding: HoldingView

    var body: some View {
        HStack(spacing: 12) {
            HoldingArt(product: holding.product, identity: holding.identity, cornerRadius: 6, caption: false).frame(width: 44, height: 60)
            VStack(alignment: .leading, spacing: 3) {
                Text(holding.product?.name ?? "Unknown").font(.geist(15, .medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(holding.product?.setName ?? "").lineLimit(1)
                    if let label = holding.label { Tag(text: label, tint: .white) }
                }
                .font(.geist(13)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text((holding.isConditionEstimate ? "≈" : "") + Format.money(holding.value)).font(.geist(15, .semibold)).monospacedDigit()
                Delta(value: holding.gain, size: 13)
                Text(Format.signedPercent(holding.gainRatio)).font(.geist(12)).foregroundStyle(Theme.tone(holding.gainRatio)).monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// How the collection's value splits between sealed, singles and graded: one bar that grows in,
/// in each kind's color, with the shares underneath.
/// How your value splits between sealed, singles and graded: a thin bar that grows in, with a
/// legend. Used on Collection and on Home's "Where your value sits".
struct AllocationBar: View {
    var holdings: [HoldingView]
    var total: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    private var parts: [(HoldingCategory, Double)] {
        guard total > 0 else { return [] }
        return HoldingCategory.allCases.compactMap { c in
            let v = holdings.filter { $0.category == c }.reduce(0) { $0 + ($1.value ?? 0) }
            return v > 0 ? (c, v / total) : nil
        }
    }

    var body: some View {
        let parts = self.parts
        if !parts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { geo in
                    HStack(spacing: 3) {
                        ForEach(parts, id: \.0) { c, share in
                            Capsule().fill(c.color)
                                .frame(width: max(6, (geo.size.width - CGFloat(parts.count - 1) * 3) * share * (grown || reduceMotion ? 1 : 0)))
                                .shadow(color: c.color.opacity(0.5), radius: 6)
                        }
                    }
                }
                .frame(height: 10)
                HStack(spacing: 14) {
                    ForEach(parts, id: \.0) { c, share in
                        HStack(spacing: 6) {
                            Circle().fill(c.color).frame(width: 7, height: 7)
                            Text(c.rawValue).font(.geist(12, .medium)).foregroundStyle(Theme.muted)
                            Text("\(Int((share * 100).rounded()))%").font(.geist(12, .semibold)).monospacedDigit().foregroundStyle(.white)
                        }
                    }
                }
            }
            .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.85).delay(0.2)) { grown = true } }
            .onReplay {
                grown = false
                withAnimation(.spring(response: 0.9, dampingFraction: 0.85).delay(0.15)) { grown = true }
            }
        }
    }
}

/// The lit backdrop behind the top of Collection: the website's faint grid with still lime, pink
/// and blue glows, fading out toward the holdings.
struct CollectionBackdrop: View {
    var body: some View {
        ZStack {
            GridPattern(step: 36, opacity: 0.05)
            glow(Theme.lime, 0.22, at: UnitPoint(x: 0.2, y: 0.42), r: 260)
            glow(Theme.planPink, 0.18, at: UnitPoint(x: 0.85, y: 0.2), r: 220)
            glow(Theme.planBlue, 0.18, at: UnitPoint(x: 0.75, y: 0.72), r: 220)
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
    }

    private func glow(_ color: Color, _ strength: Double, at center: UnitPoint, r: CGFloat) -> some View {
        RadialGradient(colors: [color.opacity(strength), .clear], center: center, startRadius: 0, endRadius: r)
    }
}

/// A glass chip with a breathing lime dot: how fresh the prices are.
private struct FreshnessChip: View {
    var refreshedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ping = false

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle().fill(Theme.lime.opacity(0.6)).scaleEffect(ping ? 2.2 : 1).opacity(ping ? 0 : 0.6)
                Circle().fill(Theme.lime)
            }
            .frame(width: 7, height: 7)
            Text(label).font(.mono(11, .medium)).tracking(0.6).foregroundStyle(Theme.muted)
        }
        .fixedSize()
        .padding(.horizontal, 12)
        .frame(height: 32)
        .modifier(BarGlass())
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { ping = true }
        }
    }

    private var label: String {
        guard let d = refreshedAt else { return "LIVE" }
        let minutes = Int(Date().timeIntervalSince(d) / 60)
        if minutes < 60 { return "\(max(minutes, 1))M AGO" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)H AGO" }
        return "\(hours / 24)D AGO"
    }
}

/// In the top bar iOS 26 already puts the item on Liquid Glass, so the chip adds nothing of its
/// own there; older iOS gets the frosted capsule.
private struct BarGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
        } else {
            content.liquidGlass(in: Capsule())
        }
    }
}
