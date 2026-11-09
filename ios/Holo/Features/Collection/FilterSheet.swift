import SwiftUI

/// Collection's sort and filters in one bottom sheet: room for every choice, sets as a list you
/// can search, and Reset and Done always in reach.
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
    @State private var setQuery = ""

    private var filtersOn: Bool { setFilter != nil || typeFilter != nil || perf != .all || sort != .value }

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
                    if !sets.isEmpty { setList }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)

            // Always in reach.
            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    withAnimation(.snappy(duration: 0.2)) { sort = .value; perf = .all; setFilter = nil; typeFilter = nil }
                } label: {
                    Text("Reset").font(.geist(16, .semibold)).foregroundStyle(filtersOn ? .white : Theme.subtle)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .glassSheet()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(text: title)
            content()
        }
    }

    /// Every set you hold cards from, with how many, searchable when there are lots.
    private var setList: some View {
        let q = setQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = q.isEmpty ? sets : sets.filter { $0.lowercased().contains(q) }
        return section("Set") {
            if sets.count > 8 {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Theme.muted)
                    TextField("", text: $setQuery, prompt: Text("Find a set").foregroundColor(Theme.subtle))
                        .font(.geist(15)).foregroundStyle(.white)
                }
                .padding(.horizontal, 14).frame(height: 42)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            VStack(spacing: 0) {
                setRow(nil, "All sets", count: nil)
                ForEach(shown, id: \.self) { s in setRow(s, s, count: setCounts[s]) }
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
        }
    }

    private func setRow(_ value: String?, _ label: String, count: Int?) -> some View {
        let on = setFilter == value
        return Button {
            Haptics.tap()
            withAnimation(.snappy(duration: 0.15)) { setFilter = value }
        } label: {
            HStack(spacing: 10) {
                Text(label).font(.geist(15, on ? .semibold : .regular)).foregroundStyle(.white).lineLimit(2)
                Spacer(minLength: 8)
                if let count { Text("\(count)").font(.geist(13)).monospacedDigit().foregroundStyle(Theme.muted) }
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18)).foregroundStyle(on ? Theme.lime : Color.white.opacity(0.25))
            }
            .padding(.horizontal, 14).frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Chips that wrap onto as many lines as they need (the selected one filled lime).
private struct FlowChips<T: Hashable>: View {
    var options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        Flow(spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = selection == option.0
                Button {
                    Haptics.tap()
                    withAnimation(.snappy(duration: 0.15)) { selection = option.0 }
                } label: {
                    Text(option.1).font(.geist(14, .medium))
                        .foregroundStyle(on ? Theme.ink : .white)
                        .padding(.horizontal, 14).frame(height: 38)
                        .background(Capsule().fill(on ? Theme.lime : Color.white.opacity(0.08)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
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
