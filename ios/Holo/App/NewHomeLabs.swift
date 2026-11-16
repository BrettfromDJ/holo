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

/// Summary | Cards, in the top bar's middle, where the page title sits.
struct CollectionModeSwitch: View {
    @AppStorage(CollectionMode.key) private var mode = "summary"

    var body: some View {
        HStack(spacing: 2) {
            ForEach([("summary", "Summary"), ("cards", "Cards")], id: \.0) { value, title in
                let on = mode == value
                Button { mode = value } label: {
                    Text(title).font(.geist(13, on ? .semibold : .medium))
                        .foregroundStyle(on ? Theme.ink : Theme.muted)
                        .padding(.horizontal, 14).frame(height: 30)
                        .background { if on { Capsule().fill(Theme.lime) } }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .liquidGlass(in: Capsule())
        .sensoryFeedback(.selection, trigger: mode)
    }
}

extension View {
    /// Collection's top: the Summary | Cards switch where the page title sits.
    func collectionPageTitle() -> some View {
        pageTitle { CollectionModeSwitch() }
    }
}
