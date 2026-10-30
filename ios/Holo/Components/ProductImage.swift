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

/// A holding's artwork: graded copies sit in a slab with their label, single cards stand bare,
/// and sealed products sit inside a dark rounded well that fills the space they're given (a
/// card-shaped space makes a card-shaped well), like the website.
struct HoldingArt: View {
    var product: Product?
    var identity: HoldingIdentity?
    var cornerRadius: CGFloat = 14
    var caption = true

    var body: some View {
        if let id = identity, id.isGraded, let company = id.gradeCompany, let grade = id.grade {
            Slab(product: product, company: company, grade: grade)
        } else if product?.isSealed == false, product?.imageURL != nil {
            ProductImage(product: product, cornerRadius: cornerRadius, caption: caption)
        } else {
            SealedWell(product: product, cornerRadius: cornerRadius, caption: caption)
        }
    }
}

/// A sealed product (or anything without a card picture) inside the website's image well.
struct SealedWell: View {
    var product: Product?
    var cornerRadius: CGFloat = 14
    var caption = true

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = max(cornerRadius, side * 0.12)
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.well)
                ProductImage(product: product, cornerRadius: 3, caption: caption)
                    .padding(side * 0.14)
            }
            .frame(width: geo.size.width, height: geo.size.height)
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
