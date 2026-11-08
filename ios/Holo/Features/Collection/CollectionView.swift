import SwiftUI

/// Everything you hold, like the website's Collection: value, gain and holdings up top, then
/// search, sort, grid or list, and Sealed / Singles / Graded.
struct CollectionView: View {
    var onScan: () -> Void
    @Environment(CollectionStore.self) private var store
    @Environment(SessionModel.self) private var session
    @Environment(GroupsStore.self) private var groups
    @State private var adding = false
    /// Your copy, opened from the grid; "View card details" pushes the card page.
    @State private var opened: HoldingView?
    @State private var path = NavigationPath()
    @State private var shelfId: String?
    /// Showing only the cards you pulled from packs.
    @State private var pullsOnly = false
    /// Asking before deleting the open shelf.
    @State private var deletingShelf = false
    /// The name being typed for a new shelf or portfolio, and which one it's for.
    @State private var naming: Naming?
    @State private var name = ""
    @State private var groupError: String?
    /// The list of every shelf and portfolio, to rename or delete them.
    @State private var managing = false
    /// The portfolio menu (our own frosted panel, opened from the portfolio pill).
    @State private var portfolioMenu = false
    /// Quick actions from a long press on a tile: sell, or work out what selling would leave.
    @State private var selling: HoldingView?
    @State private var whatIf: HoldingView?
    @State private var removing: HoldingView?
    @State private var editingDetails: HoldingView?
    @State private var deleting: HoldingView?
    /// A product to put on the shelf being named (from a tile's "Add to shelf → New shelf…").
    @State private var shelfProduct: String?
    /// Select mode (the bulk editor): the holding keys picked, all of what's shown to start with.
    @State private var selecting = false
    @State private var picked: Set<String> = []
    @State private var confirmingBulkDelete = false
    @State private var bulkBusy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Naming: Identifiable {
        case shelf, portfolio, renamePortfolio(String), renameShelf(String)
        var id: String {
            switch self {
            case .shelf: "shelf"
            case .portfolio: "portfolio"
            case let .renamePortfolio(id): "rename-\(id)"
            case let .renameShelf(id): "rename-shelf-\(id)"
            }
        }
    }
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    /// The chosen kind (screenshots can start on one with `-HoloCategory singles`).
    @State private var category: HoldingCategory? = Demo.value("-HoloCategory").flatMap { HoldingCategory(rawValue: $0.capitalized) }
    @State private var sort = Sort.value
    /// The website's extra filters: one set, one product type, and in profit or at a loss.
    @State private var setFilter: String?
    @State private var typeFilter: String?
    @State private var perf = Perf.all

    enum Perf: String, CaseIterable { case all = "All", profit = "In profit", loss = "At a loss" }
    @State private var grid = true
    @State private var router = Router.shared

    private static var openedOnce = false

    enum Sort: String, CaseIterable {
        case value = "Holding value", gain = "Gain", gainPct = "Gain %", day = "Today's move", recent = "Recently added", name = "Name"
    }

    // Filtering, sorting and counting are remembered for the inputs they came from, so a redraw
    // that changes none of them (tapping a tile, opening a sheet or a menu) doesn't redo them.
    @State private var shownMemo = CollectionMemo<ShownKey, [HoldingView]>()
    @State private var countsMemo = CollectionMemo<CountsKey, ChipCounts>()
    @State private var optionsMemo = CollectionMemo<[HoldingView], FilterOptions>()

    private struct ShownKey: Equatable {
        var holdings: [HoldingView]
        var query: String
        var category: HoldingCategory?
        var sort: Sort
        var setFilter: String?
        var typeFilter: String?
        var perf: Perf
        /// The selected shelf's products; nil when no shelf is picked.
        var shelf: [String]?
        /// The pulled copies' keys, when showing only pulls.
        var pulls: Set<String>?
    }

    private struct CountsKey: Equatable {
        var holdings: [HoldingView]
        var shelves: [GroupsStore.Shelf]
    }

    private struct ChipCounts {
        var categories: [HoldingCategory: Int] = [:]
        var shelves: [String: Int] = [:]
    }

    private struct FilterOptions {
        var sets: [String]
        var types: [String]
    }

    private var shown: [HoldingView] {
        let key = ShownKey(
            holdings: store.holdings, query: query, category: category, sort: sort, setFilter: setFilter,
            typeFilter: typeFilter, perf: perf, shelf: groups.shelves.first { $0.id == shelfId }?.product_ids,
            pulls: pullsOnly ? store.pulledKeys : nil
        )
        return shownMemo(key) { Self.filterAndSort(key) }
    }

    private static func filterAndSort(_ k: ShownKey) -> [HoldingView] {
        let q = k.query.trimmingCharacters(in: .whitespaces).lowercased()
        let shelf = k.shelf.map { Set($0) }
        let category = k.category, setFilter = k.setFilter, typeFilter = k.typeFilter, perf = k.perf
        let pulls = k.pulls
        let filtered = k.holdings.filter { h in
            (pulls == nil || pulls!.contains(h.identity.key)) &&
            (shelf == nil || shelf!.contains(h.identity.productId)) &&
            (category == nil || h.category == category) &&
            (setFilter == nil || h.product?.setName == setFilter) &&
            (typeFilter == nil || h.product.map(Analytics.category) == typeFilter) &&
            (perf == .all || (perf == .profit ? (h.gain ?? 0) > 0 : (h.gain ?? 0) < 0)) &&
                (q.isEmpty || (h.product?.name ?? "").lowercased().contains(q) || (h.product?.setName ?? "").lowercased().contains(q))
        }
        switch k.sort {
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
        NavigationStack(path: $path) {
            ScrollView {
                switch store.status {
                case .idle, .loading:
                    // First launch only (later launches open on the saved collection): dim, still shapes.
                    LoadingPlaceholder(layout: .collection)
                case let .failed(message):
                    VStack(spacing: 12) {
                        Text("Couldn't load your collection").font(.geist(17, .semibold))
                        Text(message).font(.geist(14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                        Button("Try again") { Task { await reload() } }.buttonStyle(Button3D(kind: .dark, fullWidth: false))
                    }
                    .padding(32)
                case .ready:
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 8) {
                            portfolioSwitcher
                            Spacer(minLength: 0)
                            if !store.holdings.isEmpty { selectPill }
                        }
                        // Drawn above the header's backdrop: that backdrop reaches up behind this
                        // row, and coming later it was painted over the pills, grid and all, so
                        // nothing on them could blur it.
                        .zIndex(1)
                        if let groupError { Text(groupError).font(.geist(13)).foregroundStyle(Theme.muted) }
                        header
                        if store.holdings.isEmpty {
                            empty
                        } else {
                            controls
                            // An open shelf: its name, with rename and delete on the right.
                            if let shelf = groups.shelves.first(where: { $0.id == shelfId }), !pullsOnly {
                                HStack(spacing: 10) {
                                    Text(shelf.name).font(.display(20)).tracking(-0.5).lineLimit(1)
                                    Spacer(minLength: 8)
                                    Button { name = shelf.name; naming = .renameShelf(shelf.id) } label: {
                                        Label("Rename", systemImage: "pencil").font(.geist(14, .semibold))
                                    }
                                    .buttonStyle(Button3D(kind: .dark, fullWidth: false, height: 34))
                                    Button { deletingShelf = true } label: {
                                        Image(systemName: "trash").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.down)
                                    }
                                    .buttonStyle(Button3D(kind: .dark, fullWidth: false, height: 34))
                                    .accessibilityLabel("Delete list")
                                }
                                .confirmationDialog("Delete \(shelf.name)?", isPresented: $deletingShelf, titleVisibility: .visible) {
                                    Button("Delete list", role: .destructive) {
                                        let id = shelf.id
                                        reshuffle { shelfId = nil }
                                        Task { await groupRun { try await groups.removeShelf(id) } }
                                    }
                                } message: {
                                    Text("The list goes; its cards stay in your collection.")
                                }
                            }
                            if pullsOnly {
                                // What your pulls add up to.
                                let pulls = store.pulledHoldings
                                HStack(spacing: 8) {
                                    PulledBadge()
                                    (Text("Your pulls are worth ").foregroundColor(Theme.muted)
                                        + Text(Format.money(pulls.reduce(0) { $0 + ($1.value ?? 0) })).foregroundColor(Theme.lime).fontWeight(.semibold))
                                        .font(.geist(15)).monospacedDigit()
                                }
                            }
                            if let category, shelfId == nil, !pullsOnly {
                                CategoryBanner(category: category, holdings: store.holdings, total: store.summary.value).equatable()
                            }
                            // Filtered and sorted once per redraw.
                            let shown = self.shown
                            if shown.isEmpty {
                                Text("Nothing matches.").font(.geist(15)).foregroundStyle(Theme.muted).padding(.vertical, 40).frame(maxWidth: .infinity)
                            } else if grid {
                                LazyVGrid(columns: columns, spacing: 28) {
                                    ForEach(shown) { h in
                                        gridItem(h)
                                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                                    }
                                }
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(shown) { h in
                                        VStack(spacing: 0) {
                                            listItem(h)
                                            Divider().overlay(Theme.border)
                                        }
                                        .transition(.scale(scale: 0.92).combined(with: .opacity))
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
            // No scroll bar beside the placeholder while loading.
            .scrollIndicators(store.status == .ready ? .automatic : .hidden)
            // A tap on this tab (from anywhere) closes pushed pages and scrolls back to the top.
            .tabTopReset("collection", path: $path)
            .background(Theme.background)
            .imageMaxPixel(600)
            .replaysAnimations()
            // Select mode's action bar, in the tab bar's place (the tab bar hides meanwhile).
            // Only the bar animates in; the tiles switch at once (no per-tile animation).
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if selecting, !store.holdings.isEmpty {
                        bulkBar
                            .padding(.horizontal, 16).padding(.bottom, 8)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: selecting)
            }
            // Room for the tab bar, except while selecting: the action bar takes its place.
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: selecting ? 0 : HoloTabBar<Int>.clearance) }
            .onChange(of: selecting) { _, on in Router.shared.tabBarHidden = on }
            .onDisappear { if selecting { leaveSelecting() }; Router.shared.tabBarHidden = false }
            .refreshable { await reload() }
            .navigationBarTitleDisplayMode(.inline)
            .pageTitle("Collection")
            // The portfolio menu: a frosted panel under the pill, the page dimmed behind; tap
            // anywhere else to close.
            .overlayPreferenceValue(PortfolioPillAnchor.self) { anchor in
                GeometryReader { geo in
                    if portfolioMenu, let anchor {
                        let pill = geo[anchor]
                        ZStack(alignment: .topLeading) {
                            Color.black.opacity(0.35).ignoresSafeArea()
                                .contentShape(Rectangle())
                                .onTapGesture { withAnimation(.snappy(duration: 0.2)) { portfolioMenu = false } }
                            portfolioMenuPanel
                                .offset(x: pill.minX, y: pill.maxY + 8)
                                .transition(.scale(scale: 0.92, anchor: .topLeading).combined(with: .opacity))
                        }
                    }
                }
            }
            .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
            .sheet(item: $opened) { h in
                HoldingSheet(identity: h.identity) {
                    // After the sheet slides away, so the push animates.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { path.append(h.identity.productId) }
                }
            }
            .sheet(item: $selling) { h in SellSheet(holding: h) }
            .sheet(item: $whatIf) { h in SellCalculatorSheet(holding: h) }
            .sheet(item: $removing) { h in RemoveSheet(holding: h) }
            .sheet(item: $editingDetails) { h in EditDetailsSheet(holding: h) }
            .alert("Delete this from your collection?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                presenting: deleting) { h in
                Button("Cancel", role: .cancel) {}
                Button("Delete from collection", role: .destructive) {
                    Task { await groupRun { try await store.deleteCopy(h.identity) } }
                }
            } message: { _ in
                Text("It's removed as if you never added it: it leaves your value, cost and gains. To count it as a loss instead, use Remove.")
            }
            .alert(bulkDeleteTitle, isPresented: $confirmingBulkDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { bulkDelete() }
            } message: {
                Text("Their purchase and sale records are removed.")
            }
            .fullScreenCover(isPresented: $adding) { SearchScreen(mode: .add) }
            .onAppear {
                applyRequest()
                // Screenshots: -HoloOpenHolding opens your most valuable copy's sheet.
                if Demo.isOn, ProcessInfo.processInfo.arguments.contains("-HoloOpenHolding"), opened == nil, !Self.openedOnce {
                    Self.openedOnce = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { opened = store.holdings.first }
                }
            }
            .onChange(of: router.collectionCategory) { _, _ in applyRequest() }
        }
    }

    /// How many holdings each category chip and shelf chip covers (counted once per change).
    private var chipCounts: ChipCounts {
        let holdings = store.holdings
        let shelves = groups.shelves
        return countsMemo(CountsKey(holdings: holdings, shelves: shelves)) {
            var counts = ChipCounts()
            for h in holdings { counts.categories[h.category, default: 0] += 1 }
            for shelf in shelves {
                let ids = Set(shelf.product_ids)
                counts.shelves[shelf.id] = holdings.reduce(0) { $0 + (ids.contains($1.identity.productId) ? 1 : 0) }
            }
            return counts
        }
    }

    /// Category and shelf chips for the track above the grid.
    private var categoryChips: some View {
        let counts = chipCounts
        return HStack(spacing: 2) {
            Chip(title: "All", selected: category == nil && shelfId == nil && !pullsOnly, count: store.holdings.count) { reshuffle { category = nil; shelfId = nil; pullsOnly = false } }
            // The cards you pulled from packs.
            let pulledCount = store.pulledHoldings.count
            if pulledCount > 0 {
                Chip(title: "Pulls", selected: pullsOnly, count: pulledCount) { reshuffle { pullsOnly = true; category = nil; shelfId = nil } }
            }
            ForEach(HoldingCategory.allCases) { c in
                let n = counts.categories[c] ?? 0
                if n > 0 { Chip(title: c.rawValue, selected: category == c && shelfId == nil && !pullsOnly, count: n) { reshuffle { category = c; shelfId = nil; pullsOnly = false } } }
            }
            // Your shelves (shared with the website); hold one to rename or delete it.
            ForEach(groups.shelves) { shelf in
                let n = counts.shelves[shelf.id] ?? 0
                Chip(title: shelf.name, selected: shelfId == shelf.id && !pullsOnly, count: n) { reshuffle { shelfId = shelf.id; category = nil; pullsOnly = false } }
                    .contextMenu {
                        Button { name = shelf.name; naming = .renameShelf(shelf.id) } label: { Label("Rename list", systemImage: "pencil") }
                        Button("Delete list", role: .destructive) {
                            if shelfId == shelf.id { reshuffle { shelfId = nil } }
                            Task { await groupRun { try await groups.removeShelf(shelf.id) } }
                        }
                    }
            }
            Button { shelfProduct = nil; naming = .shelf } label: {
                Label("List", systemImage: "plus").font(.geist(14, .semibold)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 14).frame(height: 36)
            }
            .buttonStyle(.plain)
        }
    }

    /// All portfolios, Main, or one of yours: filters every number, like the website's switcher.
    private var portfolioSwitcher: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { portfolioMenu.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder").font(.system(size: 13, weight: .semibold))
                Text(groups.name(of: groups.selected)).font(.geist(14, .semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(portfolioMenu ? 180 : 0))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).frame(height: 36)
            .frostedPill()
        }
        .buttonStyle(.plain)
        .anchorPreference(key: PortfolioPillAnchor.self, value: .bounds) { $0 }
        .accessibilityLabel("Portfolio: \(groups.name(of: groups.selected))")
        .sheet(isPresented: $managing) {
            ManageGroupsSheet(onClearShelf: { id in if shelfId == id { shelfId = nil } })
        }
        .alert(namingTitle, isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) { name = ""; shelfProduct = nil }
            Button("Save") { saveName() }
        }
    }

    /// The portfolio menu's rows: which portfolio to show, then new, manage, and (for one of
    /// yours) rename and delete. Full labels, never cut short; frosted behind.
    private var portfolioMenuPanel: some View {
        let options: [(String, String)] = [(GroupsStore.all, "All portfolios"), (GroupsStore.main, "Main")] + groups.portfolios.map { ($0.id, $0.name) }
        let own = groups.portfolios.contains(where: { $0.id == groups.selected })
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(options, id: \.0) { id, title in
                menuRow(title, icon: groups.selected == id ? "checkmark" : nil, tint: .white) {
                    groups.select(id, store: store)
                }
            }
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1).padding(.vertical, 6).padding(.horizontal, 16)
            menuRow("New portfolio", icon: "plus", tint: .white) { naming = .portfolio }
            menuRow("Lists and portfolios", icon: "slider.horizontal.3", tint: .white) { managing = true }
            if own {
                let id = groups.selected
                menuRow("Rename portfolio", icon: "pencil", tint: .white) { name = groups.name(of: id); naming = .renamePortfolio(id) }
                menuRow("Delete portfolio", icon: "trash", tint: Theme.down) {
                    Task { await groupRun { try await groups.removePortfolio(id, store: store) } }
                }
            }
        }
        .padding(.vertical, 8)
        .fixedSize()
        .background {
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
            ZStack {
                shape.fill(.regularMaterial)
                shape.fill(Color.black.opacity(0.35))
                shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        }
        .environment(\.colorScheme, .dark)
    }

    private func menuRow(_ title: String, icon: String?, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { portfolioMenu = false }
            action()
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let icon { Image(systemName: icon).font(.system(size: 14, weight: .semibold)) } else { Color.clear }
                }
                .frame(width: 18)
                .foregroundStyle(tint == .white ? Theme.lime : tint)
                Text(title).font(.geist(16, .medium)).foregroundStyle(tint)
                    .lineLimit(1).fixedSize()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(minWidth: 240, minHeight: 46, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var namingTitle: String {
        switch naming {
        case .shelf: "New list"
        case .portfolio: "New portfolio"
        case .renamePortfolio: "Rename portfolio"
        case .renameShelf: "Rename list"
        case nil: ""
        }
    }

    private func saveName() {
        let value = String(name.trimmingCharacters(in: .whitespaces).prefix(40))
        let what = naming
        let product = shelfProduct
        name = ""
        naming = nil
        shelfProduct = nil
        guard !value.isEmpty, let what else { return }
        Task {
            await groupRun {
                switch what {
                case .shelf:
                    let shelf = try await groups.createShelf(value, productIds: product.map { [$0] } ?? [])
                    // A shelf made from a tile's menu stays in the background; a new empty one opens.
                    if product == nil { shelfId = shelf.id }
                case .portfolio: try await groups.createPortfolio(value, store: store)
                case let .renamePortfolio(id): try await groups.renamePortfolio(id, to: value)
                case let .renameShelf(id): try await groups.renameShelf(id, to: value)
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

    /// Category and shelf switches reshuffle the grid with a short spring.
    private func reshuffle(_ change: () -> Void) {
        if reduceMotion { change() } else { withAnimation(.spring(response: 0.3, dampingFraction: 0.85), change) }
    }

    /// A tile's long-press menu: sell, what if, put it on a shelf, open the card page, and the
    /// Owned sheet's ⋯ actions (edit details, remove, delete).
    @ViewBuilder
    private func quickActions(_ h: HoldingView) -> some View {
        let productId = h.identity.productId
        Button { selling = h } label: { Label("Sell", systemImage: "dollarsign.circle") }
        Button { whatIf = h } label: { Label("What if I sell?", systemImage: "questionmark.circle") }
        Menu {
            ForEach(groups.shelves) { shelf in
                Button {
                    Task { await groupRun { try await groups.toggle(shelf.id, productId: productId) } }
                } label: {
                    if shelf.product_ids.contains(productId) { Label(shelf.name, systemImage: "checkmark") } else { Text(shelf.name) }
                }
            }
            Button { shelfProduct = productId; naming = .shelf } label: { Label("New list…", systemImage: "plus") }
        } label: {
            Label("Add to list", systemImage: "square.stack")
        }
        Button { path.append(productId) } label: { Label("Open card", systemImage: "arrow.up.right") }
        Divider()
        Button { editingDetails = h } label: {
            Label { Text("Edit details"); Text("Condition, grade or printing") } icon: { Image(systemName: "pencil") }
        }
        Button { removing = h } label: {
            Label { Text("Remove"); Text("Opened, lost or gave away") } icon: { Image(systemName: "minus.circle") }
        }
        Button(role: .destructive) { deleting = h } label: {
            Label { Text("Delete"); Text("As if you never added it") } icon: { Image(systemName: "trash") }
        }
    }

    // MARK: Select mode

    /// A grid tile: tap opens Your copy, or toggles it in select mode. Hold for quick actions
    /// (not while selecting).
    @ViewBuilder
    private func gridItem(_ h: HoldingView) -> some View {
        let key = h.identity.key
        let button = Button { tap(h) } label: {
            SelectableTile(holding: h, selecting: selecting, selected: selecting && picked.contains(key))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("holding-tile")
        .accessibilityAddTraits(selecting && picked.contains(key) ? .isSelected : [])
        if selecting {
            button
        } else {
            // Hold to lift the tile and get quick actions.
            button.contextMenu { quickActions(h) } preview: { LiftedPreview { HoldingTile(holding: h).frame(width: 190) } }
        }
    }

    @ViewBuilder
    private func listItem(_ h: HoldingView) -> some View {
        let key = h.identity.key
        let button = Button { tap(h) } label: {
            SelectableRow(holding: h, selecting: selecting, selected: selecting && picked.contains(key))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selecting && picked.contains(key) ? .isSelected : [])
        if selecting {
            button
        } else {
            button.contextMenu { quickActions(h) } preview: { LiftedPreview { HoldingListRow(holding: h).frame(width: 340) } }
        }
    }

    private func tap(_ h: HoldingView) {
        guard selecting else { opened = h; return }
        let key = h.identity.key
        if picked.contains(key) { picked.remove(key) } else { picked.insert(key) }
    }

    /// "Select" starts select mode with nothing picked; "Done" leaves it.
    private var selectPill: some View {
        Button {
            if selecting {
                leaveSelecting()
            } else {
                // Nothing picked to start: tap cards, or Select all.
                picked = []
                selecting = true
            }
        } label: {
            Text(selecting ? "Done" : "Select")
                .font(.geist(14, .semibold))
                .foregroundStyle(selecting ? Theme.ink : .white)
                .padding(.horizontal, 16).frame(height: 36)
                .background { if selecting { Capsule().fill(Theme.lime) } }
                .frostedPill(on: !selecting)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("collection-select")
    }

    private func leaveSelecting() {
        selecting = false
        picked = []
    }

    /// The picked holdings that are shown (changing a filter while selecting leaves hidden ones out).
    private var pickedShown: [HoldingView] {
        shown.filter { picked.contains($0.identity.key) }
    }

    private var bulkDeleteTitle: String {
        let n = pickedShown.count
        return "Delete \(n) item\(n == 1 ? "" : "s")?"
    }

    /// The glass bar along the bottom in select mode: the count, Select all or none, and
    /// Move, Copy, Shelf and Delete.
    private var bulkBar: some View {
        let chosen = pickedShown
        let n = chosen.count
        let all = n == shown.count && n > 0
        let noPortfolios = groups.portfolios.isEmpty
        let disabled = n == 0 || bulkBusy
        return VStack(spacing: 14) {
            HStack {
                Text("\(n) selected").font(.geist(15, .semibold)).monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                // A roomy pill, set well apart from the actions below (Delete sits under it).
                Button {
                    picked = all ? [] : Set(shown.map(\.identity.key))
                } label: {
                    Text(all ? "Select none" : "Select all")
                        .font(.geist(14, .semibold)).foregroundStyle(Theme.lime)
                        .padding(.horizontal, 16).frame(height: 38)
                        .overlay(Capsule().strokeBorder(Theme.lime.opacity(0.4), lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            HStack(spacing: 0) {
                portfolioMenu("Move", icon: "folder", header: "Move to portfolio", keys: chosen.map(\.identity.key), copy: false)
                    .disabled(disabled || noPortfolios)
                portfolioMenu("Copy", icon: "plus.square.on.square", header: "Copy to portfolio", keys: chosen.map(\.identity.key), copy: true)
                    .disabled(disabled || noPortfolios)
                shelfMenu(productIds: chosen.map(\.identity.productId))
                    .disabled(disabled || groups.shelves.isEmpty)
                Button { confirmingBulkDelete = true } label: { barAction("Delete", "trash") }
                    .disabled(disabled)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// Move or Copy: Main and each of your portfolios.
    private func portfolioMenu(_ title: String, icon: String, header: String, keys: [String], copy: Bool) -> some View {
        let targets = [GroupsStore.main] + groups.portfolios.map(\.id)
        return Menu {
            Section(header) {
                ForEach(targets, id: \.self) { id in
                    Button(groups.name(of: id)) {
                        bulk {
                            if copy {
                                try await groups.copyMany(keys, to: id, store: store)
                            } else {
                                try await groups.moveMany(keys, to: id, store: store)
                            }
                        }
                    }
                }
            }
        } label: {
            barAction(title, icon)
        }
    }

    private func shelfMenu(productIds: [String]) -> some View {
        Menu {
            Section("Add to list") {
                ForEach(groups.shelves) { shelf in
                    Button(shelf.name) { bulk { try await groups.addMany(shelf.id, productIds: productIds) } }
                }
            }
        } label: {
            barAction("List", "square.stack")
        }
    }

    private func barAction(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 18, weight: .medium)).frame(height: 22)
            Text(title).font(.geist(11, .medium))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    /// Runs a bulk change; a failure shows above the collection, as other group changes do.
    private func bulk(_ work: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            bulkBusy = true
            defer { bulkBusy = false }
            await groupRun { try await work() }
        }
    }

    private func bulkDelete() {
        let identities = pickedShown.map(\.identity)
        Task { @MainActor in
            bulkBusy = true
            defer { bulkBusy = false }
            await groupRun { try await store.deleteCopies(identities) }
            leaveSelecting()
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
                    .font(.display(56)).tracking(-2.2).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
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
                HoloSearchField(text: $query, prompt: "Search", focus: $searchFocused, scan: .collection)
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
            // The track stays inside the screen edges. When the chips don't all fit they scroll
            // inside it and the right edge fades out.
            ViewThatFits(in: .horizontal) {
                categoryChips.padding(4)
                ScrollView(.horizontal, showsIndicators: false) { categoryChips.padding(4) }
                    .fadeTrailingEdge()
            }
            .clipShape(Capsule())
            .liquidGlass(in: Capsule())
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

    /// The sets and product types you hold, for the filter menu (worked out once per change).
    private var filterOptions: FilterOptions {
        let holdings = store.holdings
        return optionsMemo(holdings) {
            let sets = Array(Set(holdings.compactMap { $0.product?.setName })).sorted()
            let present = Set(holdings.compactMap { $0.product.map(Analytics.category) })
            let types = ["Card", "Booster Box", "Elite Trainer Box", "Ultra Premium Collection", "Booster Bundle", "Collection Box", "Tin", "Booster Pack", "Other Sealed"]
                .filter { present.contains($0) }
            return FilterOptions(sets: sets, types: types)
        }
    }

    /// Filter by set, product type and profit or loss, like the website's filter panel.
    private var filterMenu: some View {
        let options = filterOptions
        let sets = options.sets
        let types = options.types
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
        EmptyPage(title: "Nothing here yet", line: "Scan a card, or search for anything you own.", action: "Scan a card",
                  onAction: onScan, link: "Search instead", onLink: { adding = true })
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
                        .font(.display(22)).tracking(-0.6).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
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

/// The check in select mode: a lime circle with a dark check, or a faint outline.
struct SelectCheck: View {
    var selected: Bool

    var body: some View {
        ZStack {
            if selected {
                Circle().fill(Theme.lime)
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.ink)
            } else {
                Circle().fill(Color.black.opacity(0.3))
                Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5)
            }
        }
        .frame(width: 26, height: 26)
    }
}

/// A grid tile with its select-mode check. Its own view, so toggling one tile redraws only it.
private struct SelectableTile: View {
    var holding: HoldingView
    var selecting: Bool
    var selected: Bool

    var body: some View {
        HoldingTile(holding: holding)
            .opacity(selecting && !selected ? 0.5 : 1)
            .overlay(alignment: .topTrailing) {
                if selecting { SelectCheck(selected: selected).padding(10) }
            }
    }
}

/// A list row with its select-mode check.
private struct SelectableRow: View {
    var holding: HoldingView
    var selecting: Bool
    var selected: Bool

    var body: some View {
        HStack(spacing: 0) {
            if selecting { SelectCheck(selected: selected).padding(.leading, 14) }
            HoldingListRow(holding: holding)
        }
        .opacity(selecting && !selected ? 0.5 : 1)
    }
}

/// A long-pressed tile, lifted toward you with a slight 3D lean, as the context menu's preview.
private struct LiftedPreview<Content: View>: View {
    var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lifted = false

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(14)
            .scaleEffect(lifted ? 1.04 : 1)
            .rotation3DEffect(.degrees(lifted ? 6 : 0), axis: (x: 1, y: -0.6, z: 0), perspective: 0.5)
            .padding(10)
            .background(Theme.background)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { lifted = true }
            }
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
                DeltaPill(ratio: holding.gainRatio, size: 11)
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

/// The chosen kind (Sealed, Singles, Graded) as a card in its color, like Overview's: its name and
/// share of your value on a slanted tag, what it's worth, and its gain on what you paid.
private struct CategoryBanner: View, Equatable {
    var category: HoldingCategory
    var holdings: [HoldingView]
    var total: Double

    /// Worked out again only when the kind, the collection's total or its size changes (not on
    /// every keystroke in search or tap of a chip).
    static func == (a: Self, b: Self) -> Bool {
        a.category == b.category && a.total == b.total && a.holdings.count == b.holdings.count
    }

    var body: some View {
        let items = holdings.filter { $0.category == category }
        let value = items.reduce(0) { $0 + ($1.value ?? 0) }
        let cost = items.filter { $0.value != nil }.reduce(0) { $0 + $1.costBasis }
        let share = total > 0 ? Int((value / total * 100).rounded()) : 0
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(category.rawValue).font(.display(26)).tracking(-0.7).displayTrim(26)
                category.tag("\(share)% of value")
            }
            Text(Format.money(value)).font(.display(36)).tracking(-1.4).monospacedDigit().displayTrim(36)
            HStack(spacing: 4) {
                Text(Format.signedMoney(value - cost)).foregroundStyle(Theme.tone(value - cost)).fontWeight(.semibold)
                Text("on what you paid").foregroundStyle(Theme.muted)
            }
            .font(.geist(14)).monospacedDigit()
        }
        .foregroundStyle(.white)
        .tinted(category.color)
        .transition(.opacity)
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

/// Remembers a value worked out from some inputs and hands it back while the inputs are the
/// same. Kept in @State (one per view) and not observed, so filling it never causes a redraw.
private final class CollectionMemo<Key: Equatable, Value> {
    private var key: Key?
    private var value: Value?

    func callAsFunction(_ key: Key, _ make: () -> Value) -> Value {
        if let value, self.key == key { return value }
        let made = make()
        self.key = key
        value = made
        return made
    }
}

/// Every shelf and portfolio in one list: tap to rename, swipe or use Delete to remove.
/// Shared with the website (the shelves and portfolios tables).
struct ManageGroupsSheet: View {
    var onClearShelf: (String) -> Void
    @Environment(GroupsStore.self) private var groups
    @Environment(CollectionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: (kind: Kind, id: String)?
    @State private var name = ""
    @State private var deleting: (kind: Kind, id: String, name: String)?
    @State private var creating: Kind?
    @State private var newName = ""
    @State private var error: String?

    enum Kind { case shelf, portfolio }

    var body: some View {
        NavigationStack {
            GlassList {
                Section {
                    if groups.shelves.isEmpty { Text("No shelves yet.").foregroundStyle(Theme.muted) }
                    ForEach(groups.shelves) { shelf in
                        row(shelf.name, sub: "\(shelf.product_ids.count) item\(shelf.product_ids.count == 1 ? "" : "s")", kind: .shelf, id: shelf.id)
                    }
                    newRow("New list", kind: .shelf)
                } header: { sectionTitle("Lists") } footer: { sectionNote("Your own lists, like Grails or For sale at the show. Deleting a list keeps its cards in your collection.") }
                Section {
                    if groups.portfolios.isEmpty { Text("No portfolios yet.").foregroundStyle(Theme.muted) }
                    ForEach(groups.portfolios) { p in
                        row(p.name, sub: nil, kind: .portfolio, id: p.id)
                    }
                    newRow("New portfolio", kind: .portfolio)
                } header: { sectionTitle("Portfolios") } footer: { sectionNote("Separate collections with their own totals. Deleting one moves its cards back to Main.") }
                if let error { Section { Text(error).foregroundStyle(Theme.down) } }
            }
            .navigationTitle("Lists and portfolios")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert(renaming?.kind == .shelf ? "Rename list" : "Rename portfolio", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $name)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Save") { saveRename() }
            }
            .alert(creating == .shelf ? "New list" : "New portfolio", isPresented: Binding(get: { creating != nil }, set: { if !$0 { creating = nil } })) {
                TextField(creating == .shelf ? "Grails, For sale…" : "Resale, PC, Graded…", text: $newName)
                Button("Cancel", role: .cancel) { creating = nil; newName = "" }
                Button("Create") { saveNew() }
            }
            .alert("Delete \(deleting?.name ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Cancel", role: .cancel) { deleting = nil }
                Button("Delete", role: .destructive) { confirmDelete() }
            } message: {
                Text(deleting?.kind == .shelf ? "The list goes; its cards stay in your collection." : "The portfolio goes; its cards move back to Main.")
            }
        }
        .presentationDetents([.medium, .fraction(0.93)])
        .glassSheet()
    }

    /// A section's heading: white, in the heading font, clearly above the rows and the note.
    private func sectionTitle(_ text: String) -> some View { SectionTitle(text) }

    /// The quiet note under a section's rows.
    private func sectionNote(_ text: String) -> some View { SectionNote(text) }

    private func row(_ title: String, sub: String?, kind: Kind, id: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.white)
                if let sub { Text(sub).font(.geist(12)).foregroundStyle(Theme.muted) }
            }
            Spacer()
            Button { name = title; renaming = (kind, id) } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless).foregroundStyle(Theme.muted).accessibilityLabel("Rename \(title)")
            Button { deleting = (kind, id, title) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).foregroundStyle(Theme.down).accessibilityLabel("Delete \(title)")
                .padding(.leading, 12)
        }
    }

    /// A lime row at the end of a section that starts a new shelf or portfolio.
    private func newRow(_ title: String, kind: Kind) -> some View {
        Button { newName = ""; creating = kind } label: { Label(title, systemImage: "plus") }
            .foregroundStyle(Theme.lime)
    }

    private func saveNew() {
        let value = String(newName.trimmingCharacters(in: .whitespaces).prefix(40))
        guard let kind = creating, !value.isEmpty else { creating = nil; return }
        creating = nil
        newName = ""
        Task { await run {
            switch kind {
            case .shelf: _ = try await groups.createShelf(value)
            case .portfolio: try await groups.createPortfolio(value, store: store)
            }
        } }
    }

    private func saveRename() {
        let value = String(name.trimmingCharacters(in: .whitespaces).prefix(40))
        guard let r = renaming, !value.isEmpty else { renaming = nil; return }
        renaming = nil
        Task { await run {
            switch r.kind {
            case .shelf: try await groups.renameShelf(r.id, to: value)
            case .portfolio: try await groups.renamePortfolio(r.id, to: value)
            }
        } }
    }

    private func confirmDelete() {
        guard let d = deleting else { return }
        deleting = nil
        Task { await run {
            switch d.kind {
            case .shelf:
                onClearShelf(d.id)
                try await groups.removeShelf(d.id)
            case .portfolio: try await groups.removePortfolio(d.id, store: store)
            }
        } }
    }

    @MainActor private func run(_ work: () async throws -> Void) async {
        do { error = nil; try await work() } catch { self.error = error.localizedDescription }
    }
}

/// Where the portfolio pill sits, so its menu can open right under it.
private struct PortfolioPillAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

private extension View {
    /// A frosted pill: a material blur of what's behind, a dark wash, a soft light from the top
    /// and a fine edge.
    @ViewBuilder func frostedPill(on: Bool = true) -> some View {
        if on {
            background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(Color(hex: 0x18181B).opacity(0.45))
                    Capsule().fill(LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
                .environment(\.colorScheme, .dark)
            }
        } else {
            self
        }
    }
}
