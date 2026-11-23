import SwiftUI

/// Home is about what's happening across the hobby (`MarketHomeView`); Collection has a
/// Summary | Cards switch at the top: Summary is what Overview showed (`HomeView`), Cards is the
/// grid (`CollectionView`). The switch's choice is kept on the phone.
enum CollectionMode {
    static let key = "collection-mode"

    /// Screenshot and speed runs (`-HoloDemo`) set it every launch, so one test's choice never
    /// carries into the next (the simulator keeps settings between launches):
    /// `-HoloCollectionMode summary|cards` if given; Summary for `-HoloPage` (its pages open from
    /// Summary's menu); Cards for `-HoloTab collection` (the grid); else Summary.
    static func applyLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-HoloDemo") else { return }
        let mode = Demo.value("-HoloCollectionMode")
            ?? (Demo.value("-HoloPage") != nil ? "summary" : Demo.value("-HoloTab") == "collection" ? "cards" : "summary")
        UserDefaults.standard.set(mode, forKey: key)
    }
}

/// The Collection tab: Summary (what Overview showed) or Cards (the grid).
struct CollectionTabRoot: View {
    var onScan: () -> Void
    @AppStorage(CollectionMode.key) private var mode = "summary"

    var body: some View {
        if mode == "summary" { HomeView(onScan: onScan) } else { CollectionView(onScan: onScan) }
    }
}

/// Summary and Cards as two big titles at the top of the page, like Home's title (the one
/// you're on white, the other faded; tap to switch), with the page's own buttons on the right.
struct CollectionTitles<Trailing: View>: View {
    @AppStorage(CollectionMode.key) private var mode = "summary"
    var trailing: Trailing

    init(@ViewBuilder trailing: () -> Trailing) { self.trailing = trailing() }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            ForEach([("summary", "Summary"), ("cards", "Cards")], id: \.0) { value, title in
                let on = mode == value
                Button { if !on { mode = value } } label: {
                    Text(title).font(.display(32)).tracking(32 * -0.03)
                        .foregroundStyle(on ? Color.white : Theme.subtle)
                        .displayTrim(32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Spacer(minLength: 8)
            trailing
        }
        .frame(minHeight: 44)
        .padding(.top, 4)
        .sensoryFeedback(.selection, trigger: mode)
    }
}

extension CollectionTitles where Trailing == EmptyView {
    init() { self.trailing = EmptyView() }
}

extension View {
    /// Collection's top: no bar (the Summary / Cards titles are in the page, like Home's).
    func collectionPageTitle() -> some View {
        toolbar(.hidden, for: .navigationBar)
    }
}
