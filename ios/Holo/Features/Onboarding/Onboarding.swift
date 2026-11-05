import Foundation
import Observation
import SwiftUI

/// The first-run flags kept on this phone: whether the welcome pages were seen, whether the
/// demo is being tried without an account, and (per account) whether the first-run steps are
/// done. Nothing here is a secret or synced; the one shared value is `Collects` below.
@Observable
final class Onboarding {
    static let shared = Onboarding()

    /// The welcome pages show once; after that a signed-out app opens on the sign-in form.
    var welcomeSeen: Bool {
        didSet { UserDefaults.standard.set(welcomeSeen, forKey: "onboarding-welcome-seen") }
    }

    /// "Try the demo" on the welcome pages: the made-up collection, no account. Survives a
    /// relaunch; Account → My collection (or Sign in) switches back to the sign-in form.
    var tryingDemo: Bool {
        didSet { UserDefaults.standard.set(tryingDemo, forKey: "onboarding-trying-demo") }
    }

    private init() {
        welcomeSeen = UserDefaults.standard.bool(forKey: "onboarding-welcome-seen")
        tryingDemo = UserDefaults.standard.bool(forKey: "onboarding-trying-demo")
    }

    /// The two first-run steps (what you collect, add your first card) finished or skipped.
    static func isDone(userId: String) -> Bool {
        UserDefaults.standard.bool(forKey: "onboarding-done:\(userId)")
    }

    static func markDone(userId: String) {
        UserDefaults.standard.set(true, forKey: "onboarding-done:\(userId)")
    }

    /// The one-line note in the scanner before the camera prompt, shown once.
    static var cameraNoteSeen: Bool {
        get { UserDefaults.standard.bool(forKey: "onboarding-camera-note-seen") }
        set { UserDefaults.standard.set(newValue, forKey: "onboarding-camera-note-seen") }
    }

    /// The one-line note before the notifications prompt, shown once.
    static var notificationsExplained: Bool {
        get { UserDefaults.standard.bool(forKey: "onboarding-notifications-explained") }
        set { UserDefaults.standard.set(newValue, forKey: "onboarding-notifications-explained") }
    }
}

/// The games you collect (`user_state` key `collects`, a list of game slugs, shared with the
/// website). Picked on first run; Search and Explore put those brands first.
enum Collects {
    struct Game: Identifiable, Hashable {
        var slug: String
        var name: String
        var id: String { slug }
    }

    /// The brands offered when the catalog can't be reached, spelled as the catalog spells them
    /// (so a brand picked offline still matches Search's brand filter).
    static let fallback: [Game] = [
        Game(slug: "pokemon", name: "Pokemon"),
        Game(slug: "pokemon-japan", name: "Pokemon Japan"),
        Game(slug: "magic", name: "Magic: The Gathering"),
        Game(slug: "one-piece", name: "One Piece"),
        Game(slug: "lorcana", name: "Disney Lorcana"),
        Game(slug: "yugioh", name: "Yu-Gi-Oh!"),
    ]

    /// Every brand in the catalog, or the fixed list when offline or in a demo.
    static func games() async -> [Game] {
        guard !Demo.isOn else { return fallback }
        if let index = try? await Backend.shared.api.exploreIndex(), !index.games.isEmpty {
            return index.games.map { Game(slug: $0.slug, name: $0.name) }
        }
        return fallback
    }

    /// The picked slugs as last known on this phone (the account's list when it was read).
    static var cached: [String] {
        get { UserDefaults.standard.stringArray(forKey: "collects") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "collects") }
    }

    /// Picked slug → brand name, so Search can default its brand filter without the catalog.
    static var cachedNames: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "collects-names") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "collects-names") }
    }

    /// Reads the account's list into the phone's copy. A failed read keeps what's there.
    static func refresh() async {
        guard let list = try? await UserState.load("collects", as: [String].self) else { return }
        cached = list ?? []
    }

    /// Saves the picks. The account's row is read first; if it can't be, only the phone's copy
    /// changes (never save over a failed load).
    static func save(_ games: [Game], userId: String?) async {
        cached = games.map(\.slug)
        cachedNames = Dictionary(games.map { ($0.slug, $0.name) }, uniquingKeysWith: { a, _ in a })
        guard let userId, !Demo.isOn else { return }
        do {
            _ = try await UserState.load("collects", as: [String].self)
        } catch {
            return
        }
        try? await UserState.save("collects", games.map(\.slug), userId: userId)
    }

    /// The one brand to filter Search by when every pick is a language of the same brand
    /// (Pokémon and Pokémon Japan → "Pokémon"); nil when the picks span brands or none were made.
    static var singleBrand: String? {
        let names = cached.compactMap { cachedNames[$0] }
        let brands = Set(names.compactMap { SearchFilters.brand(of: $0) })
        return brands.count == 1 ? brands.first : nil
    }

    /// Picked brands first, then the rest in their original order.
    static func ordered(_ games: [ExploreGame]) -> [ExploreGame] {
        let picked = cached
        guard !picked.isEmpty else { return games }
        let rank = Dictionary(picked.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return games.enumerated().sorted { a, b in
            let ra = rank[a.element.slug] ?? Int.max
            let rb = rank[b.element.slug] ?? Int.max
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }
}

/// An empty page, in the house style: a short title, one muted line and one lime action
/// (with an optional quiet link under it). No pictures, no coach marks.
struct EmptyPage: View {
    var title: String
    var line: String
    var action: String?
    var icon: String = "viewfinder"
    var onAction: () -> Void = {}
    var link: String?
    var onLink: () -> Void = {}

    var body: some View {
        VStack(spacing: 12) {
            Text(title).font(.display(28)).tracking(-0.7).multilineTextAlignment(.center)
            Text(line).font(.geist(15)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action: onAction) { Label(action, systemImage: icon) }
                    .buttonStyle(Button3D(kind: .lime, fullWidth: false))
                    .padding(.top, 8)
            }
            if let link {
                Button(link, action: onLink).font(.geist(15, .medium)).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 48)
    }
}
