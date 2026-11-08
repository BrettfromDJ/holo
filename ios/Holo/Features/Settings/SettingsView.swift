import SwiftUI

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
                    } else {
                        // Trying the demo without an account.
                        Text("You're looking at a demo. Sign in to track your own collection.").foregroundStyle(Theme.muted)
                        Button("Sign in") { Onboarding.shared.tryingDemo = false }
                    }
                } header: {
                    SectionTitle("Account")
                }
                Section {
                    notifyToggle("Price targets", "A card you watch hits your target price", \.priceTargets)
                    notifyToggle("Big moves", "One of your cards moves 15% in a day", \.bigMoves)
                    notifyToggle("Milestones", "Your collection passes a new high, or a card doubles", \.milestones)
                    notifyToggle("Sets nearly done", "Sundays, when a set is 1 to 5 cards from finished", \.nearlyDone)
                    notifyToggle("Weekly recap", "Sundays at 6pm, your week in Lucent", \.weeklyRecap)
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
                } header: {
                    SectionTitle("Notifications")
                } footer: {
                    SectionNote("Price targets, big moves, milestones and sets arrive after the daily price check.")
                }
                Section {
                    Button("Welcome pages") { showingWelcome = true }
                } header: {
                    SectionTitle("Onboarding")
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
                Section {
                    LabeledContent("Items", value: "\(Int(store.summary.items))")
                    LabeledContent("Value", value: Format.money(store.summary.value))
                    LabeledContent("Realized gains", value: Format.signedMoney(store.summary.realized))
                    ShareLink(item: ExportFile(transactions: store.transactions, watchlist: store.watchlist, products: store.products,
                                               mode: store.demo == nil ? "cloud" : "demo"),
                              preview: SharePreview("Lucent export")) {
                        Label("Export your data", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    SectionTitle("Collection")
                } footer: {
                    SectionNote("Export saves your purchases, sales, edits, watchlist and the products they refer to as a JSON file, the same as the website's export.")
                }
                Section {
                    explainer("Cost basis", "is what you actually paid for items you still hold: unit price plus allocated shipping, fees and tax. Sales use first-in, first-out lots.")
                    explainer("Unrealized gain", "is market value minus cost basis. Items without a market price are left out rather than counted as $0.")
                    explainer("Daily change", "only measures price movement on items you held at the previous close. Buying a $1,000 box worth $1,000 adds $1,000 of value and $0 of gain.")
                    explainer("Performance %", "is a time-weighted return: daily market returns are chained together, so adding or selling inventory never distorts it.")
                } header: {
                    SectionTitle("How performance is calculated")
                }
                Section {
                    Link("Open Lucent on the web", destination: AppConfig.apiBaseURL)
                } footer: {
                    SectionNote("Your collection syncs with the website.")
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                } header: {
                    SectionTitle("About")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Account")
            .toolbarBackground(.hidden, for: .navigationBar)
            .clearTopEdge()
            .toolbar { ToolbarItem(placement: .confirmationAction) { DoneButton() } }
            .alert("Sign out of Lucent?", isPresented: $confirming) {
                Button("Cancel", role: .cancel) {}
                Button("Sign out", role: .destructive) {
                    // Signed out, the welcome pages show again (the ways in, demo included).
                    Onboarding.shared.welcomeSeen = false
                    Task { await session.signOut() }
                }
            }
            .task { await loadPrefs() }
            .fullScreenCover(isPresented: $showingWelcome) {
                // A look at the welcome pages; its buttons just close it here.
                WelcomeView(preview: true, onEmail: { showingWelcome = false }, onDemo: { showingWelcome = false })
            }
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
            testResult = "This phone isn't registered yet. Check notifications are allowed for Lucent in Settings, then try again."
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
