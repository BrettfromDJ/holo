import SwiftUI

struct SearchRow: View {
    var hit: SearchHit

    var body: some View {
        HStack(spacing: 12) {
            ProductImage(product: hit.product, cornerRadius: 5).frame(width: 42, height: 58)
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.product.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                Text([hit.gameName, hit.product.setName, hit.product.number.map { "#\($0)" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            Text(Format.money(hit.market)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
    }
}
