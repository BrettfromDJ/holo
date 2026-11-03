import Foundation

/// Which portfolios a holding is in, and what Move and Copy write. Port of the website's
/// `src/lib/portfolios.ts`; keep both in step (PortfolioMembershipTests uses the same cases).
///
/// A holding may be listed in several portfolios' `holding_keys`. "Main" is every holding in no
/// named portfolio, plus the ones kept in Main too: their keys are in user_state
/// `portfolio-main`. Copying never duplicates a holding; it only shows in more places, and
/// "All portfolios" counts each holding once.
enum PortfolioMembership {
    static let main = "main"
    static let all = "all"

    struct Group: Equatable {
        var id: String
        var keys: [String]
    }

    struct State: Equatable {
        /// Named portfolios and the keys listed in each.
        var portfolios: [Group]
        /// user_state `portfolio-main`: keys kept in Main as well as in a named portfolio.
        var main: [String]
    }

    /// What a change writes: the named portfolios whose keys changed, and keys to add to or
    /// drop from `portfolio-main`.
    struct Change: Equatable {
        var next: State
        var changed: [String]
        var mainAdd: [String]
        var mainRemove: [String]
    }

    /// The portfolios a holding shows in, "main" first when it's in Main.
    static func members(_ s: State, _ key: String) -> [String] {
        let named = s.portfolios.filter { $0.keys.contains(key) }.map(\.id)
        let inMain = named.isEmpty || s.main.contains(key)
        return inMain ? [main] + named : named
    }

    /// Whether a holding shows in a portfolio ("all" holds everything).
    static func isIn(_ s: State, _ key: String, _ portfolioId: String) -> Bool {
        if portfolioId == all { return true }
        if portfolioId == main { return s.main.contains(key) || !s.portfolios.contains { $0.keys.contains(key) } }
        return s.portfolios.contains { $0.id == portfolioId && $0.keys.contains(key) }
    }

    /// A filter for the selected portfolio, by holding key; nil shows everything.
    static func filter(_ s: State, selected: String) -> ((String) -> Bool)? {
        if selected == all { return nil }
        if selected == main {
            let named = Set(s.portfolios.flatMap(\.keys))
            let kept = Set(s.main)
            return { kept.contains($0) || !named.contains($0) }
        }
        let keys = Set(s.portfolios.first { $0.id == selected }?.keys ?? [])
        return { keys.contains($0) }
    }

    /// Puts each holding in exactly these portfolios. A key is listed in `portfolio-main` only
    /// when it's in Main and in a named portfolio too (in no named one, it's in Main anyway).
    static func place(_ s: State, _ targets: [(key: String, ids: [String])]) -> Change {
        var changed: [String] = []
        let portfolios = s.portfolios.map { p -> Group in
            var keys = p.keys
            for t in targets {
                let has = keys.contains(t.key)
                let should = t.ids.contains(p.id)
                guard has != should else { continue }
                if should { keys.append(t.key) } else { keys.removeAll { $0 == t.key } }
                if !changed.contains(p.id) { changed.append(p.id) }
            }
            return Group(id: p.id, keys: keys)
        }
        let known = Set(s.portfolios.map(\.id))
        var mainSet = Set(s.main)
        var mainAdd: [String] = []
        var mainRemove: [String] = []
        for t in targets {
            let listed = t.ids.contains(main) && t.ids.contains { known.contains($0) }
            if listed, !mainSet.contains(t.key) {
                mainSet.insert(t.key)
                mainAdd.append(t.key)
            } else if !listed, mainSet.contains(t.key) {
                mainSet.remove(t.key)
                mainRemove.append(t.key)
            }
        }
        let mainList = mainAdd.isEmpty && mainRemove.isEmpty ? s.main : s.main.filter { mainSet.contains($0) } + mainAdd
        return Change(next: State(portfolios: portfolios, main: mainList), changed: changed, mainAdd: mainAdd, mainRemove: mainRemove)
    }

    /// Move: the holdings end up only in `to` ("main" or a portfolio id).
    static func move(_ s: State, _ keys: [String], to: String) -> Change {
        place(s, keys.map { (key: $0, ids: [to]) })
    }

    /// Copy: the holdings also show in `to`, staying where they are.
    static func copy(_ s: State, _ keys: [String], to: String) -> Change {
        place(s, keys.map { key -> (key: String, ids: [String]) in
            let now = members(s, key)
            return (key: key, ids: now.contains(to) ? now : now + [to])
        })
    }

    /// Applies `portfolio-main` adds and drops to a list (the account's, which may have changed
    /// since loading).
    static func applyMainChange(_ list: [String], add: [String], remove: [String]) -> [String] {
        let drop = Set(remove)
        let kept = list.filter { !drop.contains($0) }
        let have = Set(kept)
        return kept + add.filter { !have.contains($0) }
    }
}
