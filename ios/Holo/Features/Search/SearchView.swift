import SwiftUI

struct SearchRow: View {
    var hit: SearchHit
    /// Tapping the picture does this instead of the row's own tap (the add sheet opens the card).
    var onArt: (() -> Void)? = nil

    var body: some View {
        // Big art so the printing is easy to tell apart; the name without its repeated number
        // (the lines under it say the set and number), the set, then the game and number quietly.
        HStack(spacing: 14) {
            ProductImage(product: hit.pictured, cornerRadius: 4).frame(width: 64, height: 89)
                .contentShape(Rectangle())
                .highPriorityGesture(TapGesture().onEnded { onArt?() }, including: onArt == nil ? .none : .all)
            VStack(alignment: .leading, spacing: 3) {
                Text(ActionsSheet.shortName(hit.product)).font(.geist(16, .medium)).foregroundStyle(.white).lineLimit(2)
                if let set = hit.product.setName {
                    Text(set).font(.geist(13)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Text([hit.gameName.map(MasterSetsView.shortName), hit.product.number.map { "#\($0)" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.geist(12)).foregroundStyle(Theme.subtle).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Format.money(hit.market)).font(.geist(16, .semibold)).monospacedDigit().foregroundStyle(.white)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
