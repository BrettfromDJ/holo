import Charts
import PhotosUI
import Supabase
import SwiftUI
import UIKit

// MARK: - Photos

/// Photos that document a deal. Signed in, they're stored privately under your account in the
/// `deal-photos` bucket (path "<user id>/<file>.jpg"); in a demo they stay on the phone ("local:<file>").
enum DealPhotos {
    static let bucket = "deal-photos"
    private static let cache = NSCache<NSString, UIImage>()

    private static var localDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DealPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Shrink to at most 1600px on the long side and store it; returns the photo's path.
    static func save(_ image: UIImage, accountId: String?) async throws -> String {
        let small = resized(image, maxSide: 1600)
        guard let data = small.jpegData(compressionQuality: 0.72) else { throw CocoaError(.fileWriteUnknown) }
        let name = "\(UUID().uuidString.lowercased()).jpg"
        let path: String
        if let accountId {
            path = "\(accountId)/\(name)"
            _ = try await Backend.shared.supabase.storage.from(bucket).upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
        } else {
            path = "local:\(name)"
            try data.write(to: localDir.appendingPathComponent(name))
        }
        cache.setObject(small, forKey: path as NSString)
        return path
    }

    static func load(_ path: String) async -> UIImage? {
        if let hit = cache.object(forKey: path as NSString) { return hit }
        let data: Data?
        if path.hasPrefix("local:") {
            data = try? Data(contentsOf: localDir.appendingPathComponent(String(path.dropFirst(6))))
        } else {
            data = try? await Backend.shared.supabase.storage.from(bucket).download(path: path)
        }
        guard let data, let image = UIImage(data: data) else { return nil }
        let ready = await image.byPreparingForDisplay() ?? image
        cache.setObject(ready, forKey: path as NSString)
        return ready
    }

    static func delete(_ path: String) async {
        cache.removeObject(forKey: path as NSString)
        if path.hasPrefix("local:") {
            try? FileManager.default.removeItem(at: localDir.appendingPathComponent(String(path.dropFirst(6))))
        } else {
            _ = try? await Backend.shared.supabase.storage.from(bucket).remove(paths: [path])
        }
    }

    private static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let side = max(image.size.width, image.size.height)
        guard side > maxSide else { return image }
        let scale = maxSide / side
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

/// One stored photo, filling its frame (cut at the edges) or fitted.
struct DealPhotoImage: View {
    var path: String
    var fill = true
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if fill { Theme.well }
            if let image {
                if fill {
                    Color.clear.overlay { Image(uiImage: image).resizable().scaledToFill() }.clipped()
                } else {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            } else {
                ProgressView().tint(Theme.muted)
            }
        }
        .task(id: path) { image = await DealPhotos.load(path) }
    }
}

/// A row of a deal's photos with a tile to take or attach more; tap one to see it big.
struct DealPhotosStrip: View {
    var photos: [String]
    var accountId: String?
    var accent: Color = Theme.lime
    var onChange: ([String]) -> Void

    @State private var camera = false
    @State private var library = false
    @State private var picks: [PhotosPickerItem] = []
    @State private var uploading = 0
    @State private var viewing: Int?
    @State private var failed = false

    private var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    addTile
                    ForEach(0 ..< uploading, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.well)
                            .frame(width: 84, height: 84)
                            .overlay(ProgressView().tint(Theme.muted))
                    }
                    ForEach(Array(photos.enumerated().reversed()), id: \.element) { i, path in
                        Button { viewing = i } label: {
                            DealPhotoImage(path: path)
                                .frame(width: 84, height: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border))
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.vertical, 2)
            }
            if failed {
                Text("A photo couldn't be saved. Check your connection and try again.").font(.geist(12)).foregroundStyle(Theme.warn)
            }
        }
        .photosPicker(isPresented: $library, selection: $picks, maxSelectionCount: 10, matching: .images)
        .onChange(of: picks) { _, items in
            guard !items.isEmpty else { return }
            picks = []
            Task { await add(items: items) }
        }
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { image in Task { await add(images: [image]) } }.ignoresSafeArea()
        }
        .fullScreenCover(item: Binding(get: { viewing.map(ViewerStart.init) }, set: { viewing = $0?.index })) { start in
            DealPhotoViewer(photos: photos, start: start.index) { path in
                Task { await DealPhotos.delete(path) }
                withAnimation(.snappy) { onChange(photos.filter { $0 != path }) }
            }
        }
    }

    private struct ViewerStart: Identifiable {
        var index: Int
        var id: Int { index }
    }

    @ViewBuilder private var addTile: some View {
        let label = VStack(spacing: 6) {
            Image(systemName: "camera.fill").font(.system(size: 20, weight: .semibold)).foregroundStyle(accent)
            Text("Add photo").font(.geist(11, .semibold)).foregroundStyle(.white)
        }
        .frame(width: 84, height: 84)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
        if hasCamera {
            Menu {
                Button { camera = true } label: { Label("Take photo", systemImage: "camera") }
                Button { library = true } label: { Label("Choose from library", systemImage: "photo.on.rectangle") }
            } label: { label }
        } else {
            Button { library = true } label: { label }.buttonStyle(.plain)
        }
    }

    private func add(items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { images.append(image) }
        }
        await add(images: images)
    }

    @MainActor
    private func add(images: [UIImage]) async {
        guard !images.isEmpty else { return }
        failed = false
        uploading += images.count
        var saved: [String] = []
        for image in images {
            if let path = try? await DealPhotos.save(image, accountId: accountId) { saved.append(path) } else { failed = true }
            uploading -= 1
        }
        if !saved.isEmpty {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.snappy) { onChange(photos + saved) }
        }
    }
}

/// Photos full screen, swipe between them, delete one.
private struct DealPhotoViewer: View {
    var photos: [String]
    var start: Int
    var onDelete: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var confirmDelete = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element) { i, path in
                    DealPhotoImage(path: path, fill: false).tag(i).padding(.vertical, 60)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).frame(width: 40, height: 40).liquidGlass(in: Circle())
                }
                Spacer()
                Text("\(min(index + 1, photos.count)) of \(photos.count)").font(.geist(13, .semibold)).monospacedDigit().foregroundStyle(.white.opacity(0.8))
                Spacer()
                Button { confirmDelete = true } label: {
                    Image(systemName: "trash").font(.system(size: 15, weight: .bold)).frame(width: 40, height: 40).liquidGlass(in: Circle())
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .onAppear { index = start }
        .confirmationDialog("Delete this photo?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete photo", role: .destructive) {
                guard photos.indices.contains(index) else { return }
                onDelete(photos[index])
                dismiss()
            }
        }
    }
}

/// The system camera, for one photo.
private struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - Closed deals

extension DealKind {
    var icon: String {
        switch self {
        case .buy: return "arrow.down.left"
        case .sell: return "arrow.up.right"
        case .trade, .empty: return "arrow.left.arrow.right"
        }
    }

    var color: Color {
        switch self {
        case .buy: return Theme.lime
        case .sell: return Theme.planPink
        case .trade, .empty: return Theme.azure
        }
    }
}

extension DealRecord.Line.Item {
    /// Enough of a product to draw its picture.
    var product: Product { Product(id: id, name: name, setName: setName, productType: productType, kind: kind, imageUrl: imageUrl) }
}

/// Closed deals: totals that count up, profit by day as bars, a filter by kind, then each day's
/// deals as cards (kind, items fanned out, photos, profit). Tap one for everything about it.
struct DealHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DealStore.self) private var deals
    @State private var filter: DealKind? = nil

    private static let filters: [(DealKind?, String)] = [(nil, "All"), (DealKind.buy, "Buys"), (DealKind.sell, "Sales"), (DealKind.trade, "Trades")]

    private var shown: [DealRecord] { filter.map { k in deals.log.filter { $0.kind == k } } ?? deals.log }

    private var days: [(day: String, records: [DealRecord])] {
        let grouped = Dictionary(grouping: shown) { Format.day($0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!.sorted { $0.at > $1.at }) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    if deals.log.isEmpty {
                        empty
                    } else {
                        hero
                        ChipPicker(options: Self.filters, selection: $filter)
                        if days.isEmpty {
                            Text("No \(filter.map { $0.noun.lowercased() } ?? "deal")s yet.").font(.geist(14)).foregroundStyle(Theme.muted)
                        }
                        ForEach(days, id: \.day) { group in daySection(group.day, group.records).reveal() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Theme.background)
            .replaysAnimations()
            .navigationBarTitleDisplayMode(.inline)
            .pageTitle("Closed deals")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(for: DealRecord.self) { DealRecordDetail(recordId: $0.id) }
            .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.lime)
                .frame(width: 72, height: 72).background(Circle().fill(Theme.lime.opacity(0.12)))
            Text("NO CLOSED DEALS YET").font(.display(24))
            Text("Every buy, sale and trade you close shows up here, with what changed hands and your photos.")
                .font(.geist(14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: Totals and the profit chart

    private var hero: some View {
        let profit = shown.compactMap(\.profit).reduce(0, +)
        let cash = shown.reduce(0) { $0 + $1.balance }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                tile("Deals", Double(shown.count), format: { "\(Int($0.rounded()))" }, tint: .white)
                tile("Profit", profit, format: { Format.signedMoney($0) }, tint: Theme.tone(profit))
                tile("Cash", cash, format: { Format.signedMoney($0) }, tint: Theme.tone(cash))
            }
            ProfitBars(records: shown)
        }
        .background(alignment: .top) {
            ZStack {
                GridPattern(step: 36, opacity: 0.05)
                RadialGradient(colors: [Theme.lime.opacity(0.18), .clear], center: UnitPoint(x: 0.2, y: 0.3), startRadius: 0, endRadius: 260)
                RadialGradient(colors: [Theme.planBlue.opacity(0.18), .clear], center: UnitPoint(x: 0.9, y: 0.6), startRadius: 0, endRadius: 240)
            }
            .padding(.horizontal, -16)
            .padding(.top, -120)
            .padding(.bottom, -30)
            .mask(LinearGradient(colors: [.black, .clear], startPoint: .center, endPoint: .bottom))
            .allowsHitTesting(false)
        }
    }

    private func tile(_ label: String, _ value: Double, format: @escaping (Double) -> String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoLabel(text: label)
            CountingText(value: value, format: format)
                .font(.display(24)).monospacedDigit().foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.5).displayTrim(24)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Days

    private func daySection(_ day: String, _ records: [DealRecord]) -> some View {
        let profit = records.compactMap(\.profit).reduce(0, +)
        let date = Format.isoDay.date(from: day)
        let title = date.map { Calendar.current.isDateInToday($0) ? "Today" : (Calendar.current.isDateInYesterday($0) ? "Yesterday" : $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) } ?? day
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title.uppercased()).font(.display(22))
                MonoLabel(text: "\(records.count) deal\(records.count == 1 ? "" : "s")")
                Spacer()
                if records.contains(where: { $0.profit != nil }) {
                    Text(Format.signedMoney(profit)).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(Theme.tone(profit))
                }
            }
            VStack(spacing: 10) {
                ForEach(records) { r in
                    NavigationLink(value: r) { DealRecordCard(record: r) }.buttonStyle(.plain)
                }
            }
        }
    }
}

/// Profit by day for the last two weeks, lime up and pink down, drawn in.
private struct ProfitBars: View {
    var records: [DealRecord]

    private var days: [(date: Date, profit: Double)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0 ..< 14).reversed().map { back in
            let d = cal.date(byAdding: .day, value: -back, to: today) ?? today
            let p = records.filter { cal.isDate($0.date, inSameDayAs: d) }.compactMap(\.profit).reduce(0, +)
            return (d, p)
        }
    }

    var body: some View {
        let data = days
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MonoLabel(text: "Profit · last 14 days")
                Spacer()
                let total = data.reduce(0) { $0 + $1.profit }
                Text(Format.signedMoney(total)).font(.geist(13, .semibold)).monospacedDigit().foregroundStyle(Theme.tone(total))
            }
            Chart(data, id: \.date) { d in
                BarMark(x: .value("Day", d.date, unit: .day), y: .value("Profit", d.profit))
                    .foregroundStyle(d.profit >= 0 ? Theme.lime : Theme.planPink)
                    .cornerRadius(3)
                RuleMark(y: .value("Zero", 0)).foregroundStyle(Theme.border)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(Theme.subtle).font(.mono(9))
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 96)
            .drawIn()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.border))
    }
}

/// A closed deal as a card: its kind, items and time, the items fanned out, photos, and profit.
private struct DealRecordCard: View {
    var record: DealRecord

    var body: some View {
        let lines = record.lines ?? []
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: record.kind.icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(record.kind.color)
                .frame(width: 40, height: 40)
                .background(Circle().fill(record.kind.color.opacity(0.14)))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(record.kind.noun).font(.geist(15, .semibold)).foregroundStyle(.white)
                    Text("· \(record.items) item\(record.items == 1 ? "" : "s")").font(.geist(13)).foregroundStyle(Theme.muted)
                }
                HStack(spacing: 8) {
                    Text(record.date.formatted(date: .omitted, time: .shortened)).font(.mono(11)).foregroundStyle(Theme.subtle)
                    if let n = record.photos?.count, n > 0 {
                        Label("\(n)", systemImage: "camera.fill").font(.geist(11, .semibold)).foregroundStyle(Theme.muted)
                    }
                }
                if !lines.isEmpty {
                    HStack(spacing: -8) {
                        ForEach(Array(lines.prefix(6).enumerated()), id: \.offset) { _, line in
                            HoldingArt(product: line.product.product, identity: nil, cornerRadius: 3, caption: false)
                                .frame(width: 26, height: 36)
                                .shadow(color: .black.opacity(0.5), radius: 3, x: 2)
                        }
                        if lines.count > 6 {
                            Text("+\(lines.count - 6)").font(.geist(11, .semibold)).foregroundStyle(Theme.muted).padding(.leading, 14)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                if let profit = record.profit {
                    Text(Format.signedMoney(profit)).font(.display(20)).monospacedDigit().foregroundStyle(Theme.tone(profit)).displayTrim(20)
                }
                Text(balanceText).font(.geist(11)).foregroundStyle(Theme.muted).monospacedDigit()
            }
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.subtle)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.border))
    }

    private var balanceText: String {
        abs(record.balance) < 0.005 ? "Even swap" : (record.balance > 0 ? "They paid \(Format.money(record.balance))" : "You paid \(Format.money(-record.balance))")
    }
}

/// Everything about one closed deal: when, who paid whom, the totals, each item that came in and
/// went out at the price it went at, and photos you can add to or delete.
private struct DealRecordDetail: View {
    var recordId: String
    @Environment(DealStore.self) private var deals
    @Environment(CollectionStore.self) private var store

    private var record: DealRecord? { deals.log.first { $0.id == recordId } }

    var body: some View {
        ScrollView {
            if let r = record {
                VStack(alignment: .leading, spacing: 28) {
                    header(r)
                    if let lines = r.lines, !lines.isEmpty {
                        lineSection(.incoming, lines.filter { $0.side == .incoming }, r.inValue)
                        lineSection(.outgoing, lines.filter { $0.side == .outgoing }, r.outValue)
                    } else {
                        Text("Came in \(Format.money(r.inValue)) · went out \(Format.money(r.outValue)). Item details weren't kept for deals closed before they were recorded.")
                            .font(.geist(13)).foregroundStyle(Theme.muted)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("PHOTOS").font(.display(22))
                            MonoLabel(text: "\(r.photos?.count ?? 0)")
                        }
                        DealPhotosStrip(photos: r.photos ?? [], accountId: store.demo == nil ? deals.accountId : nil) { photos in
                            deals.setPhotos(photos, forRecord: r.id)
                        }
                    }
                    .reveal()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .background(Theme.background)
        .replaysAnimations()
        .navigationBarTitleDisplayMode(.inline)
        .pageTitle(record.map { $0.kind.noun } ?? "Deal")
    }

    private func header(_ r: DealRecord) -> some View {
        let b = r.balance
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: r.kind.icon).font(.system(size: 13, weight: .bold)).foregroundStyle(r.kind.color)
                    .frame(width: 30, height: 30).background(Circle().fill(r.kind.color.opacity(0.16)))
                Text(r.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()).uppercased())
                    .font(.mono(11)).tracking(1).foregroundStyle(Theme.muted)
            }
            MonoLabel(text: abs(b) < 0.005 ? "Even swap" : (b > 0 ? "They paid you" : "You paid them")).padding(.top, 18)
            CountingText(value: abs(b), format: { Format.money($0) })
                .font(.display(56)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5).displayTrim(56)
                .padding(.top, 8)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 14) {
                stat("Came in", Format.money(r.inValue), .white)
                stat("Went out", Format.money(r.outValue), .white)
                stat("Profit", r.profit.map { Format.signedMoney($0) } ?? "—", r.profit == nil ? Theme.muted : Theme.tone(r.profit))
                stat("Equity taken in", r.kind == .sell ? "—" : Format.signedMoney(r.equity), r.kind == .sell ? Theme.muted : Theme.tone(r.equity))
            }
            .padding(.top, 20)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                shape.fill(Color(hex: 0x070707))
                GridPattern(step: 28, opacity: 0.06)
                RadialGradient(colors: [r.kind.color.opacity(0.22), .clear], center: .topTrailing, startRadius: 0, endRadius: 260)
            }
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(r.kind.color.opacity(0.3)))
    }

    private func stat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            MonoLabel(text: label)
            Text(value).font(.geist(17, .semibold)).monospacedDigit().foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func lineSection(_ side: DealSide, _ lines: [DealRecord.Line], _ total: Double) -> some View {
        if !lines.isEmpty {
            let incoming = side == .incoming
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .lastTextBaseline) {
                    Image(systemName: incoming ? "arrow.down.left" : "arrow.up.right").font(.system(size: 14, weight: .bold))
                        .foregroundStyle(incoming ? Theme.lime : Theme.planPink)
                    Text(incoming ? "CAME IN" : "WENT OUT").font(.display(22))
                    Spacer()
                    Text(Format.money(total)).font(.display(22)).monospacedDigit()
                }
                VStack(spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                        NavigationLink(value: line.product.id) {
                            HStack(spacing: 12) {
                                HoldingArt(product: line.product.product, identity: nil, cornerRadius: 4, caption: false)
                                    .frame(width: 40, height: 56)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(line.product.name).font(.geist(14, .medium)).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.leading)
                                    Text("\(Int(line.qty)) × \(Format.money(line.price))" + (line.product.setName.map { " · \($0)" } ?? ""))
                                        .font(.geist(12)).foregroundStyle(Theme.muted).monospacedDigit().lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text(Format.money(line.price * line.qty)).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(.white)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < lines.count - 1 { Divider().overlay(Theme.border).padding(.leading, 64) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.border))
            }
            .reveal()
        }
    }
}
