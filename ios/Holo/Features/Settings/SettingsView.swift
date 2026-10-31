import SwiftUI

struct SettingsView: View {
    @Environment(SessionModel.self) private var session
    @Environment(CollectionStore.self) private var store
    @State private var confirming = false
    @State private var testing = false
    @State private var testResult: String?
    @State private var demo: DemoKind? = DemoKind.selected

    private var email: String? {
        if case let .signedIn(_, email) = session.state { return email }
        return nil
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    LabeledContent("Signed in as", value: email ?? "—")
                    Button("Sign out", role: .destructive) { confirming = true }
                }
                Section {
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
                    Text("Notifications")
                } footer: {
                    Text("Price alerts arrive after the daily price check when a watched card is at or below your target.")
                }
                Section {
                    Picker("Show", selection: $demo) {
                        Text("My collection").tag(DemoKind?.none)
                        ForEach(DemoKind.allCases) { kind in Text("Demo: \(kind.title)").tag(DemoKind?.some(kind)) }
                    }
                    .onChange(of: demo) { _, kind in
                        DemoKind.selected = kind
                        Task {
                            if let kind { store.loadDemo(kind) }
                            else if case let .signedIn(userId, _) = session.state { await store.load(userId: userId) }
                        }
                    }
                } header: {
                    Text("Demo collection")
                } footer: {
                    Text("See how the app looks with a made-up collection: sealed only, singles only, singles with graded slabs, or a mix. Prices are made up and nothing you do in a demo is saved. Pick My collection to go back.")
                }
                Section {
                    LabeledContent("Items", value: "\(Int(store.summary.items))")
                    LabeledContent("Value", value: Format.money(store.summary.value))
                    LabeledContent("Realized gains", value: Format.signedMoney(store.summary.realized))
                    ShareLink(item: ExportFile(transactions: store.transactions, watchlist: store.watchlist, products: store.products,
                                               mode: store.demo == nil ? "cloud" : "demo"),
                              preview: SharePreview("Holo export")) {
                        Label("Export your data", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Collection")
                } footer: {
                    Text("Export saves your purchases, sales, edits, watchlist and the products they refer to as a JSON file, the same as the website's export.")
                }
                Section("How performance is calculated") {
                    explainer("Cost basis", "is what you actually paid for items you still hold: unit price plus allocated shipping, fees and tax. Sales use first-in, first-out lots.")
                    explainer("Unrealized gain", "is market value minus cost basis. Items without a market price are left out rather than counted as $0.")
                    explainer("Daily change", "only measures price movement on items you held at the previous close. Buying a $1,000 box worth $1,000 adds $1,000 of value and $0 of gain.")
                    explainer("Performance %", "is a time-weighted return: daily market returns are chained together, so adding or selling inventory never distorts it.")
                }
                Section {
                    Link("Open Holo on the web", destination: AppConfig.apiBaseURL)
                } footer: {
                    Text("Your collection syncs with the website.")
                }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Account")
            .toolbar { ToolbarItem(placement: .confirmationAction) { DoneButton() } }
            .confirmationDialog("Sign out of Holo?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { Task { await session.signOut() } }
            }
        }
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
            testResult = "This phone isn't registered yet. Check notifications are allowed for Holo in Settings, then try again."
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
