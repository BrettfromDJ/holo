import SwiftUI

/// Our own action menus, in place of Apple's pop-up menus (which lagged and clipped): a small
/// black sheet led by the card (its picture, name and set), the main actions as a row of square
/// glass tiles, then the rest grouped into glass panels with hairlines between rows. Rows can
/// open a second page (lists, portfolios, a copy to pick), with a round back button.

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
    /// A "make something new" row: no glass, just a thin light outline, so it stands apart.
    var outlined = false
    /// Opens a second page with these rows.
    var children: [[SheetAction]]? = nil
    /// Shares this link (the system share sheet).
    var share: URL? = nil
    /// What it does. Runs once the sheet has closed, so it may open another sheet.
    var run: (() -> Void)? = nil
}

struct ActionsSheet: View {
    var title: String?
    /// The card it's about, for the header (its picture, name and set).
    var product: Product? = nil
    var groups: [[SheetAction]]
    @Environment(\.dismiss) private var dismiss
    @State private var page: (title: String, groups: [[SheetAction]])?

    var body: some View {
        let shown = page?.groups ?? groups
        VStack(alignment: .leading, spacing: 16) {
            header
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { i, section in
                        if page == nil && i == 0 && Self.isTiles(section) {
                            tiles(section)
                        } else {
                            panel(section)
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 12)
        .presentationDetents([.height(height(shown))])
        .presentationDragIndicator(.visible)
        .presentationBackground(.black)
        .animation(.snappy(duration: 0.22), value: page?.title)
        .glassSheet()
    }

    // MARK: Header

    @ViewBuilder private var header: some View {
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
                Text(page.title).font(.display(20)).tracking(-0.5).foregroundStyle(.white).lineLimit(1)
            }
        } else if let product {
            HStack(spacing: 14) {
                ProductImage(product: product, cornerRadius: 5).frame(width: 46, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(product.name).font(.display(18)).tracking(-0.4).foregroundStyle(.white).lineLimit(2)
                    if let set = product.setName { Text(set).font(.geist(13)).foregroundStyle(Theme.muted).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
        } else if let title {
            Text(title).font(.display(20)).tracking(-0.5).foregroundStyle(.white).lineLimit(2)
        }
    }

    /// The first section shows as tiles when it's 2–4 plain actions (no lines under, no pages).
    static func isTiles(_ section: [SheetAction]) -> Bool {
        (2...4).contains(section.count) && section.allSatisfy { $0.icon != nil && $0.subtitle == nil && $0.children == nil && $0.share == nil && !$0.checked && !$0.outlined }
    }

    /// Room for the header and every row, up to most of the screen (it scrolls past that).
    private func height(_ groups: [[SheetAction]]) -> CGFloat {
        var h: CGFloat = 26 + 12 + 40   // top, bottom, the grabber's room
        if page != nil { h += 48 } else if product != nil { h += 80 } else if title != nil { h += 44 }
        for (i, section) in groups.enumerated() {
            if page == nil && i == 0 && Self.isTiles(section) { h += 84 } else {
                h += section.reduce(0) { $0 + ($1.subtitle == nil ? 52 : 62) }
            }
            h += 12
        }
        return min(h, 660)
    }

    // MARK: Sections

    /// The main actions side by side: an icon over a short label, each its own glass tile.
    private func tiles(_ section: [SheetAction]) -> some View {
        HStack(spacing: 8) {
            ForEach(section) { action in
                Button { tap(action) } label: {
                    VStack(spacing: 7) {
                        Image(systemName: action.icon ?? "circle").font(.system(size: 19, weight: .medium))
                        Text(action.title).font(.geist(12, .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(action.destructive ? Theme.down : .white)
                    .frame(maxWidth: .infinity).frame(height: 76)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), tint: Color.white.opacity(0.02), interactive: true)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(action.disabled)
            }
        }
    }

    /// A section as one glass panel, its rows split by hairlines (an outlined row stands alone).
    @ViewBuilder private func panel(_ section: [SheetAction]) -> some View {
        let plain = section.filter { !$0.outlined }
        let outlined = section.filter(\.outlined)
        VStack(spacing: 8) {
            if !plain.isEmpty {
                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                VStack(spacing: 0) {
                    ForEach(Array(plain.enumerated()), id: \.element.id) { i, action in
                        if i > 0 { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 50) }
                        row(action)
                    }
                }
                .liquidGlass(in: shape, tint: Color.white.opacity(0.02))
                .overlay(shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
            }
            ForEach(outlined) { action in
                row(action)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
            }
        }
    }

    @ViewBuilder private func row(_ action: SheetAction) -> some View {
        if let url = action.share {
            ShareLink(item: url) { ActionRowLabel(action: action) }
                .buttonStyle(.plain)
        } else {
            Button { tap(action) } label: { ActionRowLabel(action: action) }
                .buttonStyle(.plain)
                .disabled(action.disabled)
                .opacity(action.disabled ? 0.45 : 1)
        }
    }

    private func tap(_ action: SheetAction) {
        Haptics.tap()
        if let children = action.children {
            withAnimation(.snappy(duration: 0.22)) { page = (action.title, children) }
        } else {
            dismiss()
            // After the sheet has gone, so an action that opens another sheet can.
            if let run = action.run { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { run() } }
        }
    }
}

/// A row inside a panel: icon, title (and a quiet line under it), a check or a ›.
struct ActionRowLabel: View {
    var action: SheetAction

    var body: some View {
        let tint: Color = action.destructive ? Theme.down : .white
        HStack(spacing: 14) {
            if let icon = action.icon {
                Image(systemName: icon).font(.system(size: 16, weight: .medium))
                    .foregroundStyle(action.destructive ? Theme.down : Color.white.opacity(0.8))
                    .frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title).font(.geist(16, .medium)).foregroundStyle(tint).lineLimit(1)
                if let sub = action.subtitle {
                    Text(sub).font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if action.checked { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.lime) }
            if action.children != nil { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.subtle) }
        }
        .padding(.horizontal, 14)
        .frame(height: action.subtitle == nil ? 52 : 62)
        .contentShape(Rectangle())
    }
}

extension View {
    /// Our action sheet, shown while `isPresented`; the rows are built when it opens.
    func actionsSheet(isPresented: Binding<Bool>, title: String? = nil, product: Product? = nil, actions: @escaping () -> [[SheetAction]]) -> some View {
        sheet(isPresented: isPresented) { ActionsSheet(title: title, product: product, groups: actions()) }
    }

    /// Our action sheet for one item (a held card, an entry), shown while `item` is set.
    func actionsSheet<Item: Identifiable>(item: Binding<Item?>, title: @escaping (Item) -> String?, product: @escaping (Item) -> Product? = { _ in nil }, actions: @escaping (Item) -> [[SheetAction]]) -> some View {
        sheet(item: item) { i in ActionsSheet(title: title(i), product: product(i), groups: actions(i)) }
    }
}
