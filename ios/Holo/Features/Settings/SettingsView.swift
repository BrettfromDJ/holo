import SwiftUI
import UserNotifications
import Supabase

struct SettingsView: View {
    @Environment(SessionModel.self) private var session
    @Environment(CollectionStore.self) private var store
    @Environment(GroupsStore.self) private var groups
    @State private var confirming = false
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
    /// Whether iOS lets Corodex show notifications (the switches do nothing when it doesn't).
    @State private var notifyStatus: UNAuthorizationStatus?

    private var email: String? {
        if case let .signedIn(_, email) = session.state { return email }
        return nil
    }

    private var signedIn: Bool {
        if case .signedIn = session.state { return true }
        return false
    }

    @State private var scanTests = ScanTestLog.isOn
    @State private var testSummary = ScanTestLog.Summary()

    var body: some View {
        NavigationStack {
            List {
                // The page's own big title, with Done beside it (it floated over the rows as they
                // scrolled under it).
                HStack(alignment: .center) {
                    Text("Account").font(.display(34)).tracking(-1)
                    Spacer()
                    DoneButton()
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 0))
                // The plan: Go Pro, or that Pro is on (test mode).
                Section {
                    ProAccountCard().padding(.vertical, 6)
                }
                .listRowBackground(rowFill)
                Section {
                    if signedIn {
                        HStack(spacing: 12) {
                            tile("person.fill", Theme.lime)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Signed in as").font(.geist(12)).foregroundStyle(Theme.muted)
                                Text(email ?? "—").font(.geist(15, .medium)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        .padding(.vertical, 2)
                    } else {
                        // Trying the demo without an account.
                        Text("You're looking at a demo. Sign in to track your own\u{00A0}collection.").foregroundStyle(Theme.muted)
                        Button { Onboarding.shared.tryingDemo = false } label: { iconRow("person.crop.circle.badge.plus", Theme.lime, "Sign in") }
                    }
                } header: {
                    SectionTitle("Account")
                }
                .listRowBackground(rowFill)
                // Settings that live on other screens, gathered here with their current values.
                Section {
                    Button { dealSettings = true } label: { iconRow("arrow.left.arrow.right", Theme.purple, "Deal", value: deals.role.title) }
                    HStack(spacing: 12) {
                        tile("camera.viewfinder", Theme.blue)
                        Picker(selection: $scanGame) {
                            ForEach(ScanGame.allCases) { Text($0.title).tag($0.rawValue) }
                        } label: { Text("Scanner game").foregroundStyle(.white) }
                        .tint(Theme.muted)
                    }
                    Button { gradingCosts = true } label: {
                        iconRow("checkmark.seal", Theme.lime, "Grading costs", value: Format.money(grading.costs.fee + grading.costs.shipping) + " a card")
                    }
                    Button {
                        budgetText = store.monthlyBudget.map { String(format: "%.0f", $0) } ?? ""
                        editingBudget = true
                    } label: { iconRow("wallet.pass", Theme.blue, "Monthly budget", value: store.monthlyBudget.map { Format.money($0) } ?? "None") }
                } header: {
                    SectionTitle("Preferences")
                }
                .listRowBackground(rowFill)
                Section {
                    if notifyStatus == .denied {
                        // The switches can't do anything until iOS allows Corodex's notifications.
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notifications are off for Corodex in your iPhone's Settings, so none of these will\u{00A0}arrive.")
                                .font(.geist(14)).foregroundStyle(.white)
                            Button("Open iPhone Settings") {
                                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                            }
                            .font(.geist(14, .semibold)).foregroundStyle(Theme.lime)
                        }
                        .padding(.vertical, 4)
                    }
                    notifyToggle("target", Theme.lime, "Price targets", "A card you watch hits your target price", \.priceTargets)
                    notifyToggle("chart.line.uptrend.xyaxis", Theme.blue, "Big moves", "One of your cards moves 15% in a day", \.bigMoves)
                    notifyToggle("flag.checkered", Theme.purple, "Milestones", "Your collection passes a new high, or a card doubles", \.milestones)
                    notifyToggle("square.grid.3x3.fill", Theme.lime, "Sets nearly done", "Sundays, when a set is 1 to 5 cards from finished", \.nearlyDone)
                    notifyToggle("calendar", Theme.blue, "Weekly recap", "Sundays at 6pm, your week in Corodex", \.weeklyRecap)
                    if notifyStatus == .authorized || notifyStatus == .provisional {
                        Button {
                            Task { await sendTest() }
                        } label: {
                            iconRow("bell.badge", Theme.purple, testing ? "Sending…" : "Send a test notification", chevron: false)
                        }
                        .disabled(testing)
                        if let testResult {
                            Text(testResult).font(.geist(13)).foregroundStyle(Theme.muted)
                        }
                    }
                } header: {
                    SectionTitle("Notifications")
                } footer: {
                    SectionNote("Price targets, big moves, milestones and sets arrive after the daily price check.")
                }
                .listRowBackground(rowFill)
                Section {
                    ShareLink(item: ExportFile(transactions: store.transactions, watchlist: store.watchlist, products: store.products,
                                               mode: store.demo == nil ? "cloud" : "demo"),
                              preview: SharePreview("Corodex export")) {
                        iconRow("square.and.arrow.up", Theme.lime, "Export your data", chevron: false)
                    }
                    if signedIn && store.demo == nil {
                        Button { sharing = true } label: { iconRow("link", Theme.blue, "Share your collection") }
                    }
                } header: {
                    SectionTitle("Collection")
                } footer: {
                    SectionNote("Export saves everything as a file, the same as the website's export. Share makes a read-only link you can turn off any time.")
                }
                .listRowBackground(rowFill)
                Section {
                    HStack(spacing: 12) {
                        tile("photo.stack", Theme.purple)
                        Picker(selection: $demo) {
                            Text("My collection").tag(DemoKind?.none)
                            ForEach(DemoKind.allCases) { kind in Text("Demo: \(kind.title)").tag(DemoKind?.some(kind)) }
                        } label: { Text("Show").foregroundStyle(.white) }
                        .tint(Theme.muted)
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
                    SectionNote("A made-up collection to try things with: sealed only, singles only, singles with graded slabs, or a mix. Nothing in a demo is saved.")
                }
                .listRowBackground(rowFill)
                Section {
                    NavigationLink { NumbersExplained() } label: { iconRow("function", Theme.lime, "How the numbers work", chevron: false) }
                    if !AppConfig.supportEmail.isEmpty, let url = contactURL {
                        Link(destination: url) { iconRow("envelope", Theme.blue, "Contact us", external: true) }
                    }
                    Link(destination: AppConfig.apiBaseURL) { iconRow("globe", Theme.purple, "Open Corodex on the web", external: true) }
                } header: {
                    SectionTitle("Help")
                } footer: {
                    SectionNote("Your collection syncs with the website.")
                }
                .listRowBackground(rowFill)
                Section {
                    Link(destination: AppConfig.apiBaseURL.appendingPathComponent("privacy")) { iconRow("hand.raised", Theme.blue, "Privacy", external: true) }
                    Link(destination: AppConfig.apiBaseURL.appendingPathComponent("terms")) { iconRow("doc.text", Theme.purple, "Terms", external: true) }
                } header: {
                    SectionTitle("About")
                }
                .listRowBackground(rowFill)
                // Test-photo mode: measure our own scanner against CardSight (a tool, so last).
                Section {
                    Toggle(isOn: Binding(get: { scanTests }, set: { on in scanTests = on; ScanTestLog.isOn = on })) {
                        HStack(spacing: 12) {
                            tile("camera.metering.matrix", Theme.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Save scan test photos").foregroundStyle(.white)
                                Text("Kept in Files → Corodex → Scan tests, read by both scanners").font(.geist(12)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .tint(Theme.lime)
                    if scanTests || testSummary.scans > 0 {
                        let s = testSummary
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(s.scans) test scans").font(.geist(15, .semibold))
                            Text("Phone sure on \(s.phoneSure) · agreed with CardSight on \(s.agreed), disagreed on \(s.disagreed)")
                                .font(.geist(13)).foregroundStyle(Theme.muted)
                            if s.phoneSure > 0, s.cardSightCount > 0 {
                                Text(String(format: "Phone %.2fs a scan · CardSight %.2fs", s.phoneSeconds / Double(s.phoneSure), s.cardSightSeconds / Double(s.cardSightCount)))
                                    .font(.geist(13)).foregroundStyle(Theme.muted).monospacedDigit()
                            }
                        }
                        .padding(.vertical, 2)
                        Button { ScanTestLog.clear(); testSummary = .init() } label: {
                            Text("Delete test photos").font(.geist(15, .semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .dangerStyle(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    SectionTitle("Scanner tests")
                }
                .listRowBackground(rowFill)
                .task { testSummary = await Task.detached { ScanTestLog.loadSummary() }.value }
                // Leaving, last: sign out (glass) and delete (pink, our one remove look), then the version.
                if signedIn {
                    VStack(spacing: 10) {
                        Button { confirming = true } label: {
                            Text("Sign out").font(.geist(16, .semibold)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .liquidGlass(in: Capsule(), interactive: true)
                        }
                        .buttonStyle(.plain)
                        Button { deletingAccount = true } label: {
                            Text("Delete account").font(.geist(16, .semibold))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .dangerStyle(Capsule())
                        }
                        .buttonStyle(.plain)
                        if let deleteError { Text(deleteError).font(.geist(13)).foregroundStyle(Theme.muted) }
                        Text("Corodex \(versionText)").font(.mono(11)).tracking(0.6).foregroundStyle(Theme.subtle)
                            .padding(.top, 8)
                    }
                    .padding(.top, 12)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 24, trailing: 0))
                } else {
                    Text("Corodex \(versionText)").font(.mono(11)).tracking(0.6).foregroundStyle(Theme.subtle)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .alert("Sign out of Corodex?", isPresented: $confirming) {
                Button("Cancel", role: .cancel) {}
                Button("Sign out", role: .destructive) {
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
                Text("What you plan to spend a month. Summary shows how much is\u{00A0}left.")
            }
            .alert("Delete your account?", isPresented: $deletingAccount) {
                Button("Cancel", role: .cancel) {}
                Button("Delete everything", role: .destructive) { Task { await deleteAccount() } }
            } message: {
                Text("This permanently removes your account and everything in it: your collection, lists, deals and settings, on the app and the website. It can't be undone. Export your data first if you want a\u{00A0}copy.")
            }
        }
    }

    /// The rows' panel: a faint white fill (not the system's grey cells).
    private var rowFill: Color { Color.white.opacity(0.06) }

    /// A small rounded tile with a symbol in one of the app's colours (lime, blue, purple).
    private func tile(_ icon: String, _ tint: Color) -> some View {
        Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.16)))
    }

    /// A row: icon tile, white name, the current value quiet on the right, and a chevron (or ↗
    /// for a link that leaves the app).
    private func iconRow(_ icon: String, _ tint: Color, _ title: String, value: String? = nil, chevron: Bool = true, external: Bool = false) -> some View {
        HStack(spacing: 12) {
            tile(icon, tint)
            Text(title).font(.geist(16)).foregroundStyle(.white)
            Spacer(minLength: 8)
            if let value { Text(value).font(.geist(15)).foregroundStyle(Theme.muted).lineLimit(1) }
            if external {
                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.subtle)
            } else if chevron {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.subtle)
            }
        }
        .contentShape(Rectangle())
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
        c.queryItems = [URLQueryItem(name: "subject", value: "Corodex \(versionText)")]
        return c.url
    }

    private func deleteAccount() async {
        deleteError = nil
        do {
            try await Backend.shared.api.deleteAccount()
            await session.signOut()
        } catch {
            deleteError = error.localizedDescription
        }
    }

    /// A notification kind's switch: its name, and a line on when it comes.
    private func notifyToggle(_ icon: String, _ tint: Color, _ title: String, _ note: String, _ key: WritableKeyPath<NotificationPrefs, Bool>) -> some View {
        Toggle(isOn: Binding(get: { prefs[keyPath: key] }, set: { on in
            prefs[keyPath: key] = on
            Task { await savePrefs() }
        })) {
            HStack(spacing: 12) {
                tile(icon, tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.white)
                    Text(note).font(.geist(12)).foregroundStyle(Theme.muted)
                }
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
            testResult = "This phone isn't registered yet. Check notifications are allowed for Corodex in Settings, then try again."
        } catch {
            testResult = error.localizedDescription
        }
    }
}

/// Closes a sheet; hidden when the view isn't presented as one.
private struct DoneButton: View {
    @Environment(\.dismiss) private var dismiss

    // Account only ever opens as a sheet (Home's and Summary's menus). Inside the list,
    // `isPresented` read false and hid the button.
    var body: some View {
        Button { dismiss() } label: {
            Text("Done").font(.geist(15, .semibold)).foregroundStyle(Theme.lime)
                .padding(.horizontal, 16).frame(height: 38)
                .liquidGlass(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
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
                        Text("Anyone with the link sees your cards and their value. Never your email, notes or where you bought\u{00A0}things.").font(.geist(13)).foregroundStyle(Theme.muted)
                    }
                } else if !loading {
                    Section {
                        Button("Create a link") { Task { await create() } }
                    } footer: {
                        Text("A read-only page anyone with the link can open, no sign-in needed. You can turn it off any\u{00A0}time.").font(.geist(13)).foregroundStyle(Theme.muted)
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
