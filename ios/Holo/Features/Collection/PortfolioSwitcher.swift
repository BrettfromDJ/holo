import SwiftUI

/// All portfolios, Main, or one of yours: filters every number in the app (Summary, Cards,
/// Analytics), like the website's switcher. Sits on Summary just above the worth; opens our action sheet
/// with the portfolios, New portfolio (named right in the sheet), Lists and portfolios, and
/// rename / delete for one of yours.
struct PortfolioSwitcher: View {
    @Environment(CollectionStore.self) private var store
    @Environment(GroupsStore.self) private var groups
    @State private var open = false
    @State private var managing = false
    @State private var renaming: String?
    @State private var name = ""
    @State private var proPaywall: ProReason?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 4) {
            Button { Haptics.tap(); open = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                    Text(groups.name(of: groups.selected)).font(.geist(14, .medium)).foregroundStyle(.white).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .liquidGlass(in: Capsule(), interactive: true)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Portfolio: \(groups.name(of: groups.selected))")
            if let error { Text(error).font(.geist(12)).foregroundStyle(Theme.muted) }
        }
        .actionsSheet(isPresented: $open, title: "Portfolio") { actions }
        .sheet(isPresented: $managing) { ManageGroupsSheet(onClearShelf: { _ in }) }
        .proPaywall($proPaywall)
        .alert("Rename portfolio", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) { name = "" }
            Button("Save") {
                let value = String(name.trimmingCharacters(in: .whitespaces).prefix(40))
                if let id = renaming, !value.isEmpty { run { try await groups.renamePortfolio(id, to: value) } }
                renaming = nil
                name = ""
            }
        }
    }

    private var actions: [[SheetAction]] {
        let options: [(String, String)] = [(GroupsStore.all, "All portfolios"), (GroupsStore.main, "Main")] + groups.portfolios.map { ($0.id, $0.name) }
        let pick = options.map { id, title in
            SheetAction(title: title, checked: groups.selected == id) { groups.select(id, store: store) }
        }
        var more: [SheetAction] = [
            SheetAction(title: "Lists and portfolios", icon: "slider.horizontal.3") { managing = true },
        ]
        if groups.portfolios.contains(where: { $0.id == groups.selected }) {
            let id = groups.selected
            more.append(SheetAction(title: "Rename portfolio", icon: "pencil") { name = groups.name(of: id); renaming = id })
            more.append(SheetAction(title: "Delete portfolio", subtitle: "Its cards go back to Main", icon: "trash", destructive: true) {
                run { try await groups.removePortfolio(id, store: store) }
            })
        }
        if Pro.shared.unlocked {
            more.append(SheetAction(title: "New portfolio", icon: "plus", outlined: true, onCreate: { name in
                run { try await groups.createPortfolio(name, store: store) }
            }, namePrompt: "Portfolio name"))
        } else {
            more.append(SheetAction(title: "New portfolio", icon: "plus", outlined: true) { proPaywall = .portfolios })
        }
        return [pick, more]
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task { @MainActor in
            do { error = nil; try await work() } catch { self.error = error.localizedDescription }
        }
    }
}
