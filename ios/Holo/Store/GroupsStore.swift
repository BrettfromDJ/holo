import Foundation
import Observation
import Supabase

/// Shelves (named groups of products, like "Grails") and portfolios (named groups of holdings
/// that filter every number), in the same `shelves` and `portfolios` tables the website uses.
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
    /// "all", "main" (holdings in no portfolio) or a portfolio id.
    private(set) var selected = GroupsStore.all
    var error: String?
    private var userId: String?
    private var loadedFor: String?

    private var db: SupabaseClient { Backend.shared.supabase }
    private static let selectedKey = "holo.portfolio.selected"

    func reset() {
        shelves = []
        portfolios = []
        selected = Self.all
        userId = nil
        loadedFor = nil
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
            selected = UserDefaults.standard.string(forKey: Self.selectedKey) ?? Self.all
        } else {
            shelves = [
                Shelf(id: "demo-grails", name: "Grails", product_ids: ["sample:umbreon-vmax-alt", "sample:charizard-base", "sample:es-bb"]),
                Shelf(id: "demo-xmas", name: "Opening at Christmas", product_ids: ["sample:pe-etb", "sample:151-bundle"]),
            ]
            portfolios = []
            selected = Self.all
        }
        apply(store)
    }

    private var cloud: Bool { userId != nil && !Demo.isOn }

    // MARK: Portfolios

    /// The portfolio a holding belongs to ("main" when none).
    func portfolioOf(_ holdingKey: String) -> String {
        portfolios.first { $0.holding_keys.contains(holdingKey) }?.id ?? Self.main
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
        if effective == Self.all {
            store.holdingFilter = nil
        } else {
            var owner: [String: String] = [:]
            for p in portfolios { for k in p.holding_keys { owner[k] = p.id } }
            store.holdingFilter = { (owner[$0] ?? Self.main) == effective }
        }
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
        struct Patch: Encodable { var holding_keys: [String] }
        for i in portfolios.indices {
            let has = portfolios[i].holding_keys.contains(holdingKey)
            let should = portfolios[i].id == target
            guard has != should else { continue }
            var keys = portfolios[i].holding_keys.filter { $0 != holdingKey }
            if should { keys.append(holdingKey) }
            if cloud { try await db.from("portfolios").update(Patch(holding_keys: keys)).eq("id", value: portfolios[i].id).execute() }
            portfolios[i].holding_keys = keys
        }
        apply(store)
    }

    // MARK: Shelves

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
