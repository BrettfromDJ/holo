import SwiftUI

/// The website's bottom bar: four tabs around a raised lime + button.
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
                        }
                    )
                    .shadow(color: Theme.lime.opacity(0.45), radius: 14, y: 2)
            }
            .accessibilityLabel("Add")
            .offset(y: -18)
            .frame(maxWidth: .infinity)
            ForEach(Array(items.suffix(2).enumerated()), id: \.offset) { _, item in button(item) }
        }
        .padding(.horizontal, 8)
        .frame(height: 60)
        .background(
            Theme.background.opacity(0.94)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func button(_ item: Item) -> some View {
        let on = selection == item.tab
        return Button {
            selection = item.tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: item.icon).font(.system(size: 21, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? Theme.lime : Theme.muted)
                Text(item.title).font(.geist(11, .medium)).foregroundStyle(on ? .white : Theme.muted)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
