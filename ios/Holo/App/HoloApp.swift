import SwiftUI

@main
struct HoloApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = SessionModel()
    @State private var store = CollectionStore()
    @State private var deals = DealStore()
    @State private var grading = GradingStore()
    @State private var groups = GroupsStore()

    init() {
        Fonts.applyAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(store)
                .environment(deals)
                .environment(grading)
                .environment(groups)
                .preferredColorScheme(.dark)
                .tint(Theme.lime)
                .font(.geist(15))
        }
    }
}

struct RootView: View {
    @Environment(SessionModel.self) private var session
    @Environment(CollectionStore.self) private var store
    @Environment(DealStore.self) private var deals
    @Environment(GradingStore.self) private var grading
    @Environment(GroupsStore.self) private var groups

    var body: some View {
        Group {
            if Demo.isOn {
                // Screenshots and tryouts: the made-up collection, no account needed.
                MainTabView()
                    .onAppear {
                        store.loadDemo(Demo.value("-HoloDemoKind").flatMap(DemoKind.init(rawValue:)) ?? .mixed)
                        if let id = Demo.value("-HoloProduct") { Router.shared.product = id }
                        if ProcessInfo.processInfo.arguments.contains("-HoloDealDemo") { deals.loadDemo(from: store) }
                        Task { await groups.load(userId: nil, store: store) }
                        // Screenshots: a rainbow bumper on the first slab, and the pull reveal.
                        if ProcessInfo.processInfo.arguments.contains("-HoloBumper"),
                           let slab = store.allHoldings.first(where: { $0.identity.isGraded }) {
                            grading.bumpers[slab.identity.key] = "rainbow"
                            grading.certs[slab.identity.key] = "84512369"
                        }
                        if ProcessInfo.processInfo.arguments.contains("-HoloPull"), let h = store.allHoldings.first, let p = h.product {
                            Router.shared.pull = PullEvent(product: p, quantity: 1, before: store.summary.value - (h.value ?? 0))
                        }
                    }
            } else if !AppConfig.isConfigured {
                NotConfiguredView()
            } else {
                switch session.state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background)
                case .signedOut:
                    SignInView()
                case let .signedIn(userId, _):
                    MainTabView()
                        .task(id: userId) {
                            await PushRegistration.refreshIfAllowed()
                            if let kind = DemoKind.selected { store.loadDemo(kind) } else { await store.load(userId: userId) }
                            await deals.load(userId: userId)
                            await groups.load(userId: store.demo == nil ? userId : nil, store: store)
                            await grading.load(userId: store.demo == nil ? userId : nil)
                        }
                }
            }
        }
        .onAppear { if AppConfig.isConfigured, !Demo.isOn { session.start() } }
        .onChange(of: session.state) { _, state in
            if state == .signedOut {
                store.reset()
                deals.reset()
                grading.reset()
                groups.reset()
            }
        }
    }
}

/// Shown when Config.xcconfig wasn't filled in before building.
struct NotConfiguredView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wrench.and.screwdriver").font(.largeTitle).foregroundStyle(Theme.muted)
            Text("Holo isn't set up yet").font(.title3.bold())
            Text("Copy ios/Config.xcconfig.example to ios/Config.xcconfig, fill in your API and Supabase hosts, then run xcodegen and build again.")
                .font(.callout).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

/// Launch arguments for demo mode: `-HoloDemo`, then optionally `-HoloTab collection` or
/// `-HoloProduct sample:es-bb` to open on a screen (used by the screenshot tests).
enum Demo {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-HoloDemo") }

    static func value(_ flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

struct MainTabView: View {
    @State private var tab: HomeTab = {
        switch Demo.value("-HoloTab") {
        case "collection": return .collection
        case "explore": return .explore
        case "deal": return .deal
        default: return .home
        }
    }()
    @State private var scanning = false
    @State private var adding = false
    @State private var searching = false
    @State private var router = Router.shared

    enum HomeTab { case home, collection, explore, deal }

    var body: some View {
        TabView(selection: $tab) {
            HomeView(onScan: { scanning = true })
                .tag(HomeTab.home)
                .toolbar(.hidden, for: .tabBar)
            CollectionView(onScan: { scanning = true })
                .tag(HomeTab.collection)
                .toolbar(.hidden, for: .tabBar)
            ExploreView()
                .tag(HomeTab.explore)
                .toolbar(.hidden, for: .tabBar)
            DealView()
                .tag(HomeTab.deal)
                .toolbar(.hidden, for: .tabBar)
        }
        // The website's bar: Overview, Collection, the lime +, Explore, Deal. It floats over the
        // pages (each page leaves room under its last card), so content shows through the glass.
        // The add menu: Scan and Search pop out from behind the + (drawn under the bar, so the
        // + stays on top and turns into a ×).
        .overlay {
            AddMenu(open: $adding, onScan: { scanning = true }, onSearch: { searching = true })
        }
        .overlay(alignment: .bottom) {
            HoloTabBar(
                items: [
                    .init(tab: .home, title: "Overview", icon: "chart.line.uptrend.xyaxis"),
                    .init(tab: .collection, title: "Collection", icon: "square.grid.2x2"),
                    .init(tab: .explore, title: "Explore", icon: "safari"),
                    .init(tab: .deal, title: "Deal", icon: "arrow.left.arrow.right"),
                ],
                selection: $tab,
                plusOpen: adding,
                onPlus: { withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { adding.toggle() } }
            )
        }
        // The "pack pull" reveal after a purchase is saved.
        .overlay {
            if let event = router.pull {
                PullReveal(event: event) { router.pull = nil } onOpen: {
                    router.pull = nil
                    router.product = event.product.id
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.25), value: router.pull)
        .onChange(of: router.tabRequest) { _, request in
            if request == "collection" { tab = .collection }
            router.tabRequest = nil
        }
        .onChange(of: router.addMenu) { _, open in
            guard open else { return }
            router.addMenu = false
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { adding = true }
        }
        .fullScreenCover(isPresented: $scanning) { ScanView() }
        .fullScreenCover(isPresented: $searching) { SearchScreen(mode: .add) }
        // A tapped price alert opens its card.
        .sheet(item: Binding(get: { router.product.map(OpenProduct.init) }, set: { router.product = $0?.id })) { open in
            NavigationStack {
                ProductDetailView(productId: open.id)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { router.product = nil } } }
                    .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
            }
        }
    }
}

private struct OpenProduct: Identifiable {
    var id: String
}
