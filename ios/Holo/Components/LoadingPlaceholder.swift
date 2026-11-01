import SwiftUI

/// What a page shows on a first launch, before anything is saved on the phone: a few dim,
/// still shapes roughly where the figures and cards go. No spinner, no shimmer. Later
/// launches open straight on the collection saved last time, so this is rarely seen.
struct LoadingPlaceholder: View {
    enum Layout { case overview, collection }
    var layout: Layout

    private static let fill = Color.white.opacity(0.05)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch layout {
            case .overview:
                // The worth and its change.
                block(width: 140, height: 14)
                block(width: 220, height: 44)
                // The hero.
                block(height: 220, radius: 24)
                // Shortcut row.
                HStack(spacing: 12) {
                    ForEach(0 ..< 4, id: \.self) { _ in block(height: 72, radius: 16) }
                }
                block(height: 160, radius: 20)
            case .collection:
                // Portfolio switcher and the header figures.
                block(width: 160, height: 32, radius: 16)
                block(width: 200, height: 40)
                block(height: 36, radius: 18)
                // Tiles, two across.
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 28) {
                    ForEach(0 ..< 4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 10) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Self.fill).aspectRatio(0.72, contentMode: .fit)
                            block(width: 110, height: 12)
                            block(width: 70, height: 12)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }

    /// A dim rounded block; without a width it fills the row.
    private func block(width: CGFloat? = nil, height: CGFloat, radius: CGFloat = 8) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Self.fill)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? CGFloat.infinity : nil, alignment: .leading)
    }
}
