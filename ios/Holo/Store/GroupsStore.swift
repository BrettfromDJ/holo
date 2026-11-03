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

    var shelves: [Shelf] = []
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
            mainSynced = false
            do {
                mainKeys = try await UserState.load("portfolio-main", as: [String].self) ?? []
                mainSynced = true
            } catch {
                mainKeys = []
            }
            selected = UserDefaults.standard.string(forKey: Self.selectedKey) ?? Self.all
        } else {
            shelves = [
                Shelf(id: "demo-grails", name: "Grails", product_ids: ["sample:umbreon-vmax-alt", "sample:charizard-base", "sample:es-bb"]),
                Shelf(id: "demo-xmas", name: "Opening at Christmas", product_ids: ["sample:pe-etb", "sample:151-bundle"]),
            ]
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
}
