import SwiftUI

struct SettingsView: View {
    @Environment(SessionModel.self) private var session
    @Environment(CollectionStore.self) private var store
    @State private var confirming = false

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
                Section("Collection") {
                    LabeledContent("Items", value: "\(Int(store.summary.items))")
                    LabeledContent("Value", value: Format.money(store.summary.value))
                    LabeledContent("Realized gains", value: Format.signedMoney(store.summary.realized))
                }
                Section {
                    Link("Open Holo on the web", destination: AppConfig.apiBaseURL)
                } footer: {
                    Text("Your collection syncs with the website. Selling, shelves, grading and deals are on the web for now.")
                }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Account")
            .confirmationDialog("Sign out of Holo?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { Task { await session.signOut() } }
            }
        }
    }
}
