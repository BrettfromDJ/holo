import SwiftUI

@main
struct HoloApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = SessionModel()
    @State private var store = CollectionStore()
    @State private var deals = DealStore()

    init() {
        Fonts.applyAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(store)
                .environment(deals)
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

    var body: some View {
        Group {
            if !AppConfig.isConfigured {
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
                            await store.load(userId: userId)
                            await deals.load(userId: userId)
                        }
                }
            }
        }
        .onAppear { if AppConfig.isConfigured { session.start() } }
        .onChange(of: session.state) { _, state in
            if state == .signedOut {
                store.reset()
                deals.reset()
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

struct MainTabView: View {
    @State private var tab = HomeTab.home
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
        .overlay(alignment: .bottom) {
            HoloTabBar(
                items: [
                    .init(tab: .home, title: "Overview", icon: "chart.line.uptrend.xyaxis"),
                    .init(tab: .collection, title: "Collection", icon: "square.grid.2x2"),
                    .init(tab: .explore, title: "Explore", icon: "safari"),
                    .init(tab: .deal, title: "Deal", icon: "arrow.left.arrow.right"),
                ],
                selection: $tab,
                onPlus: { adding = true }
            )
        }
        .onChange(of: router.tabRequest) { _, request in
            if request == "collection" { tab = .collection }
            router.tabRequest = nil
        }
        .confirmationDialog("Add to your collection", isPresented: $adding) {
            Button("Scan cards") { scanning = true }
            Button("Search and add") { searching = true }
        }
        .fullScreenCover(isPresented: $scanning) { ScanView() }
        .sheet(isPresented: $searching) { SearchView(asSheet: true) }
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
