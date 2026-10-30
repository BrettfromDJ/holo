import AVFoundation
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
    @State private var choosing = false

    private var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !photos.isEmpty || uploading > 0 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
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
            }
            // Same 3D button as "Add what's coming in".
            Button {
                if hasCamera { choosing = true } else { library = true }
            } label: {
                Label(photos.isEmpty ? "Add photos" : "Add more photos", systemImage: "camera.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(Button3D(kind: .dark, fullWidth: true, height: 46))
            .confirmationDialog("Add photos", isPresented: $choosing) {
                Button("Take photo") { camera = true }
                Button("Choose from library") { library = true }
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
            DealCameraView { image in Task { await add(images: [image]) } }
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
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).frame(width: 40, height: 40).contentShape(Circle())
                }
                .background { Color.clear.liquidGlass(in: Circle()).allowsHitTesting(false) }
                Spacer()
                Text("\(min(index + 1, photos.count)) of \(photos.count)").font(.geist(13, .semibold)).monospacedDigit().foregroundStyle(.white.opacity(0.8))
                Spacer()
                Button { confirmDelete = true } label: {
                    Image(systemName: "trash").font(.system(size: 15, weight: .bold)).frame(width: 40, height: 40).contentShape(Circle())
                }
                .background { Color.clear.liquidGlass(in: Circle()).allowsHitTesting(false) }
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

/// The camera for deal photos: the picture edge to edge, Liquid Glass controls floating over
/// it, a lime shutter, and the shots piling up bottom-left. Take as many as you like; each one
/// is added to the deal as it's taken.
struct DealCameraView: View {
    var onPhoto: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera = DealCamera()
    @State private var shots: [UIImage] = []
    @State private var flashing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session).ignoresSafeArea()
            if camera.denied {
                VStack(spacing: 14) {
                    Image(systemName: "camera.fill").font(.system(size: 30)).foregroundStyle(Theme.lime)
                    Text("CAMERA IS OFF FOR HOLO").font(.display(22))
                    Text("Turn it on in Settings to photograph deals.").font(.geist(14)).foregroundStyle(Theme.muted)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(Button3D(kind: .lime, fullWidth: false, height: 44))
                }
                .padding(28)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .padding(24)
            }
            // The shutter's flash.
            Color.white.opacity(flashing ? 0.7 : 0).ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 14) {
                topBar
                Spacer()
                if shots.isEmpty {
                    Text("Shoot the cards, the table, a receipt")
                        .font(.geist(13, .medium)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 34)
                        .liquidGlass(in: Capsule())
                } else {
                    Button { dismiss() } label: {
                        Text("Done · \(shots.count) photo\(shots.count == 1 ? "" : "s")")
                    }
                    .buttonStyle(Button3D(kind: .lime, fullWidth: false, height: 40))
                    .transition(.scale.combined(with: .opacity))
                }
                tray
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .statusBarHidden()
        // Swipe down anywhere to close, as well as the X.
        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { g in
            if g.translation.height > 120 && abs(g.translation.width) < g.translation.height { dismiss() }
        })
        .onAppear {
            camera.onPhoto = { image in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { shots.append(image) }
                onPhoto(image)
            }
            camera.start()
        }
        .onDisappear { camera.stop() }
    }

    private var topBar: some View {
        HStack {
            glassCircle("xmark", label: "Close") { dismiss() }
            Spacer()
            Text("DEAL PHOTOS").font(.display(16)).tracking(0.6).foregroundStyle(.white)
                .padding(.horizontal, 16).frame(height: 40)
                .liquidGlass(in: Capsule())
            Spacer()
            glassCircle(camera.flash ? "bolt.fill" : "bolt.slash.fill", label: camera.flash ? "Flash on" : "Flash off", tint: camera.flash ? Theme.lime : .white) {
                camera.flash.toggle()
            }
        }
        .padding(.top, 6)
    }

    private var tray: some View {
        HStack {
            // The latest shot, with how many so far.
            ZStack(alignment: .topTrailing) {
                if let last = shots.last {
                    Image(uiImage: last).resizable().scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.8), lineWidth: 2))
                        .id(shots.count)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                    Text("\(shots.count)").font(.geist(11, .bold)).monospacedDigit().foregroundStyle(Theme.ink)
                        .frame(minWidth: 20, minHeight: 20).background(Circle().fill(Theme.lime))
                        .offset(x: 7, y: -7)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.08)).frame(width: 56, height: 56)
                }
            }
            .frame(width: 64, alignment: .leading)
            Spacer()
            Button {
                camera.capture()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                guard !reduceMotion else { return }
                flashing = true
                withAnimation(.easeOut(duration: 0.35)) { flashing = false }
            } label: {
                ZStack {
                    Circle().strokeBorder(.white, lineWidth: 4).frame(width: 80, height: 80)
                    Circle().fill(Theme.lime).frame(width: 64, height: 64)
                        .shadow(color: Theme.lime.opacity(0.6), radius: 12)
                }
            }
            .buttonStyle(ShutterStyle())
            .accessibilityLabel("Take photo")
            .disabled(camera.denied)
            Spacer()
            glassCircle("arrow.triangle.2.circlepath.camera", label: "Switch camera", size: 56) { camera.flip() }
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 36, style: .continuous))
    }

    private func glassCircle(_ icon: String, label: String, tint: Color = .white, size: CGFloat = 44, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size * 0.36, weight: .semibold)).foregroundStyle(tint)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // The glass sits behind the button and never takes the touch itself.
        .background { Color.clear.liquidGlass(in: Circle()).allowsHitTesting(false) }
        .accessibilityLabel(label)
    }
}

/// The shutter sinks a little as you press it.
struct ShutterStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// The capture session behind DealCameraView.
@Observable
final class DealCamera: NSObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    var flash = false
    var denied = false
    @ObservationIgnored var onPhoto: ((UIImage) -> Void)?
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "holo.deal-camera")
    @ObservationIgnored private var input: AVCaptureDeviceInput?
    @ObservationIgnored private var position = AVCaptureDevice.Position.back

    func start() {
        Task {
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                await MainActor.run { denied = true }
                return
            }
            queue.async {
                self.configure(self.position)
                self.session.startRunning()
            }
        }
    }

    func stop() { queue.async { self.session.stopRunning() } }

    func flip() {
        position = position == .back ? .front : .back
        let p = position
        queue.async { self.configure(p) }
    }

    func capture() {
        let settings = AVCapturePhotoSettings()
        let on = flash
        queue.async {
            if self.output.supportedFlashModes.contains(.on) { settings.flashMode = on ? .on : .off }
            guard self.session.isRunning else { return }
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    private func configure(_ position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        session.sessionPreset = .photo
        if let input { session.removeInput(input) }
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
           let new = try? AVCaptureDeviceInput(device: device), session.canAddInput(new) {
            session.addInput(new)
            input = new
        }
        if !session.outputs.contains(output), session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        DispatchQueue.main.async { self.onPhoto?(image) }
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

/// Closed deals, as a page like the other tabs: all-time profit huge over a lit grid with the
/// deal count, cash and items, profit climbing deal by deal, your best deal on an electric
/// card, a filter by kind, then each day's deals as cards. Tap one for everything about it.
struct DealHistoryView: View {
    @Environment(DealStore.self) private var deals
    @State private var filter: DealKind? = nil

    private static let filters: [(DealKind?, String)] = [(nil, "All"), (DealKind.buy, "Buys"), (DealKind.sell, "Sales"), (DealKind.trade, "Trades")]

    private var shown: [DealRecord] { filter.map { k in deals.log.filter { $0.kind == k } } ?? deals.log }

    private var days: [(day: String, records: [DealRecord])] {
        let grouped = Dictionary(grouping: shown) { Format.day($0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!.sorted { $0.at > $1.at }) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                if deals.log.isEmpty {
                    empty
                } else {
                    hero
                    if let best = shown.filter({ ($0.profit ?? 0) > 0 }).max(by: { ($0.profit ?? 0) < ($1.profit ?? 0) }), shown.count > 1 {
                        NavigationLink(value: best) { BestDealCard(record: best) }.buttonStyle(.plain).reveal()
                    }
                    VStack(alignment: .leading, spacing: 26) {
                        ChipPicker(options: Self.filters, selection: $filter)
                        if days.isEmpty {
                            Text("No \(filter.map { $0.noun.lowercased() } ?? "deal")s yet.").font(.geist(14)).foregroundStyle(Theme.muted)
                        }
                        ForEach(days, id: \.day) { group in daySection(group.day, group.records).reveal() }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        // The lit grid sits behind the whole page (full width, under the bar), not just the numbers.
        .background {
            ZStack(alignment: .top) {
                Theme.background
                ZStack {
                    GridPattern(step: 36, opacity: 0.05)
                    RadialGradient(colors: [Theme.lime.opacity(0.2), .clear], center: UnitPoint(x: 0.2, y: 0.35), startRadius: 0, endRadius: 300)
                    RadialGradient(colors: [Theme.planBlue.opacity(0.2), .clear], center: UnitPoint(x: 0.95, y: 0.55), startRadius: 0, endRadius: 280)
                }
                .frame(height: 520)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.55), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            }
            .ignoresSafeArea()
        }
        .replaysAnimations()
        .tabBarClearance()
        .navigationBarTitleDisplayMode(.inline)
        .pageTitle("Closed deals")
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.left.arrow.right").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.ink)
                .frame(width: 76, height: 76).background(Circle().fill(Theme.lime))
                .shadow(color: Theme.lime.opacity(0.4), radius: 20)
            Text("NO CLOSED DEALS YET").font(.display(28))
            Text("Every buy, sale and trade you close lands here, with what changed hands, your profit and your photos.")
                .font(.geist(14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
    }

    // MARK: The top: profit, counts, and profit over time

    private var hero: some View {
        let profit = shown.compactMap(\.profit).reduce(0, +)
        let cash = shown.reduce(0) { $0 + $1.balance }
        let items = shown.reduce(0) { $0 + $1.items }
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel(text: filter == nil ? "Profit from deals" : "Profit from \(filter!.noun.lowercased())s")
                CountingText(value: profit, format: { Format.signedMoney($0) })
                    .font(.display(72)).monospacedDigit().foregroundStyle(profit < 0 ? Theme.planPink : Theme.lime)
                    .lineLimit(1).minimumScaleFactor(0.5).displayTrim(72)
                    .shadow(color: (profit < 0 ? Theme.planPink : Theme.lime).opacity(0.35), radius: 18)
            }
            HStack(spacing: 8) {
                StatPill(label: "Deals", value: "\(shown.count)")
                StatPill(label: "Cash", value: Format.signedMoney(cash), tint: Theme.tone(cash))
                if items > 0 { StatPill(label: "Items", value: "\(items)") }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            ProfitClimb(records: shown)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Days

    private func daySection(_ day: String, _ records: [DealRecord]) -> some View {
        let profit = records.compactMap(\.profit).reduce(0, +)
        let date = Format.isoDay.date(from: day)
        let title = date.map { Calendar.current.isDateInToday($0) ? "Today" : (Calendar.current.isDateInYesterday($0) ? "Yesterday" : $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) } ?? day
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title.uppercased()).font(.display(24))
                MonoLabel(text: "\(records.count) deal\(records.count == 1 ? "" : "s")")
                Spacer()
                if records.contains(where: { $0.profit != nil }) {
                    Text(Format.signedMoney(profit)).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(Theme.tone(profit))
                }
            }
            VStack(spacing: 12) {
                ForEach(records) { r in
                    NavigationLink(value: r) { DealRecordCard(record: r) }.buttonStyle(.plain)
                }
            }
        }
    }
}

/// Profit adding up deal by deal, drawn in lime (pink if it's under water), like Home's chart.
private struct ProfitClimb: View {
    var records: [DealRecord]

    private var points: [(date: Date, total: Double)] {
        var running = 0.0
        return records.filter { $0.profit != nil }.sorted { $0.at < $1.at }.map { r in
            running += r.profit ?? 0
            return (r.date, running)
        }
    }

    var body: some View {
        let data = points
        if data.count >= 2 {
            let tint = (data.last?.total ?? 0) < 0 ? Theme.planPink : Theme.lime
            Chart(Array(data.enumerated()), id: \.offset) { i, p in
                AreaMark(x: .value("Deal", i), yStart: .value("Base", min(0, data.map(\.total).min() ?? 0)), yEnd: .value("Profit", p.total))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Deal", i), y: .value("Profit", p.total))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 110)
            .drawIn()
        }
    }
}

/// The deal that made the most, on an electric card.
private struct BestDealCard: View {
    var record: DealRecord

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let lines = record.lines ?? []
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SkewTag(text: "Best deal", icon: "star.fill")
                Text("\(record.kind.noun) · \(record.date.formatted(.dateTime.month(.abbreviated).day()))").font(.geist(15, .semibold)).foregroundStyle(.white)
                Text(Format.signedMoney(record.profit)).font(.display(40)).monospacedDigit().foregroundStyle(Theme.lime).displayTrim(40)
                    .shadow(color: Theme.lime.opacity(0.4), radius: 12)
            }
            Spacer(minLength: 0)
            CardFanStack(lines: Array(lines.prefix(4)), size: CGSize(width: 54, height: 76))
                .frame(width: 120, height: 100)
        }
        .padding(18)
        .background {
            ZStack {
                shape.fill(Color(hex: 0x070707))
                GridPattern(step: 28, opacity: 0.06)
                RadialGradient(colors: [Theme.lime.opacity(0.2), .clear], center: .trailing, startRadius: 0, endRadius: 220)
            }
            .clipShape(shape)
        }
        .overlay(ElectricBorder(radius: 22))
        .shadow(color: Theme.lime.opacity(0.18), radius: 18)
    }
}

/// A few items fanned like a hand of cards.
private struct CardFanStack: View {
    var lines: [DealRecord.Line]
    var size: CGSize

    var body: some View {
        ZStack {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                let off = Double(i) - Double(lines.count - 1) / 2
                HoldingArt(product: line.product.product, identity: nil, cornerRadius: 4, caption: false)
                    .frame(width: size.width, height: size.height)
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 4)
                    .rotationEffect(.degrees(off * 9), anchor: .bottom)
                    .offset(x: off * size.width * 0.38, y: abs(off) * 4)
            }
        }
    }
}

/// A closed deal as a card, balanced left to right: its items fanned on the left; the kind tag,
/// time, what it was and who paid in the middle (a camera mark when it has photos); and the
/// number that matters on the right (profit, or for a buy the equity taken in).
private struct DealRecordCard: View {
    var record: DealRecord

    var body: some View {
        let lines = record.lines ?? []
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        HStack(alignment: .center, spacing: 14) {
            fan(lines)
                .frame(width: 66, height: 78)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    SkewTag(text: record.kind.noun, color: record.kind.color, textColor: record.kind == .buy ? Theme.ink : .white, icon: record.kind.icon)
                    Text(record.date.formatted(date: .omitted, time: .shortened)).font(.mono(11)).foregroundStyle(Theme.muted)
                }
                Text(title(lines)).font(.geist(15, .semibold)).foregroundStyle(.white).lineLimit(1)
                HStack(spacing: 6) {
                    Text(balanceText).lineLimit(1)
                    if let n = record.photos?.count, n > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "camera.fill").font(.system(size: 10, weight: .semibold))
                            Text("\(n)")
                        }
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 6).frame(height: 18)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                }
                .font(.geist(12)).foregroundStyle(Theme.muted).monospacedDigit()
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                let h = headline
                Text(h.1.map { Format.signedMoney($0) } ?? "—").font(.display(24)).monospacedDigit()
                    .foregroundStyle(h.1.map { Theme.tone($0) } ?? Theme.muted).displayTrim(24)
                    .lineLimit(1).minimumScaleFactor(0.7)
                MonoLabel(text: h.0)
            }
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.subtle)
        }
        .padding(14)
        .background {
            ZStack {
                shape.fill(Theme.surface)
                RadialGradient(colors: [record.kind.color.opacity(0.12), .clear], center: .leading, startRadius: 0, endRadius: 220)
            }
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(record.kind.color.opacity(0.2)))
    }

    /// Up to three items fanned like a hand of cards.
    private func fan(_ lines: [DealRecord.Line]) -> some View {
        let shown = Array(lines.prefix(3))
        return ZStack {
            if shown.isEmpty {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.well).frame(width: 46, height: 64)
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { i, line in
                let off = Double(i) - Double(shown.count - 1) / 2
                HoldingArt(product: line.product.product, identity: nil, cornerRadius: 4, caption: false)
                    .frame(width: 46, height: 64)
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 3)
                    .rotationEffect(.degrees(off * 10), anchor: .bottom)
                    .offset(x: off * 12)
            }
        }
    }

    private func title(_ lines: [DealRecord.Line]) -> String {
        guard let first = lines.first else { return "\(record.items) item\(record.items == 1 ? "" : "s")" }
        return lines.count == 1 ? first.product.name : "\(first.product.name) + \(lines.count - 1) more"
    }

    /// Profit when something went out; for a buy, the equity taken in.
    private var headline: (String, Double?) {
        if let p = record.profit { return ("Profit", p) }
        if record.inValue > 0 { return ("Equity", record.equity) }
        return ("Profit", nil)
    }

    private var balanceText: String {
        abs(record.balance) < 0.005 ? "Even swap" : (record.balance > 0 ? "They paid \(Format.money(record.balance))" : "You paid \(Format.money(-record.balance))")
    }
}

/// Everything about one closed deal: when, who paid whom, the totals, each item that came in and
/// went out at the price it went at, and photos you can add to or delete.
struct DealRecordDetail: View {
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
