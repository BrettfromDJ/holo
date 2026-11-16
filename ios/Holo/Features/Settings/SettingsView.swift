import SwiftUI
import UserNotifications
import Supabase

struct SettingsView: View {
    @Environment(SessionModel.self) private var session
    @Environment(CollectionStore.self) private var store
    @Environment(GroupsStore.self) private var groups
    @State private var confirming = false
    @State private var showingWelcome = false
    @State private var testing = false
    @State private var testResult: String?
    @State private var demo: DemoKind? = DemoKind.selected
    @State private var prefs = NotificationPrefs()
    /// The saved switches have loaded (until then, changes aren't saved over them).
    @State private var prefsLoaded = false
    @Environment(DealStore.self) private var deals
    @Environment(GradingStore.self) private var grading
    @Environment(\.openURL) private var openURL
    @AppStorage(ScanGame.key) private var scanGame = ScanGame.pokemon.rawValue
    @State private var dealSettings = false
    @State private var gradingCosts = false
    @State private var editingBudget = false
    @State private var budgetText = ""
    @State private var sharing = false
    @State private var deletingAccount = false
    @State private var deleteError: String?
    /// Whether iOS lets Dexora show notifications (the switches do nothing when it doesn't).
    @State private var notifyStatus: UNAuthorizationStatus?

    private var email: String? {
        if case let .signedIn(_, email) = session.state { return email }
        return nil
    }

    private var signedIn: Bool {
        if case .signedIn = session.state { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if signedIn {
                        LabeledContent("Signed in as", value: email ?? "—")
                        Button("Sign out", role: .destructive) { confirming = true }
                        Button("Delete account", role: .destructive) { deletingAccount = true }
                        if let deleteError { Text(deleteError).font(.footnote).foregroundStyle(Theme.muted) }
                    } else {
                        // Trying the demo without an account.
                        Text("You're looking at a demo. Sign in to track your own\u{00A0}collection.").foregroundStyle(Theme.muted)
                        Button("Sign in") { Onboarding.shared.tryingDemo = false }
                    }
                } header: {
                    SectionTitle("Account")
                }
                Section {
                    if notifyStatus == .denied {
                        // The switches can't do anything until iOS allows Dexora's notifications.
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notifications are off for Dexora in your iPhone's Settings, so none of these will\u{00A0}arrive.")
                                .font(.geist(14)).foregroundStyle(.white)
                            Button("Open iPhone Settings") {
                                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                            }
                            .font(.geist(14, .semibold)).foregroundStyle(Theme.lime)
                        }
                        .padding(.vertical, 4)
                    }
                    notifyToggle("Price targets", "A card you watch hits your target price", \.priceTargets)
                    notifyToggle("Big moves", "One of your cards moves 15% in a day", \.bigMoves)
                    notifyToggle("Milestones", "Your collection passes a new high, or a card doubles", \.milestones)
                    notifyToggle("Sets nearly done", "Sundays, when a set is 1 to 5 cards from finished", \.nearlyDone)
                    notifyToggle("Weekly recap", "Sundays at 6pm, your week in Dexora", \.weeklyRecap)
                    if notifyStatus == .authorized || notifyStatus == .provisional {
                    Button {
                        Task { await sendTest() }
                    } label: {
                        HStack {
                            Text(testing ? "Sending…" : "Send a test notification")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }
                    .disabled(testing)
                    if let testResult {
                        Text(testResult).font(.footnote).foregroundStyle(Theme.muted)
                    }
                    }
                } header: {
                    SectionTitle("Notifications")
                } footer: {
                    SectionNote("Price targets, big moves, milestones and sets arrive after the daily price check.")
                }
                // Settings that live on other screens, gathered here with their current values.
                Section {
                    Button { dealSettings = true } label: { prefRow("Deal", deals.role.title) }
                    Picker("Scanner game", selection: $scanGame) {
                        ForEach(ScanGame.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Button { gradingCosts = true } label: {
                        prefRow("Grading costs", Format.money(grading.costs.fee + grading.costs.shipping) + " a card")
                    }
                    Button {
                        budgetText = store.monthlyBudget.map { String(format: "%.0f", $0) } ?? ""
                        editingBudget = true
                    } label: { prefRow("Monthly budget", store.monthlyBudget.map { Format.money($0) } ?? "None") }
                } header: {
                    SectionTitle("Preferences")
                }
                Section {
                    ShareLink(item: ExportFile(transactions: store.transactions, watchlist: store.watchlist, products: store.products,
                                               mode: store.demo == nil ? "cloud" : "demo"),
                              preview: SharePreview("Dexora export")) {
                        Label("Export your data", systemImage: "square.and.arrow.up")
                    }
                    if signedIn && store.demo == nil {
                        Button { sharing = true } label: { Label("Share your collection", systemImage: "link") }
                    }
                } header: {
                    SectionTitle("Collection")
                } footer: {
                    SectionNote("Export saves everything as a file, the same as the website's export. Share makes a read-only link you can turn off any time.")
                }
                Section {
                    NavigationLink { NumbersExplained() } label: { Text("How the numbers work") }
                    if !AppConfig.supportEmail.isEmpty, let url = contactURL {
                        Link("Contact us", destination: url)
                    }
                    Link("Open Dexora on the web", destination: AppConfig.apiBaseURL)
                } header: {
                    SectionTitle("Help")
                } footer: {
                    SectionNote("Your collection syncs with the website.")
                }
                Section {
                    LabeledContent("Version", value: versionText)
                    Link("Privacy", destination: AppConfig.apiBaseURL.appendingPathComponent("privacy"))
                    Link("Terms", destination: AppConfig.apiBaseURL.appendingPathComponent("terms"))
                } header: {
                    SectionTitle("About")
                }
                // For showing the app to someone: last, after the everyday settings.
                Section {
                    Button("Welcome pages") { showingWelcome = true }
                } header: {
                    SectionTitle("Try the app")
                } footer: {
                    SectionNote("What a new person sees before sign-in. A look only; nothing is saved.")
                }
                Section {
                    Picker("Show", selection: $demo) {
                        Text("My collection").tag(DemoKind?.none)
                        ForEach(DemoKind.allCases) { kind in Text("Demo: \(kind.title)").tag(DemoKind?.some(kind)) }
                    }
                    .onChange(of: demo) { _, kind in
                        DemoKind.selected = kind
                        Task {
                            // Lists and portfolios follow too: a demo's never show in your account.
                            groups.reset()
                            if let kind {
                                store.loadDemo(kind)
                                await groups.load(userId: nil, store: store)
                            } else if case let .signedIn(userId, _) = session.state {
                                async let lists: Void = groups.load(userId: userId, store: store)
                                await store.load(userId: userId)
                                await lists
                            }
                            // No account: "My collection" means signing in first.
                            else { Onboarding.shared.tryingDemo = false }
                        }
                    }
                } header: {
                    SectionTitle("Demo collection")
                } footer: {
                    SectionNote("See how the app looks with a made-up collection: sealed only, singles only, singles with graded slabs, or a mix. Prices are made up and nothing you do in a demo is saved. Pick My collection to go back.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Account")
            .toolbarBackground(.hidden, for: .navigationBar)
            .clearTopEdge()
            .toolbar { ToolbarItem(placement: .confirmationAction) { DoneButton() } }
            .alert("Sign out of Dexora?", isPresented: $confirming) {
                Button("Cancel", role: .cancel) {}
                Button("Sign out", role: .destructive) {
                    // Signed out, the welcome pages show again (the ways in, demo included).
                    Onboarding.shared.welcomeSeen = false
                    Task { await session.signOut() }
                }
            }
            .task {
                await loadPrefs()
                notifyStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            }
            .sheet(isPresented: $dealSettings) { DealRatesSheet() }
            .sheet(isPresented: $gradingCosts) { CostsSheet() }
            .sheet(isPresented: $sharing) { ShareCollectionSheet() }
            .alert("Monthly budget", isPresented: $editingBudget) {
                TextField("500", text: $budgetText).keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) { Task { try? await store.setMonthlyBudget(nil) } }
                Button("Save") { Task { try? await store.setMonthlyBudget(MoneyField.value(budgetText)) } }
            } message: {
                Text("What you plan to spend a month. Overview shows how much is\u{00A0}left.")
            }
            .alert("Delete your account?", isPresented: $deletingAccount) {
                Button("Cancel", role: .cancel) {}
                Button("Delete everything", role: .destructive) { Task { await deleteAccount() } }
            } message: {
                Text("This permanently removes your account and everything in it: your collection, lists, deals and settings, on the app and the website. It can't be undone. Export your data first if you want a\u{00A0}copy.")
            }
            .fullScreenCover(isPresented: $showingWelcome) {
                // A look at the welcome pages; its buttons just close it here.
                WelcomeView(preview: true, onEmail: { showingWelcome = false }, onDemo: { showingWelcome = false })
            }
        }
    }

    /// A preference row: its name, and its current value on the right.
    private func prefRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.white)
            Spacer()
            Text(value).foregroundStyle(Theme.muted)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.subtle)
        }
    }

    private var versionText: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return b.map { "\(v) (\($0))" } ?? v
    }

    /// An email to support with the version filled in.
    private var contactURL: URL? {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = AppConfig.supportEmail
        c.queryItems = [URLQueryItem(name: "subject", value: "Dexora \(versionText)")]
        return c.url
    }

    private func deleteAccount() async {
        deleteError = nil
        do {
            try await Backend.shared.api.deleteAccount()
            Onboarding.shared.welcomeSeen = false
            await session.signOut()
        } catch {
            deleteError = error.localizedDescription
        }
    }

    /// A notification kind's switch: its name, and a line on when it comes.
    private func notifyToggle(_ title: String, _ note: String, _ key: WritableKeyPath<NotificationPrefs, Bool>) -> some View {
        Toggle(isOn: Binding(get: { prefs[keyPath: key] }, set: { on in
            prefs[keyPath: key] = on
            Task { await savePrefs() }
        })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(note).font(.geist(12)).foregroundStyle(Theme.muted)
            }
        }
        .tint(Theme.lime)
        .disabled(!prefsLoaded)
    }

    private func loadPrefs() async {
        guard signedIn, !Demo.isOn, DemoKind.selected == nil else {
            prefs.weeklyRecap = NotificationPrefs.recapOn
            prefsLoaded = true
            return
        }
        if let saved = try? await UserState.load(NotificationPrefs.key, as: NotificationPrefs.self) { prefs = saved }
        prefs.weeklyRecap = NotificationPrefs.recapOn
        prefsLoaded = true
    }

    private func savePrefs() async {
        // The recap is set on the phone: schedule or cancel it now.
        NotificationPrefs.recapOn = prefs.weeklyRecap
        await Notifications.scheduleWeeklyRecap()
        guard let userId = store.userId, !Demo.isOn, DemoKind.selected == nil else { return }
        try? await UserState.save(NotificationPrefs.key, prefs, userId: userId)
    }

    private func sendTest() async {
        testing = true
        testResult = nil
        defer { testing = false }
        // Make sure this phone is registered; the token is saved a moment after permission is given.
        await PushRegistration.enable()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        do {
            let r = try await Backend.shared.api.testPush()
            if r.sent > 0 {
                testResult = "Sent. It should appear in a few seconds."
            } else {
                testResult = "Apple didn't accept it: \(r.reasons.joined(separator: ", "))."
            }
        } catch let error as HoloError where error.code == "no_devices" {
            testResult = "This phone isn't registered yet. Check notifications are allowed for Dexora in Settings, then try again."
        } catch {
            testResult = error.localizedDescription
        }
    }
}

/// Closes a sheet; hidden when the view isn't presented as one.
private struct DoneButton: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented

    var body: some View {
        if isPresented { Button("Done") { dismiss() } }
    }

}

/// "Cost basis is what you actually paid…": the term in white, the rest muted.
private func explainer(_ term: String, _ text: String) -> some View {
    (Text(term).foregroundColor(.white).fontWeight(.semibold) + Text(" " + text).foregroundColor(Theme.muted))
        .font(.geist(14))
        .padding(.vertical, 2)
}

/// How the numbers work, in plain words (from Account → Help).
private struct NumbersExplained: View {
    var body: some View {
        List {
            Section {
                explainer("What you paid", "is the price plus your share of shipping, fees and tax. When you sell, the oldest copies count as sold first.")
                explainer("Gain", "is what something is worth now minus what you paid. Cards with no market price are left out, not counted as $0.")
                explainer("Today's change", "only counts price moves on things you already owned yesterday. Buying a $1,000 box adds $1,000 of value, not $1,000 of gain.")
                explainer("Market-only return", "is how prices moved, leaving out when you bought and sold, so adding to or selling from your collection doesn't skew it.")
                explainer("Realized", "is profit from things you've sold. Sales & taxes in Analytics shows each sale.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("How the numbers work")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A read-only link to your whole collection (the website's share page), with or without gains.
private struct ShareCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CollectionStore.self) private var store
    @State private var link: ShareRow?
    @State private var loading = true
    @State private var error: String?

    struct ShareRow: Codable { var id: String; var token: String; var title: String?; var show_gains: Bool; var revoked_at: String? }

    private var url: URL? { link.map { AppConfig.apiBaseURL.appendingPathComponent("s").appendingPathComponent($0.token) } }

    var body: some View {
        NavigationStack {
            GlassForm {
                if let url, let link {
                    Section {
                        ShareLink(item: url) { Label("Send link", systemImage: "square.and.arrow.up") }
                        Toggle("Show what I paid and my gains", isOn: Binding(get: { link.show_gains }, set: { on in Task { await setGains(on) } }))
                    } footer: {
                        Text(url.absoluteString)
                    }
                    Section {
                        Button("Stop sharing", role: .destructive) { Task { await stop() } }
                    } footer: {
                        Text("Anyone with the link sees your cards and their value. Never your email, notes or where you bought\u{00A0}things.")
                    }
                } else if !loading {
                    Section {
                        Button("Create a link") { Task { await create() } }
                    } footer: {
                        Text("A read-only page anyone with the link can open, no sign-in needed. You can turn it off any\u{00A0}time.")
                    }
                }
                if let error { Section { Text(error).foregroundStyle(Theme.muted) } }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Share your collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
        .glassSheet()
    }

    private var db: SupabaseClient { Backend.shared.supabase }

    private func load() async {
        defer { loading = false }
        let rows: [ShareRow] = (try? await db.from("share_links").select("id,token,title,show_gains,revoked_at").execute().value) ?? []
        // Collection links only: list links carry a "list:" title.
        link = rows.first { $0.revoked_at == nil && !($0.title ?? "").hasPrefix(ListPricing.sharePrefix) }
    }

    private func create() async {
        guard let userId = store.userId else { return }
        struct New: Encodable { var user_id: String; var token: String; var show_gains: Bool }
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
        do {
            try await db.from("share_links").insert(New(user_id: userId, token: token, show_gains: false)).execute()
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func setGains(_ on: Bool) async {
        guard let id = link?.id else { return }
        struct Patch: Encodable { var show_gains: Bool }
        do {
            try await db.from("share_links").update(Patch(show_gains: on)).eq("id", value: id).execute()
            link?.show_gains = on
        } catch { self.error = error.localizedDescription }
    }

    private func stop() async {
        guard let id = link?.id else { return }
        struct Patch: Encodable { var revoked_at: String }
        do {
            try await db.from("share_links").update(Patch(revoked_at: ISO8601DateFormatter().string(from: Date()))).eq("id", value: id).execute()
            link = nil
        } catch { self.error = error.localizedDescription }
    }
}
