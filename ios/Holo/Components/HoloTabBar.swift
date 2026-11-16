import SwiftUI

/// The bottom bar: Overview, Collection, Search, Explore, Deal, floating on Liquid Glass.
struct HoloTabBar<Tab: Hashable>: View {
    struct Item {
        var tab: Tab
        var title: String
        var icon: String
        /// Some symbols draw larger than others at the same size; this evens them out.
        var iconSize: CGFloat = 21
    }

    var items: [Item]
    @Binding var selection: Tab
    /// The add menu is open: Search turns into a ×.
    var plusOpen = false
    var onPlus: () -> Void
    /// Every tap on a tab, including the one already showing.
    var onTap: (Tab) -> Void = { _ in }
    /// Taps on the tab already showing (back to the top), each one a little lime spark.
    @State private var sparks: [Int: Int] = [:]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.prefix(2).enumerated()), id: \.offset) { _, item in button(item) }
            // Search, a plain item like the rest (a × while the add menu is open).
            Button(action: onPlus) {
                VStack(spacing: 4) {
                    Image(systemName: plusOpen ? "xmark" : "magnifyingglass").font(.system(size: 20, weight: .regular))
                        .foregroundStyle(plusOpen ? .white : Theme.muted)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(height: 26)
                    Text(plusOpen ? "Close" : "Search").font(.geist(11, .medium)).foregroundStyle(plusOpen ? .white : Theme.muted)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(plusOpen ? "Close" : "Search")
            .accessibilityIdentifier("tab-search")
            ForEach(Array(items.suffix(2).enumerated()), id: \.offset) { _, item in button(item) }
        }
        .padding(.horizontal, 6)
        .frame(height: 64)
        .liquidGlass(in: Capsule(), tint: Theme.background.opacity(0.4))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        // A faint hairline edge (no glow).
        .overlay {
            Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1).allowsHitTesting(false)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 2)
        .ignoresSafeArea(.keyboard)
    }

    /// Room to leave under each page so its last card scrolls clear of the bar.
    static var clearance: CGFloat { 96 }

    private func button(_ item: Item) -> some View {
        let on = selection == item.tab
        let key = item.tab.hashValue
        return Button {
            if on { sparks[key, default: 0] += 1 }
            selection = item.tab
            onTap(item.tab)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: item.icon).font(.system(size: item.iconSize, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? Theme.lime : Theme.muted)
                    .frame(height: 26)
                    .overlay {
                        SparkBurst(trigger: sparks[key] ?? 0, count: 10, spread: 22)
                            .frame(width: 70, height: 70)
                    }
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
