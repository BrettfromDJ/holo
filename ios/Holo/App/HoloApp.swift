import SwiftUI

@main
struct HoloApp: App {
    @State private var session = SessionModel()
    @State private var store = CollectionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Theme.lime)
        }
    }
}

struct RootView: View {
    @Environment(SessionModel.self) private var session
    @Environment(CollectionStore.self) private var store

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
                        .task(id: userId) { await store.load(userId: userId) }
                }
            }
        }
        .onAppear { if AppConfig.isConfigured { session.start() } }
        .onChange(of: session.state) { _, state in
            if state == .signedOut { store.reset() }
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
    @State private var tab = HomeTab.collection
    @State private var scanning = false

    enum HomeTab { case collection, search, account }

    var body: some View {
        TabView(selection: $tab) {
            CollectionView(onScan: { scanning = true })
                .tabItem { Label("Collection", systemImage: "square.grid.2x2.fill") }
                .tag(HomeTab.collection)
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(HomeTab.search)
            SettingsView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(HomeTab.account)
        }
        // The scanner opens full screen from the floating button, like a camera app.
        .overlay(alignment: .bottom) {
            Button { scanning = true } label: {
                Image(systemName: "viewfinder")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 60, height: 60)
                    .background(Theme.lime, in: Circle())
                    .shadow(color: Theme.lime.opacity(0.35), radius: 14, y: 4)
            }
            .accessibilityLabel("Scan cards")
            .padding(.bottom, 58)
        }
        .fullScreenCover(isPresented: $scanning) { ScanView() }
    }
}
