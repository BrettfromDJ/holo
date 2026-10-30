import SwiftUI

@main
struct HoloApp: App {
    @State private var session = SessionModel()
    @State private var store = CollectionStore()
    @State private var deals = DealStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(store)
                .environment(deals)
                .preferredColorScheme(.dark)
                .tint(Theme.lime)
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

    enum HomeTab { case home, collection, scan, deal, lists }

    var body: some View {
        TabView(selection: $tab) {
            HomeView(onScan: { scanning = true })
                .tabItem { Label("Home", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(HomeTab.home)
            CollectionView(onScan: { scanning = true })
                .tabItem { Label("Collection", systemImage: "square.grid.2x2.fill") }
                .tag(HomeTab.collection)
            // Scan is an action, not a page: picking it opens the camera and keeps you where you were.
            Color.clear
                .tabItem { Label("Scan", systemImage: "viewfinder") }
                .tag(HomeTab.scan)
            DealView()
                .tabItem { Label("Deal", systemImage: "arrow.left.arrow.right") }
                .tag(HomeTab.deal)
            ListsView()
                .tabItem { Label("Lists", systemImage: "heart.text.square") }
                .tag(HomeTab.lists)
        }
        .onChange(of: tab) { old, new in
            if new == .scan {
                tab = old
                scanning = true
            }
        }
        .fullScreenCover(isPresented: $scanning) { ScanView() }
    }
}
