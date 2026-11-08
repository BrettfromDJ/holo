import Foundation
import Observation
import Supabase

/// Shelves (named groups of products, like "Grails") and portfolios (named groups of holdings
/// that filter every number), in the same `shelves` and `portfolios` tables the website uses.
/// A holding can be in several portfolios; Main is every holding in none of them, plus the ones
/// kept in Main too (user_state `portfolio-main`). The rules are in `PortfolioMembership`.
/// A demo keeps them on the phone.
@Observable
final class GroupsStore {
    struct Shelf: Codable, Identifiable, Hashable {
        var id: String
        var name: String
        var product_ids: [String]
    }

    struct PortfolioGroup: Codable, Identifiable, Hashable {
        var id: String
        var name: String
        var holding_keys: [String]
    }

    static let main = "main"
    static let all = "all"

    /// Lists (the `shelves` table; the app called them shelves before).
    var shelves: [Shelf] = []
    /// Each list's extras (for sale, asking prices), user_state `list-meta`.
    private(set) var listMeta: [String: ListMeta] = [:]
    /// Cards on lists that aren't in your collection: their catalog rows and market prices.
    private(set) var extraProducts: [String: Product] = [:]
    private(set) var extraMarket: [String: Double] = [:]
    /// Share links already looked up this session, by list id (nil: not shared).
    private(set) var shareURLs: [String: URL?] = [:]
    var portfolios: [PortfolioGroup] = []
    /// Holdings kept in Main as well as in a named portfolio (user_state `portfolio-main`).
    private(set) var mainKeys: [String] = []
    /// The account's `portfolio-main` was read this session (a failed read is never saved over).
    @ObservationIgnored private var mainSynced = false
    /// "all", "main" (holdings in Main) or a portfolio id.
    private(set) var selected = GroupsStore.all
    var error: String?
    private var userId: String?
    private var loadedFor: String?
    /// The filter last handed to the collection. Setting it again rebuilds every holding and
    /// the value history, so an unchanged filter isn't set again.
    @ObservationIgnored private var applied: Applied?

    private struct Applied: Equatable {
        var store: ObjectIdentifier
        var selection: String
        var portfolios: [PortfolioGroup]
        var mainKeys: [String]
    }

    private var db: SupabaseClient { Backend.shared.supabase }
    private static let selectedKey = "holo.portfolio.selected"

    func reset() {
        shelves = []
        listMeta = [:]
        shareURLs = [:]
        extraProducts = [:]
        extraMarket = [:]
        portfolios = []
        mainKeys = []
        mainSynced = false
        selected = Self.all
        userId = nil
        loadedFor = nil
        applied = nil
    }

    /// Load for an account (nil for a demo, which starts with two example shelves).
    @MainActor
    func load(userId: String?, store: CollectionStore) async {
        let key = userId ?? "demo"
        guard loadedFor != key else { return }
        loadedFor = key
        self.userId = userId
        if userId != nil, !Demo.isOn {
            do {
                shelves = try await db.from("shelves").select("id,name,product_ids").order("created_at").execute().value
                portfolios = try await db.from("portfolios").select("id,name,holding_keys").order("created_at").execute().value
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
            listMeta = (try? await UserState.load(ListPricing.metaKey, as: [String: ListMeta].self)) ?? [:]
            mainSynced = false
            do {
                mainKeys = try await UserState.load("portfolio-main", as: [String].self) ?? []
                mainSynced = true
            } catch {
                mainKeys = []
            }
            selected = UserDefaults.standard.string(forKey: Self.selectedKey) ?? Self.all
        } else {
            // Made-up lists only for the screenshot runs (-HoloDemo); a demo picked in the app starts with none.
            shelves = !Demo.isOn || ProcessInfo.processInfo.arguments.contains("-HoloNoLists") ? [] : [
                Shelf(id: "demo-grails", name: "Grails", product_ids: ["sample:umbreon-vmax-alt", "sample:charizard-base", "sample:es-bb"]),
                Shelf(id: "demo-show", name: "For sale at the show", product_ids: ["sample:charizard-ex-151", "sample:mew-ex-gold", "sample:giratina-v-alt", "sample:pf-tin"]),
                Shelf(id: "demo-sirs", name: "Favorite SIRs", product_ids: ["sample:pikachu-ex-ss", "sample:charizard-ex-151", "sample:charizard-ex-of", "sample:rayquaza-vmax-alt"]),
                Shelf(id: "demo-empty", name: "Japanese promos", product_ids: []),
            ]
            listMeta = !Demo.isOn ? [:] : ["demo-show": ListMeta(forSale: true, askPercent: 90, prices: ["sample:giratina-v-alt": 300], percents: ["sample:mew-ex-gold": 80])]
            portfolios = []
            mainKeys = []
            selected = Self.all
        }
        apply(store)
    }

    private var cloud: Bool { userId != nil && !Demo.isOn }

    // MARK: Portfolios

    private var membership: PortfolioMembership.State {
        PortfolioMembership.State(portfolios: portfolios.map { PortfolioMembership.Group(id: $0.id, keys: $0.holding_keys) }, main: mainKeys)
    }

    /// Every portfolio a holding shows in, "main" first when it's in Main.
    func portfoliosOf(_ holdingKey: String) -> [String] {
        PortfolioMembership.members(membership, holdingKey)
    }

    /// The first portfolio a holding shows in ("main" when it's in Main).
    func portfolioOf(_ holdingKey: String) -> String {
        portfoliosOf(holdingKey).first ?? Self.main
    }

    func name(of id: String) -> String {
        id == Self.all ? "All portfolios" : id == Self.main ? "Main" : portfolios.first { $0.id == id }?.name ?? "Portfolio"
    }

    @MainActor
    func select(_ id: String, store: CollectionStore) {
        selected = id
        UserDefaults.standard.set(id, forKey: Self.selectedKey)
        apply(store)
    }

    /// Filter the collection's numbers to the selected portfolio.
    @MainActor
    func apply(_ store: CollectionStore) {
        let effective = selected == Self.all || selected == Self.main || portfolios.contains { $0.id == selected } ? selected : Self.all
        // "All" doesn't depend on what's in each portfolio; the others do.
        let all = effective == Self.all
        let stamp = Applied(store: ObjectIdentifier(store), selection: effective, portfolios: all ? [] : portfolios, mainKeys: all ? [] : mainKeys)
        guard stamp != applied else { return }
        applied = stamp
        store.holdingFilter = PortfolioMembership.filter(membership, selected: effective)
    }

    @MainActor
    func createPortfolio(_ name: String, store: CollectionStore) async throws {
        struct New: Encodable { var user_id: String; var name: String; var holding_keys: [String] }
        if cloud, let userId {
            let row: PortfolioGroup = try await db.from("portfolios").insert(New(user_id: userId, name: name, holding_keys: [])).select("id,name,holding_keys").single().execute().value
            portfolios.append(row)
        } else {
            portfolios.append(PortfolioGroup(id: UUID().uuidString.lowercased(), name: name, holding_keys: []))
        }
        select(portfolios.last!.id, store: store)
    }

    @MainActor
    func renamePortfolio(_ id: String, to name: String) async throws {
        struct Patch: Encodable { var name: String }
        if cloud { try await db.from("portfolios").update(Patch(name: name)).eq("id", value: id).execute() }
        if let i = portfolios.firstIndex(where: { $0.id == id }) { portfolios[i].name = name }
    }

    /// Delete a portfolio; its holdings go back to Main.
    @MainActor
    func removePortfolio(_ id: String, store: CollectionStore) async throws {
        if cloud { try await db.from("portfolios").delete().eq("id", value: id).execute() }
        portfolios.removeAll { $0.id == id }
        if selected == id { select(Self.all, store: store) } else { apply(store) }
    }

    /// Move a holding into a portfolio ("main" takes it out of every custom one).
    @MainActor
    func move(_ holdingKey: String, to target: String, store: CollectionStore) async throws {
        try await moveMany([holdingKey], to: target, store: store)
    }

    /// Move holdings: they end up only in `target`.
    @MainActor
    func moveMany(_ keys: [String], to target: String, store: CollectionStore) async throws {
        try await write(PortfolioMembership.move(membership, keys, to: target), store: store)
    }

    /// Copy holdings: they also show in `target`, staying where they are (nothing is duplicated).
    @MainActor
    func copyMany(_ keys: [String], to target: String, store: CollectionStore) async throws {
        try await write(PortfolioMembership.copy(membership, keys, to: target), store: store)
    }

    /// Put a holding in exactly these portfolios (a slab back from grading joins its raw card's).
    @MainActor
    func place(_ holdingKey: String, in ids: [String], store: CollectionStore) async throws {
        try await write(PortfolioMembership.place(membership, [(key: holdingKey, ids: ids)]), store: store)
    }

    @MainActor
    private func write(_ change: PortfolioMembership.Change, store: CollectionStore) async throws {
        struct Patch: Encodable { var holding_keys: [String] }
        defer { apply(store) }
        for id in change.changed {
            guard let keys = change.next.portfolios.first(where: { $0.id == id })?.keys,
                  let i = portfolios.firstIndex(where: { $0.id == id }) else { continue }
            if cloud { try await db.from("portfolios").update(Patch(holding_keys: keys)).eq("id", value: id).execute() }
            portfolios[i].holding_keys = keys
        }
        guard !change.mainAdd.isEmpty || !change.mainRemove.isEmpty else { return }
        guard cloud, let userId else {
            mainKeys = PortfolioMembership.applyMainChange(mainKeys, add: change.mainAdd, remove: change.mainRemove)
            return
        }
        // Merge onto the account's list (the website may have changed it since loading).
        let base: [String]
        do {
            base = try await UserState.load("portfolio-main", as: [String].self) ?? []
        } catch {
            // Never read from the account this session: saving what's on the phone could wipe it.
            guard mainSynced else { throw HoloError.server(code: nil, message: "Couldn't reach your account. Try again.") }
            base = mainKeys
        }
        let next = PortfolioMembership.applyMainChange(base, add: change.mainAdd, remove: change.mainRemove)
        try await UserState.save("portfolio-main", next, userId: userId)
        mainKeys = next
        mainSynced = true
    }

    // MARK: Shelves

    /// Put several products on a shelf (ones already on it stay as they are).
    @MainActor
    func addMany(_ shelfId: String, productIds: [String]) async throws {
        struct Patch: Encodable { var product_ids: [String] }
        guard let i = shelves.firstIndex(where: { $0.id == shelfId }) else { return }
        var ids = shelves[i].product_ids
        for p in productIds where !ids.contains(p) { ids.append(p) }
        guard ids != shelves[i].product_ids else { return }
        if cloud { try await db.from("shelves").update(Patch(product_ids: ids)).eq("id", value: shelfId).execute() }
        shelves[i].product_ids = ids
    }

    @MainActor
    func createShelf(_ name: String, productIds: [String] = []) async throws -> Shelf {
        struct New: Encodable { var user_id: String; var name: String; var product_ids: [String] }
        let shelf: Shelf
        if cloud, let userId {
            shelf = try await db.from("shelves").insert(New(user_id: userId, name: name, product_ids: productIds)).select("id,name,product_ids").single().execute().value
        } else {
            shelf = Shelf(id: UUID().uuidString.lowercased(), name: name, product_ids: productIds)
        }
        shelves.append(shelf)
        return shelf
    }

    @MainActor
    func renameShelf(_ id: String, to name: String) async throws {
        struct Patch: Encodable { var name: String }
        if cloud { try await db.from("shelves").update(Patch(name: name)).eq("id", value: id).execute() }
        if let i = shelves.firstIndex(where: { $0.id == id }) { shelves[i].name = name }
    }

    @MainActor
    func removeShelf(_ id: String) async throws {
        if cloud { try await db.from("shelves").delete().eq("id", value: id).execute() }
        shelves.removeAll { $0.id == id }
    }

    /// Put a product on a shelf, or take it off.
    @MainActor
    func toggle(_ shelfId: String, productId: String) async throws {
        struct Patch: Encodable { var product_ids: [String] }
        guard let i = shelves.firstIndex(where: { $0.id == shelfId }) else { return }
        var ids = shelves[i].product_ids
        if let at = ids.firstIndex(of: productId) { ids.remove(at: at) } else { ids.append(productId) }
        if cloud { try await db.from("shelves").update(Patch(product_ids: ids)).eq("id", value: shelfId).execute() }
        shelves[i].product_ids = ids
    }

    // MARK: List extras and sharing

    func meta(_ listId: String) -> ListMeta { listMeta[listId] ?? ListMeta() }

    /// Change one list's extras, merged onto what the account has (the website may have changed others).
    @MainActor
    func updateMeta(_ listId: String, _ change: (inout ListMeta) -> Void) async throws {
        var local = listMeta
        var entry = local[listId] ?? ListMeta()
        change(&entry)
        guard cloud, let userId else {
            local[listId] = entry
            listMeta = local
            return
        }
        var base = try await UserState.load(ListPricing.metaKey, as: [String: ListMeta].self) ?? [:]
        var merged = base[listId] ?? ListMeta()
        change(&merged)
        base[listId] = merged
        try await UserState.save(ListPricing.metaKey, base, userId: userId)
        listMeta = base
    }

    private struct ShareRow: Codable { var token: String; var revoked_at: String? }

    private static func url(_ token: String) -> URL { AppConfig.apiBaseURL.appendingPathComponent("l").appendingPathComponent(token) }

    /// The list's live share link, if it has one.
    @MainActor
    func loadShare(_ listId: String) async {
        guard cloud else { return }
        let rows: [ShareRow] = (try? await db.from("share_links").select("token,revoked_at").eq("title", value: ListPricing.shareTitle(listId)).execute().value) ?? []
        shareURLs[listId] = .some(rows.first { $0.revoked_at == nil }.map { Self.url($0.token) })
    }

    /// Share a list: a link anyone can open (no sign-in), showing only that list.
    @MainActor
    func share(_ listId: String) async throws -> URL {
        guard cloud, let userId else { throw HoloError.server(code: nil, message: "Sign in to share a list. Nothing is saved in a demo.") }
        await loadShare(listId)
        if let existing = shareURLs[listId] ?? nil { return existing }
        struct New: Encodable { var user_id: String; var token: String; var title: String; var show_gains: Bool }
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
        try await db.from("share_links").insert(New(user_id: userId, token: token, title: ListPricing.shareTitle(listId), show_gains: false)).execute()
        let url = Self.url(token)
        shareURLs[listId] = url
        return url
    }

    /// Turn the link off: anyone who has it sees nothing.
    @MainActor
    func stopSharing(_ listId: String) async throws {
        struct Patch: Encodable { var revoked_at: String }
        if cloud {
            try await db.from("share_links").update(Patch(revoked_at: ISO8601DateFormatter().string(from: Date()))).eq("title", value: ListPricing.shareTitle(listId)).execute()
        }
        shareURLs[listId] = .some(nil)
    }

    /// Take products off a list.
    @MainActor
    func removeMany(_ listId: String, productIds: [String]) async throws {
        struct Patch: Encodable { var product_ids: [String] }
        guard let i = shelves.firstIndex(where: { $0.id == listId }) else { return }
        let ids = shelves[i].product_ids.filter { !productIds.contains($0) }
        if cloud { try await db.from("shelves").update(Patch(product_ids: ids)).eq("id", value: listId).execute() }
        shelves[i].product_ids = ids
    }

    /// Remember a card added from the catalog, so its picture and price show right away.
    func remember(_ product: Product, market: Double?) {
        extraProducts[product.id] = product
        if let market { extraMarket[product.id] = market }
    }

    /// Fetch the catalog rows and prices of list cards you don't own (once each per session).
    @MainActor
    func loadExtras(_ ids: [String], known: [String: Product]) async {
        let missing = Array(Set(ids.filter { known[$0] == nil && extraProducts[$0] == nil }))
        guard !missing.isEmpty, cloud else { return }
        guard let rows: [ProductRow] = try? await db.from("products").select().in("id", values: missing).execute().value else { return }
        let priceRows: [PriceRow] = (try? await db.from("product_prices").select().in("product_id", values: missing).execute().value) ?? []
        for r in rows { extraProducts[r.id] = r.product }
        for r in priceRows {
            if let m = r.price.market { extraMarket[r.product_id] = max(extraMarket[r.product_id] ?? 0, m) }
        }
    }
}
