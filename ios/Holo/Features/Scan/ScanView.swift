import AVFoundation
import SwiftUI

/// Full-screen scanner. Tap the card (or anywhere on the picture) to scan it; each lands in a
/// strip you can swipe through. Next opens the review, where you set what you paid and add
/// them all. The first time, a small hint says to tap the card. There is no shutter button.
/// Text on the glass is white, never grey: grey reads as dull on a see-through surface, so
/// secondary lines differ by size and weight only.
///
/// Live tracking: while the scanner is on screen and uncovered, the camera finds the card
/// in view and `CardTracker` follows it; `CardTrackingOverlay` (its own small view, the only
/// one redrawn per frame) draws the lime border, and the static guide fades out. Tapping the
/// card adds it: straight from the live read when it matched (no paid scan), else as a photo
/// cropped to the card. With no card tracked a tap scans the whole picture.
struct ScanView: View {
    /// When scanning into a deal: which side, and where each match goes.
    var dealSide: DealSide?
    var onPick: (@MainActor (ScanCandidate, ScanRead?) -> (ok: Bool, note: String))?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = Camera()
    @State private var model = ScanModel()
    @State private var tracker = CardTracker()
    @State private var reviewing = false
    @State private var flash = false
    @State private var focused: UUID?
    @State private var torch = false
    @State private var clearing = false
    @State private var searchingManually = false
    /// A scanned card's page, open over the scanner (tap a matched card in the strip).
    @State private var viewing: ViewedProduct?
    /// "Tap the card to scan it", until the first tap ever.
    @State private var showTip = !UserDefaults.standard.bool(forKey: "scan-tip-seen")
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session, running: camera.state == .running).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { shoot() }
            CardTrackingOverlay(tracker: tracker, onTap: { shoot() })
            if flash { Color.white.opacity(0.7).ignoresSafeArea().transition(.opacity).allowsHitTesting(false) }

            VStack(spacing: 0) {
                topBar
                guide
                bottom
            }
        }
        .statusBarHidden()
        // Swipe down anywhere to close, as well as the X.
        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { g in
            if g.translation.height > 120 && abs(g.translation.width) < g.translation.height { dismiss() }
        })
        .onAppear {
            let liveTracker = self.tracker
            let liveCamera = self.camera
            liveCamera.onCard = { [weak liveTracker] quad, size in liveTracker?.update(quad, frame: size) }
            liveTracker.snapshot = { [weak liveCamera] in await liveCamera?.snapshotCard() }
            camera.start()
            syncTracking()
        }
        .onDisappear {
            if torch { camera.setTorch(false) }
            camera.stop()
            tracker.active = false
        }
        // Live tracking only while the scanner can be seen.
        .onChange(of: reviewing) { _, _ in syncTracking() }
        .onChange(of: viewing) { _, _ in syncTracking() }
        // Search manually covers the scanner and has a scanner of its own: this camera is let
        // go while it's up (two at once would fight over the lens) and taken back after.
        .onChange(of: searchingManually) { _, searching in
            if searching {
                if torch { torch = false; camera.setTorch(false) }
                camera.stop()
            } else {
                camera.start()
            }
            syncTracking()
        }
        .onChange(of: camera.state) { _, _ in syncTracking() }
        // Search instead: into the collection, or (scanning into a deal) onto that side of it.
        .fullScreenCover(isPresented: Binding(get: { searchingManually && dealSide == nil }, set: { searchingManually = $0 })) { SearchScreen(mode: .add) }
        .sheet(isPresented: Binding(get: { searchingManually && dealSide != nil }, set: { searchingManually = $0 })) {
            if let dealSide { DealPickerSheet(side: dealSide) }
        }
        .task {
            model.onPick = onPick
            await model.refreshBalance()
            // CardSight does the identifying: the live border stays, the phone's own read doesn't run.
            if model.cardSight { tracker.identifies = false }
        }
        .sheet(isPresented: $reviewing) {
            ScanReviewSheet(model: model, focus: focused, onAdded: { dismiss() })
        }
        // The card's page, as everywhere else in the app, over the camera.
        .sheet(item: $viewing) { v in
            NavigationStack {
                ProductDetailView(productId: v.id)
                    .navigationDestination(for: String.self) { ProductDetailView(productId: $0) }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { viewing = nil } } }
            }
            .presentationDetents([.fraction(0.93)])
            .presentationDragIndicator(.visible)
            .glassSheet()
        }
    }

    // MARK: Top: close, search instead of scanning, scans left (all Liquid Glass)

    private var topBar: some View {
        HStack(spacing: 8) {
            glassCircle("xmark", label: "Close") { dismiss() }
            // Can't scan it (a bad angle, a foreign card)? Look it up by name instead.
            Button { searchingManually = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium))
                    Text(dealSide == nil ? "Search manually" : (dealSide == .incoming ? "Search · coming in" : "Search · going out"))
                        .font(.geist(15, .medium)).lineLimit(1)
                }
                .frame(maxWidth: .infinity).frame(height: 44)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .background { Color.clear.liquidGlass(in: Capsule()).allowsHitTesting(false) }
            if let left = model.scansLeft {
                Text("\(left.formatted()) left").font(.mono(12)).monospacedDigit()
                    .padding(.horizontal, 12).frame(height: 44)
                    .liquidGlass(in: Capsule())
            }
            // The light, for dim card shows: lime while on.
            if camera.hasTorch || camera.state != .running {
                Button {
                    torch.toggle()
                    camera.setTorch(torch)
                } label: {
                    Image(systemName: torch ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(torch ? Theme.ink : .white)
                        .frame(width: 44, height: 44)
                        .background { if torch { Circle().fill(Theme.lime) } }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .background { Color.clear.liquidGlass(in: Circle()).allowsHitTesting(false) }
                .accessibilityLabel(torch ? "Light on" : "Light")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: The card outline: a thin lime frame with a light sweeping down

    private var guide: some View {
        GeometryReader { geo in
            let h = min(geo.size.height * 0.86, geo.size.width * 0.62 * 88 / 63)
            let w = h * 63 / 88
            ZStack {
                // Gives way to the live border while a card is tracked.
                TrackingFade(tracker: tracker) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Theme.lime, lineWidth: 2)
                            .shadow(color: Theme.lime.opacity(0.6), radius: 6)
                            .frame(width: w, height: h)
                        ScanSweep(height: h)
                            .frame(width: w - 16, height: h)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                if model.busy > 0 {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini).tint(Theme.lime)
                        Text("\(model.busy) reading").font(.geist(12, .semibold)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12).frame(height: 30)
                    .liquidGlass(in: Capsule())
                    .frame(width: w, height: h, alignment: .bottom)
                    .padding(.bottom, 14)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Taps go through to the tracked card underneath.
            .allowsHitTesting(false)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if showTip, camera.state == .running {
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.lime)
                    Text("Tap the card to scan it").font(.geist(14, .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).frame(height: 40)
                .liquidGlass(in: Capsule())
                .padding(.bottom, 18)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: showTip)
        .overlay {
            if camera.state == .denied {
                VStack(spacing: 14) {
                    Image(systemName: "camera.fill").font(.system(size: 30)).foregroundStyle(Theme.lime)
                    Text("Camera is off for Lucent").font(.display(22)).tracking(-0.6)
                    Text("Turn it on in Settings to scan cards.").font(.geist(14)).foregroundStyle(.white)
                    Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                        .buttonStyle(Button3D(kind: .lime, fullWidth: false, height: 44))
                }
                .foregroundStyle(.white)
                .padding(28)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .padding(24)
            }
        }
    }

    // MARK: Bottom: the docked tray with the scans, the total and Next

    private var bottom: some View {
        VStack(spacing: 14) {
            if let blocked = model.blocked {
                Label(blocked, systemImage: "exclamationmark.triangle.fill")
                    .font(.geist(13, .medium)).foregroundStyle(.white)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), tint: Theme.planPink.opacity(0.4))
                    .padding(.horizontal, 16)
            }
            tray
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: model.entries.count)
    }

    /// Docked to the bottom edge: what this scan is and how many, the scans so far (or a short
    /// hint), then the total with Clear and Next.
    private var tray: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
        return VStack(spacing: 0) {
            HStack {
                Text(dealSide == nil ? "This scan" : (dealSide == .incoming ? "Coming in" : "Going out"))
                    .font(.geist(16, .semibold))
                Spacer()
                Text("\(model.entries.count) card\(model.entries.count == 1 ? "" : "s")")
                    .font(.geist(13, .medium)).monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            Group {
                if model.entries.isEmpty {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                            .frame(width: 48, height: 64)
                            .overlay(Image(systemName: "rectangle.on.rectangle").font(.system(size: 16)).foregroundStyle(.white))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("No cards yet").font(.geist(15, .semibold))
                            Text("Hold a card in view, then tap it.").font(.geist(13)).foregroundStyle(.white)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 8) {
                            // Newest first, so the card you just scanned lands on the left.
                            ForEach(model.entries) { e in
                                ScanChip(entry: e, onTap: {
                                    // A matched card opens its page; anything else goes to the review
                                    // (to pick between matches), and a failed read is tried again.
                                    if e.state == .failed {
                                        model.retry(e.id)
                                    } else if e.state == .done, let p = e.picked?.product {
                                        viewing = ViewedProduct(id: p.id)
                                    } else {
                                        focused = e.id
                                        reviewing = true
                                    }
                                }, onRemove: {
                                    withAnimation(.snappy) { model.remove(e.id) }
                                })
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .frame(height: 112)
            .padding(.vertical, 12)
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(Format.money(model.total)).font(.display(28)).tracking(-0.8).monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(model.picks.isEmpty ? "Total value" : "\(model.picks.count) matched").font(.geist(12)).foregroundStyle(.white)
                }
                Spacer()
                Button { clearing = true } label: {
                    Image(systemName: "trash").font(.system(size: 16, weight: .medium))
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .background { Color.clear.liquidGlass(in: Circle()).allowsHitTesting(false) }
                .opacity(model.entries.isEmpty ? 0.4 : 1)
                .disabled(model.entries.isEmpty)
                .accessibilityLabel("Clear all scans")
                Button {
                    // In a deal, scans are already in it: Done just closes the camera.
                    if dealSide != nil {
                        dismiss()
                    } else {
                        focused = nil
                        reviewing = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(dealSide == nil ? "Next" : "Done")
                        if dealSide == nil { Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold)) }
                    }
                }
                .buttonStyle(Button3D(kind: .lime, fullWidth: false, height: 48))
                .fixedSize()
                .opacity(model.entries.isEmpty ? 0.4 : 1)
                .disabled(model.entries.isEmpty)
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10)
        }
        .foregroundStyle(.white)
        .background { Color.clear.liquidGlass(in: shape).ignoresSafeArea(edges: .bottom) }
        .alert("Clear these scans?", isPresented: $clearing) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { withAnimation(.snappy) { for e in model.entries { model.remove(e.id) } } }
        } message: {
            Text("Nothing has been added to your collection yet.")
        }
    }

    private func glassCircle(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // The glass sits behind the button and never takes the touch itself.
        .background { Color.clear.liquidGlass(in: Circle()).allowsHitTesting(false) }
        .accessibilityLabel(label)
    }

    /// Process camera frames only while the scanner is up and nothing covers it.
    private func syncTracking() {
        let on = camera.state == .running && !reviewing && !searchingManually && viewing == nil
        camera.setTracking(on)
        tracker.active = on
    }

    /// A tap on the card (or the picture). A card already read live goes straight in;
    /// a tracked card is photographed and cropped to its corners; otherwise a plain photo.
    private func shoot() {
        guard camera.state == .running else { return }
        if showTip {
            showTip = false
            UserDefaults.standard.set(true, forKey: "scan-tip-seen")
        }
        // Reading the tracker here (an action, not `body`) doesn't make this view observe it.
        if let live = tracker.readyMatch {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            flashOnce()
            model.add(matched: OnDeviceScan.result(for: live.hit), photo: live.crop.jpeg, thumbnail: live.crop.image)
            return
        }
        guard model.blocked == nil else { return }
        let quad = tracker.quad
        let tappedAt = Date()
        UIImpactFeedbackGenerator(style: quad == nil ? .medium : .light).impactOccurred()
        flashOnce()
        Task {
            do {
                // CardSight reads a card fine from a smaller photo, which uploads in about half the time.
                let small = model.cardSight
                let jpeg = small ? try await camera.capture(maxEdge: 1000, quality: 0.75) : try await camera.capture()
                // Crop to the tracked card (off the main thread); the whole photo if that fails.
                var photo = jpeg
                // With CardSight the whole photo goes up: it finds every card in it.
                if let quad, !model.cardSight {
                    let crop = await Task.detached(priority: .userInitiated) { Camera.crop(photo: jpeg, to: quad)?.jpeg }.value
                    if let crop { photo = crop }
                }
                await MainActor.run { model.add(photo: photo, tappedAt: tappedAt) }
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func flashOnce() {
        withAnimation(.easeOut(duration: 0.05)) { flash = true }
        withAnimation(.easeOut(duration: 0.25).delay(0.05)) { flash = false }
    }
}

/// A product whose page is open over the scanner.
struct ViewedProduct: Identifiable, Equatable {
    let id: String
}

/// Shows its content only while no card is tracked. Reads just `isTracking`, so the corner
/// updates never redraw it.
private struct TrackingFade<Content: View>: View {
    let tracker: CardTracker
    let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(tracker: CardTracker, @ViewBuilder content: () -> Content) {
        self.tracker = tracker
        self.content = content()
    }

    var body: some View {
        content
            .opacity(tracker.isTracking ? 0 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: tracker.isTracking)
    }
}

/// Just the four corners of a rounded card outline.
private struct ScanCorners: Shape {
    var radius: CGFloat

    func path(in r: CGRect) -> Path {
        let len = min(r.width, r.height) * 0.16
        var p = Path()
        // Top left
        p.move(to: CGPoint(x: r.minX, y: r.minY + radius + len))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addQuadCurve(to: CGPoint(x: r.minX + radius, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + radius + len, y: r.minY))
        // Top right
        p.move(to: CGPoint(x: r.maxX - radius - len, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + radius), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + radius + len))
        // Bottom right
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - radius - len))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - radius - len, y: r.maxY))
        // Bottom left
        p.move(to: CGPoint(x: r.minX + radius + len, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - radius), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - radius - len))
        return p
    }
}

/// A soft lime light sweeping down the card outline: one repeating offset animation.
private struct ScanSweep: View {
    var height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var down = false

    var body: some View {
        if !reduceMotion {
            LinearGradient(colors: [.clear, Theme.lime.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 70)
                .overlay(Rectangle().fill(Theme.lime.opacity(0.7)).frame(height: 1.5))
                .offset(y: down ? height / 2 : -height / 2)
                .frame(maxHeight: .infinity)
                .allowsHitTesting(false)
                // Only sweeps while it can be seen: under the review sheet's glass a moving light
                // makes iOS redraw the blur every frame and the sheet feels slow.
                .onVisibilityChange { on in
                    if on {
                        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { down = true }
                    } else {
                        stopLoop { down = false }
                    }
                }
        }
    }
}

/// A scan in the strip: the card's picture, what it matched (name, set, number and price), or
/// what it still needs. A long press offers to remove it. A faint white tile with a hairline,
/// not glass: glass on the glass tray looked like a smudge.
struct ScanChip: View {
    var entry: ScanModel.Entry
    var onTap: () -> Void
    var onRemove: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                thumb.frame(width: 66, height: 92).clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.geist(15, .semibold)).foregroundStyle(.white).lineLimit(2)
                    if entry.state == .done, let set = entry.picked?.product.setName {
                        Text(set).font(.geist(12)).foregroundStyle(.white).lineLimit(1)
                    }
                    detail.font(.geist(13)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(width: 256, height: 112)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onRemove) { Label("Remove", systemImage: "trash") }
        }
    }

    @ViewBuilder private var thumb: some View {
        if let p = entry.picked?.product {
            ProductImage(product: p, cornerRadius: 7)
        } else if let img = entry.thumbnail {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            Theme.surface2
        }
    }

    private var title: String {
        switch entry.state {
        case .queued, .reading: return "Reading…"
        case .failed: return "Couldn't read"
        case .done:
            if let p = entry.picked { return p.product.name }
            return entry.result?.status == "ambiguous" ? "Which one?" : "No match"
        }
    }

    @ViewBuilder private var detail: some View {
        switch entry.state {
        case .queued, .reading:
            ProgressView().controlSize(.mini).tint(.white)
        case .failed:
            Label("Try again", systemImage: "arrow.clockwise").foregroundStyle(.white)
        case .done:
            if entry.rejected, let note = entry.note {
                Text(note).foregroundStyle(Theme.down)
            } else if let p = entry.picked {
                (Text(p.product.number.map { "#\($0) · " } ?? "").foregroundStyle(.white)
                    + Text(Format.money(entry.value)).bold().foregroundStyle(.white))
                    .monospacedDigit()
            } else {
                Text(entry.result?.status == "ambiguous" ? "Tap to pick" : "Tap for details").foregroundStyle(Theme.warn)
            }
        }
    }
}
