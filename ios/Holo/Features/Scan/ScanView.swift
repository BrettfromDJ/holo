import AVFoundation
import SwiftUI

/// Full-screen scanner. Tap the card (or anywhere on the picture) to scan it; each lands in a
/// strip you can swipe through. Next opens the review, where you set what you paid and add
/// them all. The first time, a small hint says to tap the card. There is no shutter button.
/// Text on the glass is white, never grey: grey reads as dull on a see-through surface, so
/// secondary lines differ by size and weight only.
///
/// Live tracking: while the scanner is on screen and uncovered, the camera finds the card
/// in view and `CardTracker` follows it (no outline is drawn; the still lime guide stays).
/// Tapping adds it: straight from the live read when it matched (no paid scan), else as a photo
/// cropped to the card. With no card tracked a tap scans the whole picture.
struct ScanView: View {
    /// When scanning into a deal: which side, and where each match goes.
    var dealSide: DealSide?
    var onPick: (@MainActor (ScanCandidate, ScanRead?) -> (ok: Bool, note: String))?

    @Environment(\.dismiss) private var dismiss
    @Environment(CollectionStore.self) private var store
    /// One camera for every scanner: set up once, then just restarted, so reopening is quick.
    @ObservedObject private var camera = Camera.shared
    @State private var model = ScanModel()
    @State private var tracker = CardTracker()
    @State private var reviewing = false
    @State private var flash = false
    @State private var focused: UUID?
    @State private var torch = false
    @AppStorage(ScanGame.key) private var scanGame = ScanGame.pokemon.rawValue
    @State private var searchingManually = false
    /// The scan open close up (tap a tile): condition, printing, price, paid, remove.
    @State private var editing: EditingScan?
    /// The strip opened out into a list over the camera (tap the card count), to look through
    /// what's been scanned; tap again to go back to scanning.
    @State private var expanded = false
    /// "Tap the card to scan it", until the first tap ever.
    @State private var showTip = !UserDefaults.standard.bool(forKey: "scan-tip-seen")
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The first time, before Apple's camera prompt: one line on why, then the prompt.
    @State private var cameraNote = !Onboarding.cameraNoteSeen && AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session, running: camera.state == .running).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { shoot() }
            // The card is still found and followed (for a clean crop), but no live outline is
            // drawn round it: the still guide below is the only frame on screen.
            if flash { Color.white.opacity(0.7).ignoresSafeArea().transition(.opacity).allowsHitTesting(false) }

            VStack(spacing: 0) {
                topBar
                gamePicker.padding(.top, 10)
                guide
                bottom
            }
            if cameraNote {
                CameraNote {
                    Onboarding.cameraNoteSeen = true
                    cameraNote = false
                    camera.start()
                }
            }
        }
        .statusBarHidden()
        // Swipe down anywhere to close, as well as the X.
        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { g in
            if g.translation.height > 120 && abs(g.translation.width) < g.translation.height { dismiss() }
        })
        .onAppear {
            wire()
            // The note's button starts the camera the first time (its prompt follows the note).
            if !cameraNote { camera.start() }
            syncTracking()
        }
        .onDisappear {
            if torch { camera.setTorch(false) }
            camera.stop()
            tracker.active = false
        }
        // Live tracking only while the scanner can be seen.
        .onChange(of: reviewing) { _, _ in syncTracking() }
        .onChange(of: editing) { _, _ in syncTracking() }
        .onChange(of: expanded) { _, _ in syncTracking() }
        // Search manually covers the scanner and has a scanner of its own: this camera is let
        // go while it's up (two at once would fight over the lens) and taken back after.
        .onChange(of: searchingManually) { _, searching in
            if searching {
                if torch { torch = false; camera.setTorch(false) }
                camera.stop()
            } else {
                // Search's own scanner may have pointed the shared camera at its tracker.
                wire()
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
            // Screenshots: -HoloScanSample ambiguous|retake|matched opens a made-up scan's sheet.
            if Demo.isOn, Demo.value("-HoloScanSample") == "matched", let p = store.products["sample:charizard-ex-151"] {
                let hit = ScanCandidate(product: p, printing: nil, printings: p.printings ?? [], market: store.marketPrice(p.id, printing: p.printings?.first)?.market, score: 0.9)
                model.add(matched: ScanResult(status: "matched", message: nil, read: nil, candidates: [hit], scansRemaining: nil), photo: Data(), thumbnail: nil)
                try? await Task.sleep(nanoseconds: 800_000_000)
                if let first = model.entries.first { editing = EditingScan(id: first.id) }
            } else if Demo.isOn, let kind = Demo.value("-HoloScanSample") {
                let ids = ["sample:charizard-ex-151", "sample:charizard-ex-of", "sample:mew-ex-gold", "sample:pikachu-ex-ss"]
                let candidates = kind == "retake" ? [] : ids.compactMap { id in
                    store.products[id].map { ScanCandidate(product: $0, printing: nil, printings: $0.printings ?? [], market: store.marketPrice(id, printing: $0.printings?.first)?.market, score: 0.5) }
                }
                var e = ScanModel.Entry(photo: Data())
                e.state = .done
                e.result = ScanResult(status: kind == "retake" ? "retake" : "ambiguous",
                                      message: kind == "retake" ? "No card found in the photo. Fill the frame with the card and try again." : nil,
                                      read: nil, candidates: candidates, scansRemaining: nil)
                model.entries.append(e)
                try? await Task.sleep(nanoseconds: 800_000_000)
                editing = EditingScan(id: e.id)
            }
        }
        .sheet(isPresented: $reviewing) {
            ScanReviewSheet(model: model, focus: focused, onAdded: { dismiss() })
        }
        // One scan close up, over the camera.
        .sheet(item: $editing) { e in
            ScanCardSheet(model: model, id: e.id, onRemove: { withAnimation(.snappy) { model.remove(e.id) } })
        }
    }

    // MARK: Top: close, search instead of scanning, scans left (all Liquid Glass)

    /// Which game the scanner reads, under the top bar: Pokémon unless you switch.
    private var gamePicker: some View {
        Menu {
            Picker("Game", selection: $scanGame) {
                ForEach(ScanGame.allCases) { Text($0.title).tag($0.rawValue) }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Scanning").foregroundStyle(.white.opacity(0.7))
                Text(ScanGame(rawValue: scanGame)?.title ?? "Pokémon").foregroundStyle(.white)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.7))
            }
            .font(.geist(13, .semibold))
            .padding(.horizontal, 12).frame(height: 32)
            .background(Capsule().fill(Color.black.opacity(0.55)))
        }
        .onChange(of: scanGame) { _, _ in Haptics.tap() }
        .accessibilityLabel("Game: \(ScanGame(rawValue: scanGame)?.title ?? "Pokémon")")
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            glassCircle("xmark", label: "Close") { Haptics.tap(); dismiss() }
            // Can't scan it (a bad angle, a foreign card)? Look it up by name instead.
            Button { Haptics.tap(); searchingManually = true } label: {
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
                    Haptics.tap()
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
                // The still guide, always shown.
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.lime, lineWidth: 2)
                        .shadow(color: Theme.lime.opacity(0.6), radius: 6)
                        .frame(width: w, height: h)
                    ScanSweep(height: h)
                        .frame(width: w - 16, height: h)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                // Its own view: it's the only part of the guide that watches the scans.
                ReadingPill(model: model)
                    .frame(width: w, height: h, alignment: .bottom)
                    .padding(.bottom, 14)
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
                    Text("Tap the card to scan\u{00A0}it").font(.geist(14, .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).frame(height: 40)
                // Solid, not glass: glass over the live picture is re-blurred every frame.
                .background(Capsule().fill(Color.black.opacity(0.72)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
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
                    Text("Camera is off for Dexora").font(.display(22)).tracking(-0.6)
                    Text("Turn it on in Settings to scan\u{00A0}cards.").font(.geist(14)).foregroundStyle(.white)
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

    // MARK: Bottom: the docked tray (its own view, so the scans redraw only it)

    private var bottom: some View {
        ScanTray(model: model, dealSide: dealSide, expanded: $expanded, onOpen: { open($0) },
                 onNext: { focused = nil; reviewing = true }, onDone: { dismiss() })
    }

    /// A tapped scan opens (its card page on the scan's printing; a failed read is tried again first).
    private func open(_ e: ScanModel.Entry) {
        if e.state == .failed { model.retry(e.id) }
        if let p = e.picked { store.setOpenPrinting(e.printing ?? p.printing, for: p.product.id) }
        editing = EditingScan(id: e.id)
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

    /// Points the shared camera at this scanner's tracker (and the tracker at the camera).
    private func wire() {
        let liveTracker = self.tracker
        let liveCamera = self.camera
        liveCamera.onCard = { [weak liveTracker] quad, size in liveTracker?.update(quad, frame: size) }
        liveTracker.snapshot = { [weak liveCamera] in await liveCamera?.snapshotCard() }
    }

    /// Process camera frames only while the scanner is up and nothing covers it.
    private func syncTracking() {
        let on = camera.state == .running && !reviewing && !searchingManually && editing == nil && !expanded
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
            Haptics.tap()
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

/// A scan open close up over the scanner.
struct EditingScan: Identifiable, Equatable {
    let id: UUID
}

/// The docked tray: what this scan is and how many, the scans so far (a strip, or opened out
/// into a list), then the total with Clear and Next. Its own view so that the scans coming
/// and going redraw only this, never the camera, the top bar or the overlays.
private struct ScanTray: View {
    let model: ScanModel
    var dealSide: DealSide?
    @Binding var expanded: Bool
    var onOpen: (ScanModel.Entry) -> Void
    var onNext: () -> Void
    var onDone: () -> Void
    @State private var clearing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(CollectionStore.self) private var store

    var body: some View {
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

    private var tray: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
        return VStack(spacing: 0) {
            HStack {
                // What this scan is, and the running total.
                HStack(spacing: 8) {
                    Text(dealSide == nil ? "This scan" : (dealSide == .incoming ? "Coming in" : "Going out"))
                        .font(.geist(16, .semibold))
                    if !model.picks.isEmpty {
                        Text(Format.money(model.total)).font(.geist(16, .semibold)).monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(Theme.lime)
                    }
                }
                Spacer()
                // The count opens the strip out into a list (and closes it again).
                Button {
                    Haptics.tap()
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text("\(model.entries.count) card\(model.entries.count == 1 ? "" : "s")")
                            .font(.geist(13, .medium)).monospacedDigit()
                            .contentTransition(.numericText())
                        Image(systemName: "chevron.up").font(.system(size: 11, weight: .semibold))
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(Capsule().fill(Color.white.opacity(expanded ? 0.18 : 0.1)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.entries.isEmpty)
                .accessibilityLabel(expanded ? "Back to the strip" : "See all scanned cards")
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            Group {
                if expanded {
                    // Every scan, top to bottom, newest first.
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 8) {
                            ForEach(model.entries) { e in
                                chip(e, fills: true)
                                    // Swipe either way to remove.
                                    .swipeAway(e.picked?.product.name ?? "this scan") { withAnimation(.snappy) { model.remove(e.id) } }
                                    .transition(.opacity)
                            }
                        }
                        .padding(.horizontal, 20).padding(.vertical, 8)
                    }
                    .scrollClipDisabled()
                } else if model.entries.isEmpty {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                            .frame(width: 48, height: 64)
                            .overlay(Image(systemName: "rectangle.on.rectangle").font(.system(size: 16)).foregroundStyle(.white))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("No cards yet").font(.geist(15, .semibold))
                            Text("Hold a card in view, then tap\u{00A0}it.").font(.geist(13)).foregroundStyle(.white)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 8) {
                            // Newest first, so the card you just scanned lands on the left.
                            ForEach(model.entries) { e in
                                chip(e, fills: false)
                                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                    // A long-pressed tile lifts a little past its edges: don't cut it off.
                    .scrollClipDisabled()
                }
            }
            .frame(height: expanded ? min(CGFloat(model.entries.count) * 120 + 16, 480) : 128)
            .padding(.vertical, 4)
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(Format.money(model.total)).font(.display(28)).tracking(-0.8).padding(.trailing, 0.8).monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(model.picks.isEmpty ? "Total value" : "\(model.picks.count) matched").font(.geist(12)).foregroundStyle(.white)
                }
                Spacer()
                Button { Haptics.tap(); clearing = true } label: {
                    Image(systemName: "trash").font(.system(size: 16, weight: .medium))
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .background { Circle().fill(Color.white.opacity(0.1)).allowsHitTesting(false) }
                .opacity(model.entries.isEmpty ? 0.4 : 1)
                .disabled(model.entries.isEmpty)
                .accessibilityLabel("Clear all scans")
                Button {
                    // In a deal, scans are already in it: Done just closes the camera.
                    Haptics.tap()
                    if dealSide != nil { onDone() } else { onNext() }
                } label: {
                    HStack(spacing: 6) {
                        Text(dealSide == nil ? "Review \(model.entries.count)" : "Done")
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
        // Solid black, not glass: the camera behind made the tray's text and tiles hard to read.
        .background {
            shape.fill(Color.black)
                .overlay(shape.stroke(Color.white.opacity(0.1), lineWidth: 1))
                .ignoresSafeArea(edges: .bottom)
        }
        .alert("Clear these scans?", isPresented: $clearing) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { Haptics.remove(); withAnimation(.snappy) { for e in model.entries { model.remove(e.id) } } }
        } message: {
            Text("Nothing has been added to your collection\u{00A0}yet.")
        }
    }

    /// One scan's tile, in the strip (fixed width) or the opened-out list (full width).
    private func chip(_ e: ScanModel.Entry, fills: Bool) -> some View {
        ScanChip(entry: e, owned: owned(e), fills: fills, onTap: { Haptics.tap(); onOpen(e) },
                 onRemove: { Haptics.remove(); withAnimation(.snappy) { model.remove(e.id) } })
    }

    /// How many of this card you already have.
    private func owned(_ e: ScanModel.Entry) -> Int {
        guard let id = e.picked?.product.id else { return 0 }
        return Int(store.allHoldings.filter { $0.identity.productId == id }.reduce(0) { $0 + $1.quantity })
    }
}

/// "2 reading" while scans are being read. Its own view so that only it watches the scans.
private struct ReadingPill: View {
    let model: ScanModel

    var body: some View {
        if model.busy > 0 {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini).tint(Theme.lime)
                Text("\(model.busy) reading").font(.geist(12, .semibold)).foregroundStyle(.white)
            }
            .padding(.horizontal, 12).frame(height: 30)
            // Solid, not glass: glass over the live picture is re-blurred every frame.
            .background(Capsule().fill(Color.black.opacity(0.72)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        }
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
/// what it still needs. Removing is done in the opened-out list (a swipe) or the review; the
/// tile itself only opens the card. A faint white tile with a hairline, not glass: glass on
/// the glass tray looked like a smudge.
struct ScanChip: View {
    var entry: ScanModel.Entry
    /// How many of this card you already own (a tag when more than none).
    var owned = 0
    /// Full width (in the opened-out list) rather than a fixed strip tile.
    var fills = false
    var onTap: () -> Void
    /// Takes this scan out: a trash button inside the tile's right edge.
    var onRemove: (() -> Void)? = nil

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                thumb.frame(width: 66, height: 92).clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.geist(15, .semibold)).foregroundStyle(.white).lineLimit(fills ? 2 : 1)
                    if entry.state == .done, let p = entry.picked?.product {
                        Text(p.subtitle).font(.geist(12)).foregroundStyle(.white).lineLimit(1)
                    }
                    detail.font(.geist(13)).lineLimit(1)
                }
                Spacer(minLength: 0)
                // Room for the trash button laid over this edge.
                if onRemove != nil { Color.clear.frame(width: 30) }
            }
            .padding(10)
            .frame(width: fills ? nil : 256, height: 112)
            .frame(maxWidth: fills ? .infinity : nil)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "trash").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
                .accessibilityLabel("Remove \(entry.picked?.product.name ?? "this scan")")
            }
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
                // Condition (or grade), the printing when the card has several, and the price.
                let condition = entry.isSlab ? entry.result?.read?.grade.map { "\($0.company) \($0.grade)" } : (p.product.isSealed ? nil : CardCondition(rawValue: entry.condition)?.short)
                let printing = (p.product.printings?.count ?? 0) > 1 ? (entry.printing ?? p.printing) : nil
                let lead = [condition, printing].compactMap { $0 }.joined(separator: " · ")
                // The price on its own line, so the trash button never squeezes it out.
                VStack(alignment: .leading, spacing: 3) {
                    if !lead.isEmpty { Text(lead).foregroundStyle(.white) }
                    HStack(spacing: 6) {
                        Text(Format.money(entry.value)).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(.white)
                            .fixedSize()
                        if owned > 0 { Tag(text: "Owned ×\(owned)", tint: Theme.lime) }
                    }
                }
            } else {
                Text(entry.result?.status == "ambiguous" ? "Tap to pick" : "Tap for details").foregroundStyle(Theme.warn)
            }
        }
    }
}


/// The one-line glass note shown once before the camera prompt.
private struct CameraNote: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.viewfinder").font(.system(size: 28, weight: .medium)).foregroundStyle(Theme.lime)
            Text("Dexora uses the camera to read your\u{00A0}cards").font(.geist(16, .semibold)).multilineTextAlignment(.center)
            Text("Nothing is kept unless you add\u{00A0}it.").font(.geist(13)).foregroundStyle(Theme.muted)
            Button("Continue", action: onContinue).buttonStyle(Button3D(kind: .lime, height: 46)).padding(.top, 4)
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: 320)
        .blurredGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(24)
        .accessibilityIdentifier("camera-note")
    }
}
