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
                    // Restoring the session takes a moment: blank, no spinner.
                    Theme.background.ignoresSafeArea()
                case .signedOut:
                    SignInView()
                case let .signedIn(userId, _):
                    MainTabView()
                        .task(id: userId) {
                            await PushRegistration.refreshIfAllowed()
                            if let kind = DemoKind.selected {
                                store.loadDemo(kind)
                                await deals.load(userId: userId)
                                await groups.load(userId: nil, store: store)
                            } else {
                                // Portfolios load alongside, so the selected one applies to the
                                // collection saved on the phone as soon as it shows.
                                let portfolios = Task { await groups.load(userId: userId, store: store) }
                                await store.load(userId: userId)
                                await portfolios.value
                                await deals.load(userId: userId)
                            }
                            await grading.load(userId: store.demo == nil ? userId : nil)
                            // Slabs marked CGC Pristine 10 are priced apart; the marks arrive after the first pricing.
                            if !grading.pristine.isEmpty { await store.loadSlabPrices() }
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
            Text("Lucent isn't set up yet").font(.title3.bold())
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

    /// Speed-test switches (CI's PerformanceTests): each turns one feature off so its cost can
    /// be measured. Read once at launch; never set in normal use.
    static let perfNoThumbnails = ProcessInfo.processInfo.arguments.contains("-HoloPerfNoThumbnails")
    static let perfNoSellMeter = ProcessInfo.processInfo.arguments.contains("-HoloPerfNoSellMeter")
    static let perfPlainCGC = ProcessInfo.processInfo.arguments.contains("-HoloPerfPlainCGC")

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
    @Environment(DealStore.self) private var deals
    @Environment(CollectionStore.self) private var store
    /// While a deal is open, the scanner asks where cards go; the answer holds until the deal ends.
    @State private var askScanTarget = false
    @State private var scanChoice: ScanChoice?
    @State private var dealScan: DealSide?
    enum ScanChoice: Equatable { case collection, deal(DealSide) }
    @State private var adding = false
    @State private var searching = false
    @State private var router = Router.shared

    enum HomeTab { case home, collection, explore, deal }

    /// The main scanner: straight to the collection, unless a deal is open, then it asks once
    /// (per deal) whether cards go into the deal or the collection.
    private func startScan() {
        guard deals.deal.kind != .empty else { scanning = true; return }
        switch scanChoice {
        case .collection: scanning = true
        case let .deal(side): dealScan = side
        case nil: askScanTarget = true
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            // The pages take an action, which SwiftUI can't compare, so without `StablePage`
            // every tab switch or tap on the + re-ran all of them.
            StablePage { HomeView(onScan: { startScan() }) }
                .equatable()
                .tag(HomeTab.home)
                .toolbar(.hidden, for: .tabBar)
            StablePage { CollectionView(onScan: { startScan() }) }
                .equatable()
                .tag(HomeTab.collection)
                .toolbar(.hidden, for: .tabBar)
            ExploreView()
                .tag(HomeTab.explore)
                .toolbar(.hidden, for: .tabBar)
            DealView()
                .tag(HomeTab.deal)
                .toolbar(.hidden, for: .tabBar)
        }
        // Every page, and everything pushed on it: a fully clear top bar (no iOS 26 tinted blur).
        .clearTopEdge()
        // Undo for a few seconds after a delete or a sale, above the tab bar.
        .undoToast(bottom: 104)
        // The website's bar: Overview, Collection, the lime +, Explore, Deal. It floats over the
        // pages (each page leaves room under its last card), so content shows through the glass.
        // The add menu: Scan and Search pop out from behind the + (drawn under the bar, so the
        // + stays on top and turns into a ×).
        .overlay {
            AddMenu(open: $adding, onScan: { startScan() }, onSearch: { searching = true })
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
                onPlus: { withAnimation(.spring(response: 0.3, dampingFraction: 0.74)) { adding.toggle() } },
                onTap: { t in
                    let name: String = switch t {
                    case .home: "home"
                    case .collection: "collection"
                    case .explore: "explore"
                    case .deal: "deal"
                    }
                    router.tabTap = TabTap(name: name, count: router.tabTap.count + 1)
                }
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
            switch request {
            case "collection": tab = .collection
            case "explore": tab = .explore
            case "deal": tab = .deal
            default: break
            }
            router.tabRequest = nil
        }
        .onChange(of: router.addMenu) { _, open in
            guard open else { return }
            router.addMenu = false
            withAnimation(.spring(response: 0.3, dampingFraction: 0.74)) { adding = true }
        }
        .fullScreenCover(isPresented: $scanning) { ScanView() }
        // Scanning while a deal is open: into the deal (then show it) or into the collection.
        .background {
            Color.clear.fullScreenCover(item: $dealScan, onDismiss: { tab = .deal }) { side in
                ScanView(dealSide: side, onPick: { c, read in deals.addScanned(c, read: read, to: side, store: store) })
            }
        }
        .confirmationDialog("A deal is open. Where should scanned cards go?", isPresented: $askScanTarget, titleVisibility: .visible) {
            Button("Deal · coming in") { scanChoice = .deal(.incoming); dealScan = .incoming }
            Button("Deal · going out") { scanChoice = .deal(.outgoing); dealScan = .outgoing }
            Button("My collection") { scanChoice = .collection; scanning = true }
            Button("Cancel", role: .cancel) {}
        }
        // A new deal asks again.
        .onChange(of: deals.deal.kind) { _, kind in if kind == .empty { scanChoice = nil } }
        .fullScreenCover(isPresented: $searching) { SearchScreen(mode: .add) }
        // A card you own, tapped on any page (Activity, Master Sets, Analytics, Explore…): Your copy.
        // "View card details" then opens the full card page.
        .sheet(item: Binding(get: { router.holding.map(OpenedHolding.init) }, set: { router.holding = $0?.identity })) { o in
            HoldingSheet(identity: o.identity) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { router.product = o.identity.productId }
            }
        }
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

/// Shows a page and never re-runs it just because its parent redrew; the page still updates
/// from its own state and stores. For pages whose only input is an action that never changes
/// what they show (closures can't be compared, so SwiftUI would otherwise always redraw them).
private struct StablePage<Content: View>: View, Equatable {
    @ViewBuilder var content: Content

    static func == (lhs: StablePage, rhs: StablePage) -> Bool { true }

    var body: some View { content }
}

private struct OpenProduct: Identifiable {
    var id: String
}
