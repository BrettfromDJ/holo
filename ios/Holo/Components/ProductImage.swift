import ImageIO
import SwiftUI

/// A product's picture, fading in once it has downloaded, or the website's lime line-art
/// silhouette when there is none.
struct ProductImage: View {
    var product: Product?
    var cornerRadius: CGFloat = 8
    /// Show the type and set under the silhouette (large tiles).
    var caption = false

    var body: some View {
        CachedImage(url: product?.imageURL) { image in
            image.resizable().aspectRatio(contentMode: .fit)
        } placeholder: {
            Silhouette(product: product, showCaption: caption)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// A remote picture that's downloaded once and kept in memory. Unlike AsyncImage it shows a
/// picture it already has immediately, so it survives views that redraw every frame (the
/// floating fan, the ticker, the holo card) instead of restarting its download each time.
/// While downloading it leaves the space empty and fades the picture in when it arrives; the
/// placeholder only shows when there's no picture or it couldn't be downloaded.
struct CachedImage<Content: View, Placeholder: View>: View {
    var url: URL?
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder
    /// Long lists set this (`.imageMaxPixel(…)`) so pictures are shrunk to thumbnail size off the
    /// main thread instead of decoding full-size photos while you scroll.
    @Environment(\.imageMaxPixel) private var maxPixel
    @State private var image: UIImage?
    @State private var failed = false

    init(url: URL?, @ViewBuilder content: @escaping (Image) -> Content, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        _image = State(initialValue: url.flatMap { ImageCache.shared.cached($0) })
    }

    var body: some View {
        ZStack {
            if let image = image ?? url.flatMap({ ImageCache.shared.cached($0, maxPixel: maxPixel) }) {
                content(Image(uiImage: image)).transition(.opacity)
            } else if url == nil || failed {
                placeholder()
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            guard let url, image == nil, ImageCache.shared.cached(url, maxPixel: maxPixel) == nil else { return }
            failed = false
            if let loaded = await ImageCache.shared.load(url, maxPixel: maxPixel) {
                withAnimation(.easeOut(duration: 0.3)) { image = loaded }
            } else {
                failed = true
            }
        }
    }
}

/// Downloads each picture once (sharing one download between everything asking for it) and
/// keeps them in memory.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let memory = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private let lock = NSLock()

    init() { memory.countLimit = 400 }

    /// Thumbnails are cached apart from full-size pictures.
    private func key(_ url: URL, _ maxPixel: CGFloat?) -> URL {
        guard let maxPixel else { return url }
        return URL(string: url.absoluteString + "#px\(Int(maxPixel))") ?? url
    }

    func cached(_ url: URL, maxPixel: CGFloat? = nil) -> UIImage? { memory.object(forKey: key(url, maxPixel) as NSURL) }

    func load(_ url: URL, maxPixel: CGFloat? = nil) async -> UIImage? {
        let cacheKey = key(url, maxPixel)
        if let hit = memory.object(forKey: cacheKey as NSURL) { return hit }
        lock.lock()
        let task: Task<UIImage?, Never>
        if let running = inFlight[cacheKey] {
            task = running
        } else {
            task = Task.detached(priority: .userInitiated) {
                if let maxPixel {
                    // Read the file and decode it straight to thumbnail size (ImageIO), never full size.
                    let data: Data?
                    if url.isFileURL { data = try? Data(contentsOf: url) } else { data = try? await URLSession.shared.data(from: url).0 }
                    return data.flatMap { ImageCache.downsample($0, maxPixel: maxPixel) }
                }
                if url.isFileURL { return UIImage(contentsOfFile: url.path) }
                guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
                // Decode here, off the main thread, so scrolling a grid of new pictures stays smooth.
                return await UIImage(data: data)?.byPreparingForDisplay() ?? UIImage(data: data)
            }
            inFlight[cacheKey] = task
        }
        lock.unlock()
        let image = await task.value
        lock.lock()
        inFlight[cacheKey] = nil
        lock.unlock()
        if let image { memory.setObject(image, forKey: cacheKey as NSURL) }
        return image
    }

    /// Decode just a thumbnail: no full-size bitmap is ever made, and it comes out ready to draw.
    static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

private struct ImageMaxPixelKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    /// Pictures below are decoded at most this many pixels on their long side (nil: full size).
    var imageMaxPixel: CGFloat? {
        get { self[ImageMaxPixelKey.self] }
        set { self[ImageMaxPixelKey.self] = newValue }
    }
}

extension View {
    /// Decode the pictures in this view as thumbnails (for long, scrolling lists).
    func imageMaxPixel(_ pixels: CGFloat) -> some View { environment(\.imageMaxPixel, pixels) }
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
