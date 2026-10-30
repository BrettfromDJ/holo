import SwiftUI

/// The website's bottom bar: four tabs around a raised lime + button, floating on Liquid Glass.
struct HoloTabBar<Tab: Hashable>: View {
    struct Item {
        var tab: Tab
        var title: String
        var icon: String
    }

    var items: [Item]
    @Binding var selection: Tab
    var onPlus: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.prefix(2).enumerated()), id: \.offset) { _, item in button(item) }
            // The + sits above the glass (below), so this only holds its place.
            Color.clear.frame(maxWidth: .infinity)
            ForEach(Array(items.suffix(2).enumerated()), id: \.offset) { _, item in button(item) }
        }
        .padding(.horizontal, 6)
        .frame(height: 64)
        .liquidGlass(in: Capsule(), tint: Theme.background.opacity(0.4))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        // Drawn over the bar, not inside the glass, so the bar's edge never shows through it.
        .overlay {
            Button(action: onPlus) {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 64, height: 64)
                    .background(
                        ZStack {
                            Circle().fill(Color(hex: 0x7A9200)).offset(y: 4)
                            Circle().fill(Theme.lime)
                            Circle().fill(LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .center))
                            Sheen(strength: 0.6).clipShape(Circle())
                        }
                        .compositingGroup()
                    )
                    .shadow(color: Theme.lime.opacity(0.4), radius: 12, y: 2)
            }
            .accessibilityLabel("Add")
            .offset(y: -18)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 2)
        .ignoresSafeArea(.keyboard)
    }

    /// Room to leave under each page so its last card scrolls clear of the bar.
    static var clearance: CGFloat { 96 }

    private func button(_ item: Item) -> some View {
        let on = selection == item.tab
        return Button {
            selection = item.tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: item.icon).font(.system(size: 21, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? Theme.lime : Theme.muted)
                    .frame(height: 26)
                Text(item.title).font(.geist(11, .medium)).foregroundStyle(on ? .white : Theme.muted)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// Leaves room under a pushed page's content for the floating tab bar. Root pages get this
    /// from the tab view; a page pushed onto a navigation stack has to ask for it itself.
    func tabBarClearance() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: HoloTabBar<Int>.clearance) }
    }
}
