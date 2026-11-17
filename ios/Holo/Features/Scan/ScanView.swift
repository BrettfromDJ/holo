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
    /// The Pro page, when Free's monthly scans are used up.
    @State private var proPaywall: ProReason?
    /// When scanning into a deal: which side, and where each match goes.
    var dealSide: DealSide?
    var onPick: (@MainActor (ScanCandidate, ScanRead?) -> (ok: Bool, note: String))?
    /// The tray's title in place of "This scan" / "Coming in" (the simple Deal flow's "Their cards").
    var trayTitle: String? = nil

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
            if Demo.isOn, ["matched", "tray"].contains(Demo.value("-HoloScanSample") ?? ""), let p = store.products["sample:charizard-ex-151"] {
                let hit = ScanCandidate(product: p, printing: nil, printings: p.printings ?? [], market: store.marketPrice(p.id, printing: p.printings?.first)?.market, score: 0.9)
                model.add(matched: ScanResult(status: "matched", message: nil, read: nil, candidates: [hit], scansRemaining: nil), photo: Data(), thumbnail: nil)
                try? await Task.sleep(nanoseconds: 800_000_000)
                // "tray" leaves it in the tray (the latest scan, big); "matched" opens its card page;
                // -HoloScanList opens the tray's list.
                if Demo.value("-HoloScanSample") == "matched", let first = model.entries.first { editing = EditingScan(id: first.id) }
                if ProcessInfo.processInfo.arguments.contains("-HoloScanList") { expanded = true }
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
        .proPaywall($proPaywall)
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
        ScanTray(model: model, dealSide: dealSide, title: trayTitle, expanded: $expanded, onOpen: { open($0) },
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
            guard Pro.shared.canScan else { proPaywall = .scans; return }
            Pro.shared.countScan()
            Haptics.tap()
            flashOnce()
            model.add(matched: OnDeviceScan.result(for: live.hit), photo: live.crop.jpeg, thumbnail: live.crop.image)
            return
        }
        guard model.blocked == nil else { return }
        // Free: 20 scans a month, then the Pro page.
        guard Pro.shared.canScan else { proPaywall = .scans; return }
        Pro.shared.countScan()
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
    var title: String?
    @Binding var expanded: Bool
    var onOpen: (ScanModel.Entry) -> Void
    var onNext: () -> Void
    var onDone: () -> Void
    @State private var clearing = false
    /// The scan whose Change card sheet is open.
    @State private var changing: EditingScan?
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
        .sheet(item: $changing) { e in ChangeCardSheet(model: model, id: e.id) }
    }

    private var tray: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
        return VStack(spacing: 0) {
            // Nothing scanned yet: just the how-to (no header, no $0.00 total or greyed buttons).
            if !model.entries.isEmpty {
            HStack {
                // What this scan is, and the running total.
                HStack(spacing: 8) {
                    Text(title ?? (dealSide == nil ? "This scan" : (dealSide == .incoming ? "Coming in" : "Going out")))
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
            }
            Group {
                if expanded {
                    // Every scan, top to bottom, newest first.
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 8) {
                            ForEach(model.entries) { e in
                                listRow(e)
                                    // Swipe either way to remove.
                                    .swipeAway(e.picked?.product.name ?? "this scan") { withAnimation(.snappy) { model.remove(e.id) } }
                                    .transition(.opacity)
                            }
                        }
                        .padding(.horizontal, 20).padding(.vertical, 8)
                    }
                    .scrollClipDisabled()
                } else if model.entries.isEmpty {
                    EmptyScanTray()
                } else if let latest = model.entries.first {
                    // The card you just scanned, big: its picture, then what it is, its price and
                    // its printing and condition to change right here. The count above opens the rest.
                    LatestScan(entry: latest, owned: owned(latest), inDeal: model.onPick != nil,
                               onOpen: { Haptics.tap(); onOpen(latest) },
                               onChange: { Haptics.tap(); changing = EditingScan(id: latest.id) },
                               setPrinting: { model.setPrinting(latest.id, $0) },
                               setCondition: { model.setCondition(latest.id, $0) })
                        .id(latest.id)
                        .transition(.opacity)
                        .padding(.horizontal, 16)
                }
            }
            .frame(height: expanded ? min(CGFloat(model.entries.count) * 120 + 16, 480) : (model.entries.isEmpty ? 196 : 222))
            .padding(.vertical, 4)
            if !model.entries.isEmpty {
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

    /// One scan in the opened-out list: a matched card as a row you can edit in place (its
    /// printing and condition), anything else as its tile.
    @ViewBuilder private func listRow(_ e: ScanModel.Entry) -> some View {
        if e.state == .done, e.picked != nil, !e.rejected {
            ScanListRow(entry: e, owned: owned(e), inDeal: model.onPick != nil,
                        onOpen: { Haptics.tap(); onOpen(e) },
                        setPrinting: { model.setPrinting(e.id, $0) },
                        setCondition: { model.setCondition(e.id, $0) })
        } else {
            chip(e, fills: true)
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

/// The latest scan, big, in the tray: its picture (tap for the full card, or Change card), and
/// beside it the name, number and set, the price, and menus for its printing and condition.
private struct LatestScan: View {
    var entry: ScanModel.Entry
    var owned: Int
    /// Scanning into a deal: the deal sets the price, so no printing or condition menus.
    var inDeal: Bool
    var onOpen: () -> Void
    /// Change card: the next best matches, or search.
    var onChange: () -> Void
    var setPrinting: (String?) -> Void
    var setCondition: (String) -> Void

    private var matched: Bool { entry.state == .done && entry.picked != nil && !entry.rejected }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            picture
            panel
        }
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    // MARK: The picture, with Change card under it

    private var picture: some View {
        Button(action: onOpen) {
            Group {
                if let p = entry.picked?.product {
                    ProductImage(product: p, cornerRadius: 9)
                } else if let img = entry.thumbnail {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Color.white.opacity(0.06)
                }
            }
            .frame(width: 128, height: 178)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            // Bright, half over the card's bottom edge: easy to find (a little smaller than before;
            // the tap area reaches past it).
            Button(action: matched ? onChange : onOpen) {
                HStack(spacing: 5) {
                    Image(systemName: matched ? "arrow.left.arrow.right" : "magnifyingglass").font(.system(size: 11, weight: .bold))
                    Text(matched ? "Wrong card?" : "Pick card").font(.geist(13, .semibold))
                }
                .foregroundStyle(Theme.lime)
                .padding(.horizontal, 11).frame(height: 30)
                .background(Capsule().fill(Color(hex: 0x111111)))
                .overlay(Capsule().strokeBorder(Theme.lime.opacity(0.45), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
                .fixedSize()
                .contentShape(Capsule().inset(by: -6))
            }
            .buttonStyle(.plain)
            .offset(y: 13)
            .accessibilityLabel(matched ? "Wrong card? Change it" : "Pick the right card")
        }
        .accessibilityLabel("Open this card")
    }

    // MARK: What it is, its price and the menus

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if owned > 0 { SkewTag(text: "Owned ×\(owned)", icon: "checkmark").padding(.bottom, 6) }
            Text(title).font(.geist(18, .semibold)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.85)
            if let sub = subtitle {
                Text(sub).font(.geist(13)).foregroundStyle(Theme.muted).lineLimit(1).padding(.top, 2)
            }
            if matched, entry.isBestGuess { BestGuessLabel().padding(.top, 4) }
            Spacer(minLength: 6)
            if matched {
                Text(Format.money(entry.value)).font(.display(30)).tracking(-0.9).padding(.trailing, 0.9).monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: entry.value)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if !inDeal {
                    ScanEditMenus(entry: entry, setPrinting: setPrinting, setCondition: setCondition).padding(.top, 8)
                }
            } else {
                Text(note).font(.geist(13)).foregroundStyle(Theme.muted).lineLimit(3)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 178, maxHeight: 178, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(matched ? Theme.lime.opacity(0.07) : Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(matched ? Theme.lime.opacity(0.32) : Color.white.opacity(0.1), lineWidth: 1))
    }

    private var title: String {
        switch entry.state {
        case .queued, .reading: return "Reading…"
        case .failed: return "Couldn't read it"
        case .done:
            if let p = entry.picked { return p.product.name }
            return entry.result?.status == "ambiguous" ? "Which one is it?" : "No match"
        }
    }

    private var subtitle: String? {
        guard entry.state == .done, let p = entry.picked?.product else { return nil }
        let line = [p.number.map { "#\($0)" }, p.setName].compactMap { $0 }.joined(separator: " · ")
        return line.isEmpty ? nil : line
    }

    private var note: String {
        if entry.rejected, let n = entry.note { return n }
        switch entry.state {
        case .queued, .reading: return "Finding the card and its price."
        case .failed: return "Tap the picture to try again."
        case .done: return entry.result?.status == "ambiguous" ? "Tap the picture to choose between close matches." : "Tap the picture to search for it."
        }
    }

}

/// A matched scan in the opened-out list (and the review): its picture (tap for the card), name
/// and price, number and set, its printing and condition to change right here, and (in the
/// review) how you got it, "Bought $X" with a pencil, opening its purchase details.
struct ScanListRow: View {
    var entry: ScanModel.Entry
    var owned: Int
    var inDeal: Bool
    var onOpen: () -> Void
    var setPrinting: (String?) -> Void
    var setCondition: (String) -> Void
    /// The scan's default, bought at market or pulled (what the pill says for an untouched card).
    var pulled = false
    /// Opens the purchase details; nil hides the pill.
    var onPurchase: (() -> Void)? = nil

    /// "Bought" and the price, or "Pulled": the card's own details, a typed price, or the default.
    private var purchase: (word: String, price: String?, own: Bool) {
        if let d = entry.draft {
            if d.pulled { return ("Pulled", nil, true) }
            let extra = d.purchase.shipping + d.purchase.tax + d.purchase.fees
            return ("Bought", Format.money(d.purchase.unitPrice) + (extra > 0 ? " +\(Format.money(extra))" : ""), true)
        }
        if !entry.paid.isEmpty {
            let typed = Double(entry.paid.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ""))
            return ("Bought", typed.map { Format.money($0) } ?? entry.paid, true)
        }
        if pulled { return ("Pulled", nil, false) }
        return ("Bought", Format.money(entry.value), false)
    }

    var body: some View {
        let p = entry.picked!.product
        HStack(alignment: .top, spacing: 12) {
            Button(action: onOpen) {
                ProductImage(product: p, cornerRadius: 6).frame(width: 62, height: 86)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Open \(p.name)")
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(p.name).font(.geist(16, .semibold)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(Format.money(entry.value)).font(.geist(16, .semibold)).monospacedDigit().foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                Text([p.number.map { "#\($0)" }, p.setName].compactMap { $0 }.joined(separator: " · "))
                    .font(.geist(12)).foregroundStyle(Theme.muted).lineLimit(1)
                if entry.isBestGuess || owned > 0 {
                    HStack(spacing: 8) {
                        if entry.isBestGuess { BestGuessLabel() }
                        if owned > 0 { SkewTag(text: "Owned ×\(owned)", icon: "checkmark") }
                    }
                    .padding(.top, 2)
                }
                // Printing, condition and how you got it, side by side in one row.
                if !inDeal {
                    HStack(spacing: 6) {
                        ScanEditMenus(entry: entry, setPrinting: setPrinting, setCondition: setCondition)
                        if let onPurchase { purchasePill(onPurchase) }
                    }
                    .padding(.top, 6)
                }
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
        .contentShape(Rectangle())
    }

    /// "Bought $X" (or "Pulled") with a lime pencil: the purchase details.
    private func purchasePill(_ action: @escaping () -> Void) -> some View {
        let p = purchase
        return Button(action: action) {
            HStack(spacing: 5) {
                Text(p.word).foregroundStyle(Theme.muted)
                if let price = p.price { Text(price).foregroundStyle(.white).monospacedDigit() }
                if let d = entry.draft, let co = d.purchase.gradeCompany, let g = d.purchase.grade {
                    Text("· \(co) \(d.pristine ? "Pristine 10" : g)").foregroundStyle(.white)
                }
                Image(systemName: "pencil").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.lime)
            }
            .font(.geist(13, .semibold))
            .lineLimit(1)
            .padding(.horizontal, 10).frame(height: 32)
            .background(Capsule().fill(Color.white.opacity(p.own ? 0.14 : 0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
        .fixedSize()
        .accessibilityLabel("\(p.word) \(p.price ?? ""). Edit purchase details")
    }
}

/// The tray before anything is scanned: three card outlines, the middle one in the lime scan
/// corners, and how to scan. Still: nothing moves.
private struct EmptyScanTray: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: -10) {
                ghost.rotationEffect(.degrees(-9)).offset(y: 6)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 58, height: 81)
                    .overlay(ScanCorners(radius: 7).stroke(Theme.lime, style: StrokeStyle(lineWidth: 2, lineCap: .round)))
                    .zIndex(1)
                ghost.rotationEffect(.degrees(9)).offset(y: 6)
            }
            VStack(spacing: 4) {
                Text("Tap to scan").font(.display(20)).tracking(-0.4)
                // Lines of even length, centred.
                BalancedText(text: "Hold a card in the frame, then tap the screen. Scan as many as you like.",
                             font: .geist(13), lineGap: 1, color: Theme.muted, alignment: .center)
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .accessibilityElement(children: .combine)
    }

    private var ghost: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(width: 48, height: 67)
    }
}

/// "Best guess": the scan picked the closest of several matches. Check it (Wrong card? lists the others).
private struct BestGuessLabel: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "questionmark.circle").font(.system(size: 11, weight: .semibold))
            Text("Best guess")
        }
            .font(.geist(12, .medium)).foregroundStyle(Theme.muted)
            .accessibilityLabel("Best guess: check it's the right card")
    }
}

/// A scan's printing and condition, as two small menus (the tray's latest scan and the list).
private struct ScanEditMenus: View {
    var entry: ScanModel.Entry
    var setPrinting: (String?) -> Void
    var setCondition: (String) -> Void

    var body: some View {
        if let p = entry.picked, !p.product.isSealed, !entry.isSlab {
            HStack(spacing: 6) {
                if p.printings.count > 1 || (p.product.printings?.count ?? 0) > 1 { printingMenu(p) }
                conditionMenu
            }
        }
    }

    private func printingMenu(_ p: ScanCandidate) -> some View {
        let options = Editions.ordered(p.printings.isEmpty ? (p.product.printings ?? []) : p.printings)
        let current = entry.printing ?? p.printing ?? options.first ?? ""
        return Menu {
            Picker("Printing", selection: Binding(get: { current }, set: { setPrinting($0) })) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
        } label: {
            pill(icon: "square.stack", text: current)
        }
        .menuStyle(.button).buttonStyle(.borderless)
    }

    private var conditionMenu: some View {
        let current = CardCondition(rawValue: entry.condition) ?? .nearMint
        return Menu {
            Picker("Condition", selection: Binding(get: { entry.condition }, set: { setCondition($0) })) {
                ForEach(CardCondition.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(current.tint).frame(width: 7, height: 7)
                Text(current.short).font(.geist(13, .semibold))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.muted)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).frame(height: 32)
            .background(Capsule().fill(Color.white.opacity(0.1)))
            .contentShape(Capsule())
        }
        .menuStyle(.button).buttonStyle(.borderless)
        .fixedSize()
    }

    private func pill(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.muted)
            Text(text).font(.geist(13, .semibold)).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.muted)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10).frame(height: 32)
        .background(Capsule().fill(Color.white.opacity(0.1)))
        .contentShape(Capsule())
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
            Image(systemName: "camera").font(.system(size: 28, weight: .medium)).foregroundStyle(Theme.lime)
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
