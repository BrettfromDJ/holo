import SwiftUI

/// A product's picture, or the website's lime line-art silhouette while it loads or when there is none.
struct ProductImage: View {
    var product: Product?
    var cornerRadius: CGFloat = 8
    /// Show the type and set under the silhouette (large tiles).
    var caption = false

    var body: some View {
        AsyncImage(url: product?.imageURL) { phase in
            switch phase {
            case let .success(image):
                image.resizable().aspectRatio(contentMode: .fit)
            default:
                Silhouette(product: product, showCaption: caption)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// A holding's artwork: graded copies sit in a slab with their label, everything else as is.
struct HoldingArt: View {
    var product: Product?
    var identity: HoldingIdentity?
    var cornerRadius: CGFloat = 14
    var caption = true

    var body: some View {
        if let id = identity, id.isGraded, let company = id.gradeCompany, let grade = id.grade {
            SlabFrame(company: company, grade: grade, product: product) {
                ProductImage(product: product, cornerRadius: 4, caption: caption).aspectRatio(63.0 / 88.0, contentMode: .fit)
            }
        } else {
            ProductImage(product: product, cornerRadius: cornerRadius, caption: caption)
        }
    }
}

/// A small tinted label for a condition or grade.
struct Tag: View {
    var text: String
    var tint: Color = Theme.muted

    var body: some View {
        Text(text)
            .font(.geist(11, .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.16), in: Capsule())
    }
}

/// A compact row: picture, name, a detail line, and a figure on the right.
struct MiniRow: View {
    var holding: HoldingView
    var trailing: String
    var tint: Color

    var body: some View {
        HStack(spacing: 12) {
            HoldingArt(product: holding.product, identity: holding.identity, cornerRadius: 6, caption: false).frame(width: 36, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(holding.product?.name ?? "Unknown").font(.geist(15, .medium)).lineLimit(1)
                Text([holding.label, holding.product?.setName].compactMap { $0 }.joined(separator: " · ")).font(.geist(13)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            Text(trailing).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(tint)
        }
        .contentShape(Rectangle())
    }
}
