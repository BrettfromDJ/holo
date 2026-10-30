import SwiftUI

/// A product's picture, or a card / box silhouette while it loads or when there is none.
struct ProductImage: View {
    var product: Product?
    var cornerRadius: CGFloat = 8

    var body: some View {
        AsyncImage(url: product?.imageURL) { phase in
            switch phase {
            case let .success(image):
                image.resizable().aspectRatio(contentMode: .fit)
            default:
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.surface2)
            .aspectRatio(63.0 / 88.0, contentMode: .fit)
            .overlay(
                Image(systemName: product?.isSealed == true ? "shippingbox" : "rectangle.portrait")
                    .font(.title3)
                    .foregroundStyle(Theme.lime.opacity(0.7))
            )
    }
}

/// A small tinted label for a condition or grade.
struct Tag: View {
    var text: String
    var tint: Color = Theme.muted

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.16), in: Capsule())
    }
}
