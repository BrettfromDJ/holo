import SwiftUI

/// Collection's sort and filters in one bottom sheet: sort, show and type, with Reset and Done
/// always in reach.
struct CollectionFilterSheet: View {
    @Binding var sort: CollectionView.Sort
    @Binding var perf: CollectionView.Perf
    @Binding var setFilter: String?
    @Binding var typeFilter: String?
    var sets: [String]
    var types: [String]
    /// How many of your holdings are in each set, for the set list.
    var setCounts: [String: Int]
    @Environment(\.dismiss) private var dismiss

    private var filtersOn: Bool { setFilter != nil || typeFilter != nil || perf != .all || sort != .value }

    /// The options' height, measured, so the sheet fits them exactly.
    @State private var contentHeight: CGFloat = 420

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sort & filter").font(.geist(17, .semibold)).foregroundStyle(.white)
                Spacer()
                Button { Haptics.tap(); dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    section("Sort by") {
                        FlowChips(options: CollectionView.Sort.allCases.map { ($0, $0.rawValue) }, selection: $sort)
                    }
                    section("Show") {
                        FlowChips(options: CollectionView.Perf.allCases.map { ($0, $0.rawValue) }, selection: $perf)
                    }
                    if !types.isEmpty {
                        section("Type") {
                            FlowChips(options: [(String?.none, "All types")] + types.map { (String?.some($0), $0) }, selection: $typeFilter)
                        }
                    }
                    // (The set search and set list were removed: the owner's call.)
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollDismissesKeyboard(.immediately)
            .scrollBounceBehavior(.basedOnSize)

            // Always in reach.
            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    withAnimation(.snappy(duration: 0.2)) { sort = .value; perf = .all; setFilter = nil; typeFilter = nil }
                } label: {
                    Text("Reset").font(.geist(16, .semibold)).foregroundStyle(filtersOn ? .white : Theme.subtle)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .liquidGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
                .disabled(!filtersOn)
                Button { Haptics.tap(); dismiss() } label: {
                    Text("Done").font(.geist(16, .semibold)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Capsule().fill(Theme.lime))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)
        }
        // One height, just what it holds (nothing more to drag up to): the header, the options
        // and the buttons; it scrolls only if there are too many types to fit.
        .presentationDetents([.height(min(64 + contentHeight + 74, 720))])
        .presentationDragIndicator(.visible)
        .glassSheet()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(text: title)
            content()
        }
    }
}

/// Chips that wrap onto as many lines as they need (the app's glass chips, the chosen one white).
private struct FlowChips<T: Hashable>: View {
    var options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        Flow(spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                // The app's chips: rounded Liquid Glass tiles, the chosen one white.
                Chip(title: option.1, selected: selection == option.0) {
                    withAnimation(.snappy(duration: 0.15)) { selection = option.0 }
                }
            }
        }
    }
}

/// Lays children left to right, wrapping to a new line when the next one won't fit.
private struct Flow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += line + spacing; line = 0 }
            x += s.width + spacing
            line = max(line, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            line = max(line, s.height)
        }
    }
}
