import SwiftUI

/// Trying out a new layout (Account → Try the new Home, or `-HoloNewHome` for screenshots):
/// the first tab becomes Home, about what's happening across the hobby (trending cards, hot
/// sealed, new and coming sets), and Collection gets a Summary | Cards switch at the top:
/// Summary is what Overview showed, Cards is the grid.
enum Labs {
    static let newHomeKey = "labs-new-home"
    static let collectionModeKey = "collection-mode"

    /// Screenshots turn it on with a launch argument.
    /// Screenshot runs (`-HoloDemo`) set it every launch, on or off, so one test's choice never
    /// carries into the next (the simulator keeps settings between launches).
    static func applyLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-HoloDemo") else { return }
        UserDefaults.standard.set(args.contains("-HoloNewHome"), forKey: newHomeKey)
        UserDefaults.standard.set(Demo.value("-HoloCollectionMode") ?? "summary", forKey: collectionModeKey)
    }
}

/// The first tab: the new Home when it's on, else Overview.
struct HomeTabRoot: View {
    var onScan: () -> Void
    @AppStorage(Labs.newHomeKey) private var newHome = false

    var body: some View {
        if newHome { MarketHomeView() } else { HomeView(onScan: onScan) }
    }
}

/// The Collection tab: with the new Home on, Summary (what Overview showed) or Cards (the grid).
struct CollectionTabRoot: View {
    var onScan: () -> Void
    @AppStorage(Labs.newHomeKey) private var newHome = false
    @AppStorage(Labs.collectionModeKey) private var mode = "summary"

    var body: some View {
        if newHome && mode == "summary" { HomeView(onScan: onScan) } else { CollectionView(onScan: onScan) }
    }
}

/// Summary | Cards, in the top bar's middle, where the page title sits.
struct CollectionModeSwitch: View {
    @AppStorage(Labs.collectionModeKey) private var mode = "summary"

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
    /// The page title, or, with the new Home on, the Summary | Cards switch in its place.
    @ViewBuilder func collectionPageTitle(_ title: String) -> some View {
        if UserDefaults.standard.bool(forKey: Labs.newHomeKey) {
            pageTitle { CollectionModeSwitch() }
        } else {
            pageTitle(title)
        }
    }
}
