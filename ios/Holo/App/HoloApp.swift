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
        // A bigger download cache, so pictures (set banners, cards) come back from the phone's
        // storage on the next launch instead of over the network.
        URLCache.shared = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024)
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
                .toggleStyle(LimeToggleStyle())
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
    @State private var onboarding = Onboarding.shared

    private var signedIn: Bool {
        if case .signedIn = session.state { return true }
        return false
    }

    var body: some View {
        Group {
            if Demo.isOn, ProcessInfo.processInfo.arguments.contains("-HoloOnboarding") {
                // Screenshots: the welcome pages.
                WelcomeView(onEmail: {}, onDemo: {})
            } else if Demo.isOn {
                // Screenshots and tryouts: the made-up collection, no account needed.
                MainTabView()
                    .onAppear {
                        store.loadDemo(Demo.value("-HoloDemoKind").flatMap(DemoKind.init(rawValue:)) ?? .mixed)
                        if let id = Demo.value("-HoloProduct") { Router.shared.product = id }
                        if ProcessInfo.processInfo.arguments.contains("-HoloDealDemo") { deals.loadDemo(from: store) }
                        // -HoloDealRole collector: the Deal tab as a collector at a vendor's table.
                        if let role = Demo.value("-HoloDealRole").flatMap(DealRole.init(rawValue:)) { deals.role = role }
                        Task { await groups.load(userId: nil, store: store) }
                        // Screenshots: a rainbow bumper on the first slab, and the pull reveal.
                        if ProcessInfo.processInfo.arguments.contains("-HoloBumper"),
                           let slab = store.allHoldings.first(where: { $0.identity.isGraded }) {
                            grading.bumpers[slab.identity.key] = "rainbow"
                            grading.certs[slab.identity.key] = "84512369"
                        }
                        if ProcessInfo.processInfo.arguments.contains("-HoloPull"),
                           let h = store.allHoldings.first(where: { $0.product?.isSealed == false && !$0.identity.isGraded }) ?? store.allHoldings.first,
                           let p = h.product {
                            Router.shared.pull = PullEvent(product: p, quantity: 1, before: store.summary.value - (h.value ?? 0), identity: h.identity,
                                                           pulled: ProcessInfo.processInfo.arguments.contains("-HoloPulled"))
                        }
                    }
            } else if !AppConfig.isConfigured {
                NotConfiguredView()
            } else if onboarding.tryingDemo, !signedIn {
                // "Try the demo" from the welcome pages: the made-up collection without an
                // account, until Account → My collection or Sign in.
                MainTabView()
                    .task {
                        store.loadDemo(DemoKind.selected ?? .mixed)
                        await groups.load(userId: nil, store: store)
                        await grading.load(userId: nil)
                    }
            } else {
                switch session.state {
                case .loading:
                    // Restoring the session takes a moment: blank, no spinner.
                    Theme.background.ignoresSafeArea()
                case .signedOut:
                    if onboarding.welcomeSeen {
                        SignInView()
                    } else {
                        // The first time only: what the app does, then the ways in.
                        WelcomeView(onEmail: {}, onDemo: { onboarding.tryingDemo = true })
                    }
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
                // The no-account demo keeps showing after the session settles as signed out.
                if onboarding.tryingDemo {
                    store.loadDemo(DemoKind.selected ?? .mixed)
                    Task { await groups.load(userId: nil, store: store) }
                }
            } else if case .signedIn = state {
                onboarding.tryingDemo = false
                onboarding.welcomeSeen = true
            }
        }
    }
}

/// Shown when Config.xcconfig wasn't filled in before building.
struct NotConfiguredView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wrench.and.screwdriver").font(.largeTitle).foregroundStyle(Theme.muted)
            Text("Dexora isn't set up yet").font(.title3.bold())
            Text("Copy ios/Config.xcconfig.example to ios/Config.xcconfig, fill in your API and Supabase hosts, then run xcodegen and build\u{00A0}again.")
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
    @State private var notifications = NotificationExplainer.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        // Screenshots: -HoloScan opens the scanner.
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-HoloScan") else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            scanning = true
        }
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
            if !router.tabBarHidden && !(tab == .deal && router.dealDocked) {
            HoloTabBar(
                items: [
                    .init(tab: .home, title: "Overview", icon: "chart.line.uptrend.xyaxis"),
                    .init(tab: .collection, title: "Collection", icon: "square.grid.2x2"),
                    .init(tab: .explore, title: "Explore", icon: "safari"),
                    .init(tab: .deal, title: "Deal", icon: "arrow.left.arrow.right", iconSize: 17),
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
            .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: router.tabBarHidden)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: tab == .deal && router.dealDocked)
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
        .onChange(of: router.scanRequest) { _, _ in startScan() }
        .onChange(of: router.searchRequest) { _, _ in searching = true }
        // One line on why before the notifications prompt, the first time something asks for it.
        .sheet(isPresented: Binding(get: { notifications.pending }, set: { if !$0 { notifications.answer(false) } })) {
            NotificationNoteSheet { notifications.answer($0) }
        }
        .onChange(of: router.tabRequest) { _, request in
            switch request {
            case "home": tab = .home
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
        .sheet(isPresented: $askScanTarget) {
            ScanTargetSheet { choice in
                askScanTarget = false
                // Open the scanner once the sheet is down.
                Task {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    switch choice {
                    case .incoming: scanChoice = .deal(.incoming); dealScan = .incoming
                    case .outgoing: scanChoice = .deal(.outgoing); dealScan = .outgoing
                    case nil: scanChoice = .collection; scanning = true
                    }
                }
            }
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


/// Scanning while a deal is open: a small glass sheet asking where the cards go, three clear
/// rows (into the deal, either side, or straight into your collection).
struct ScanTargetSheet: View {
    /// The deal side picked, or nil for your collection.
    var onPick: (DealSide?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Scan into").font(.display(24)).tracking(-0.6)
                    Text("A deal is open").font(.geist(13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("Cancel") { dismiss() }.font(.geist(15, .medium)).foregroundStyle(Theme.muted)
            }
            VStack(spacing: 8) {
                row("Coming in", "Cards the customer hands you", icon: "arrow.down.left", tint: Theme.lime) { onPick(.incoming) }
                row("Going out", "Cards you hand over", icon: "arrow.up.right", tint: Theme.planPink) { onPick(.outgoing) }
                row("My collection", "Not part of the deal", icon: "square.grid.2x2", tint: .white) { onPick(nil) }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(330)])
        .glassSheet()
    }

    private func row(_ title: String, _ sub: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(tint.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.geist(16, .semibold))
                    Text(sub).font(.geist(13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.subtle)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .sheetPanel(radius: 18)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
