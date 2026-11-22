import SwiftUI

/// Our own action menus: a small black sheet of quiet Liquid Glass rows, in place of Apple's
/// pop-up menus (which lagged and clipped). Rows can open a second page (lists, portfolios,
/// a copy to pick), with a round back button.

/// One row in an `ActionsSheet`.
struct SheetAction: Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String? = nil
    var icon: String? = nil
    /// Shows a check (a list the card is on, the current sort).
    var checked = false
    var destructive = false
    var disabled = false
    /// Opens a second page with these rows.
    var children: [[SheetAction]]? = nil
    /// Shares this link (the system share sheet).
    var share: URL? = nil
    /// What it does. Runs once the sheet has closed, so it may open another sheet.
    var run: (() -> Void)? = nil
}

struct ActionsSheet: View {
    var title: String?
    var groups: [[SheetAction]]
    @Environment(\.dismiss) private var dismiss
    @State private var page: (title: String, groups: [[SheetAction]])?

    var body: some View {
        let shown = page?.groups ?? groups
        VStack(alignment: .leading, spacing: 14) {
            if let page {
                HStack(spacing: 10) {
                    Button {
                        Haptics.tap()
                        withAnimation(.snappy(duration: 0.22)) { self.page = nil }
                    } label: {
                        Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .liquidGlass(in: Circle(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    Text(page.title).font(.display(18)).tracking(-0.4).foregroundStyle(.white).lineLimit(1)
                }
            } else if let title {
                Text(title).font(.display(18)).tracking(-0.4).foregroundStyle(.white).lineLimit(2)
            }
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, section in
                        VStack(spacing: 8) {
                            ForEach(section) { action in row(action) }
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(20)
        .padding(.top, 8)
        .presentationDetents([.height(height(shown))])
        .presentationDragIndicator(.visible)
        .presentationBackground(.black)
        .animation(.snappy(duration: 0.22), value: page?.title)
        .glassSheet()
    }

    /// Room for the heading and every row, up to most of the screen (it scrolls past that).
    private func height(_ groups: [[SheetAction]]) -> CGFloat {
        let rows = groups.reduce(0) { $0 + $1.count }
        let hasHeading = page != nil || title != nil
        let h = 56 + (hasHeading ? 46 : 0) + CGFloat(rows) * 58 + CGFloat(max(0, groups.count - 1)) * 14
        return min(h, 640)
    }

    @ViewBuilder private func row(_ action: SheetAction) -> some View {
        if let url = action.share {
            ShareLink(item: url) { ActionRowLabel(action: action) }
                .buttonStyle(.plain)
        } else {
            Button {
                Haptics.tap()
                if let children = action.children {
                    withAnimation(.snappy(duration: 0.22)) { page = (action.title, children) }
                } else {
                    dismiss()
                    // After the sheet has gone, so an action that opens another sheet can.
                    if let run = action.run { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { run() } }
                }
            } label: { ActionRowLabel(action: action) }
            .buttonStyle(.plain)
            .disabled(action.disabled)
            .opacity(action.disabled ? 0.45 : 1)
        }
    }
}

/// A row's look: icon, title (and a quiet line under it), a check or a ›, on quiet glass.
struct ActionRowLabel: View {
    var action: SheetAction

    var body: some View {
        let tint: Color = action.destructive ? Theme.down : .white
        HStack(spacing: 12) {
            if let icon = action.icon {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(action.title).font(.geist(16, .semibold)).lineLimit(1)
                if let sub = action.subtitle {
                    Text(sub).font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if action.checked { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.lime) }
            if action.children != nil { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.subtle) }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 16)
        .frame(height: 50)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), tint: Color.white.opacity(0.02), interactive: true)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        .contentShape(Rectangle())
    }
}

extension View {
    /// Our action sheet, shown while `isPresented`; the rows are built when it opens.
    func actionsSheet(isPresented: Binding<Bool>, title: String? = nil, actions: @escaping () -> [[SheetAction]]) -> some View {
        sheet(isPresented: isPresented) { ActionsSheet(title: title, groups: actions()) }
    }

    /// Our action sheet for one item (a held card, an entry), shown while `item` is set.
    func actionsSheet<Item: Identifiable>(item: Binding<Item?>, title: @escaping (Item) -> String?, actions: @escaping (Item) -> [[SheetAction]]) -> some View {
        sheet(item: item) { i in ActionsSheet(title: title(i), groups: actions(i)) }
    }
}
