import SwiftUI

/// Everything you hold, like the website's Collection: value, gain and holdings up top, then
/// search, sort, grid or list, and Sealed / Singles / Graded.
struct CollectionView: View {
    var onScan: () -> Void
    @Environment(CollectionStore.self) private var store
    @Environment(SessionModel.self) private var session
    @State private var adding = false
    @State private var query = ""
    @State private var category: HoldingCategory?
    @State private var sort = Sort.value
    @State private var grid = true
    @State private var router = Router.shared

    enum Sort: String, CaseIterable {
        case value = "Holding value", gain = "Gain", gainPct = "Gain %", day = "Today's move", recent = "Recently added", name = "Name"
    }

    private var shown: [HoldingView] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = store.holdings.filter { h in
            (category == nil || h.category == category) &&
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
                        header
                        if store.holdings.isEmpty {
                            empty
                        } else {
                            controls
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
            .refreshable { await reload() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { BrandMark() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
            .sheet(isPresented: $adding) { SearchView(asSheet: true) }
            .onAppear { applyRequest() }
            .onChange(of: router.collectionCategory) { _, _ in applyRequest() }
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
        return VStack(alignment: .leading, spacing: 14) {
            PageHeader(title: "Collection") {
                Button { adding = true } label: { Label("Add", systemImage: "plus") }
                    .buttonStyle(Button3D(kind: .dark, fullWidth: false, height: 40))
            }
            VStack(alignment: .leading, spacing: 4) {
                MonoLabel(text: "Value")
                Text(Format.money(s.value)).font(.display(56)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            }
            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 4) {
                    MonoLabel(text: "Gain")
                    HStack(spacing: 6) {
                        Text(Format.signedMoney(s.gain)).font(.geist(18, .semibold)).foregroundStyle(Theme.tone(s.gain))
                        Text(Format.signedPercent(s.gainRatio)).font(.geist(15, .medium)).foregroundStyle(Theme.tone(s.gain))
                    }
                    .monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 4) {
                    MonoLabel(text: "Holdings")
                    Text("\(store.holdings.count)").font(.geist(18, .semibold)).monospacedDigit()
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("Search", text: $query).font(.geist(16)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Capsule().fill(Theme.surface2))
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .menuStyle(.button)
                .buttonStyle(IconButton3D(size: 46))
                HStack(spacing: 2) {
                    Button { grid = true } label: { Image(systemName: "square.grid.2x2") }.buttonStyle(IconButton3D(size: 40, active: grid))
                    Button { grid = false } label: { Image(systemName: "list.bullet") }.buttonStyle(IconButton3D(size: 40, active: !grid))
                }
                .padding(3)
                .background(Capsule().fill(Theme.surface))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Chip(title: "All", selected: category == nil, count: store.holdings.count) { category = nil }
                    ForEach(HoldingCategory.allCases) { c in
                        let n = store.holdings.filter { $0.category == c }.count
                        if n > 0 { Chip(title: c.rawValue, selected: category == c, count: n) { category = c } }
                    }
                }
                .padding(.vertical, 4)
            }
            if sort != .value {
                Text("Sorted by \(sort.rawValue.lowercased())").font(.geist(13)).foregroundStyle(Theme.muted)
            }
        }
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
            ZStack(alignment: .topLeading) {
                HoldingArt(product: holding.product, identity: holding.identity, cornerRadius: holding.product?.imageURL == nil ? 22 : 12)
                    .frame(maxWidth: .infinity)
                .aspectRatio(0.72, contentMode: .fit)
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
