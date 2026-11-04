import AVFoundation
import SwiftUI

/// Full-screen scanner. Shoot card after card; each lands in a slim strip you can
/// swipe through. Next opens the review, where you set what you paid and add them all.
struct ScanView: View {
    /// When scanning into a deal: which side, and where each match goes.
    var dealSide: DealSide?
    var onPick: (@MainActor (ScanCandidate, ScanRead?) -> (ok: Bool, note: String))?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = Camera()
    @State private var model = ScanModel()
    @State private var reviewing = false
    @State private var flash = false
    @State private var focused: UUID?
    @State private var torch = false
    @State private var clearing = false
    @State private var searchingManually = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session, running: camera.state == .running).ignoresSafeArea()
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
        .onAppear { camera.start() }
        .onDisappear { if torch { camera.setTorch(false) }; camera.stop() }
        // Search instead: into the collection, or (scanning into a deal) onto that side of it.
        .fullScreenCover(isPresented: Binding(get: { searchingManually && dealSide == nil }, set: { searchingManually = $0 })) { SearchScreen(mode: .add) }
        .sheet(isPresented: Binding(get: { searchingManually && dealSide != nil }, set: { searchingManually = $0 })) {
            if let dealSide { DealPickerSheet(side: dealSide) }
        }
        .task {
            model.onPick = onPick
            await model.refreshBalance()
        }
        .sheet(isPresented: $reviewing) {
            ScanReviewSheet(model: model, focus: focused, onAdded: { dismiss() })
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
            Group {
                if let left = model.scansLeft {
                    Text("\(left.formatted()) left").font(.mono(12)).monospacedDigit()
                        .padding(.horizontal, 12).frame(height: 44)
                        .liquidGlass(in: Capsule())
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: The light, beside the shutter

    private var rail: some View {
        VStack(spacing: 12) {
            if camera.hasTorch || camera.state != .running {
                railButton(torch ? "flashlight.on.fill" : "flashlight.off.fill", torch ? "Light on" : "Light", active: torch) {
                    torch.toggle()
                    camera.setTorch(torch)
                }
            }
        }
        .padding(.leading, 16)
    }

    private func railButton(_ icon: String, _ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 18, weight: .medium))
                Text(title).font(.geist(11, .medium)).lineLimit(1)
            }
            .foregroundStyle(active ? Theme.ink : .white)
            .frame(width: 60, height: 64)
            .background { if active { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.lime) } }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .background { Color.clear.liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous)).allowsHitTesting(false) }
        .accessibilityLabel(title)
    }

    // MARK: The card outline: a thin lime frame with a light sweeping down

    private var guide: some View {
        GeometryReader { geo in
            let h = min(geo.size.height * 0.86, geo.size.width * 0.62 * 88 / 63)
            let w = h * 63 / 88
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.lime, lineWidth: 2)
                    .shadow(color: Theme.lime.opacity(0.6), radius: 6)
                    .frame(width: w, height: h)
                ScanSweep(height: h)
                    .frame(width: w - 16, height: h)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        }
        .padding(.vertical, 10)
        .overlay {
            if camera.state == .denied {
                VStack(spacing: 14) {
                    Image(systemName: "camera.fill").font(.system(size: 30)).foregroundStyle(Theme.lime)
                    Text("Camera is off for Lucent").font(.display(22)).tracking(-0.6)
                    Text("Turn it on in Settings to scan cards.").font(.geist(14)).foregroundStyle(Theme.muted)
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

    // MARK: Bottom: the shutter, then the docked tray with the scans, the total and Next

    private var bottom: some View {
        VStack(spacing: 14) {
            if let blocked = model.blocked {
                Label(blocked, systemImage: "exclamationmark.triangle.fill")
                    .font(.geist(13, .medium)).foregroundStyle(.white)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), tint: Theme.planPink.opacity(0.4))
                    .padding(.horizontal, 16)
            }
            // The light on the left, level with the shutter in the middle.
            ZStack {
                shutter
                HStack {
                    rail
                    Spacer()
                }
            }
            tray
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: model.entries.count)
    }

    private var shutter: some View {
        Button(action: shoot) {
            ZStack {
                Circle().strokeBorder(.white, lineWidth: 4).frame(width: 78, height: 78)
                Circle().fill(Theme.lime).frame(width: 62, height: 62)
                    .shadow(color: Theme.lime.opacity(0.6), radius: 12)
                Image(systemName: "viewfinder").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.ink)
            }
        }
        .buttonStyle(ShutterStyle())
        .disabled(camera.state != .running || model.blocked != nil)
        .opacity(camera.state != .running || model.blocked != nil ? 0.5 : 1)
        .accessibilityLabel("Scan")
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
                            .overlay(Image(systemName: "rectangle.on.rectangle").font(.system(size: 16)).foregroundStyle(Theme.subtle))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("No cards yet").font(.geist(15, .semibold))
                            Text("Line a card up in the frame and tap the shutter.").font(.geist(13)).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 8) {
                            ForEach(Array(model.entries.reversed())) { e in
                                ScanChip(entry: e) {
                                    if e.state == .failed { model.retry(e.id) } else { focused = e.id; reviewing = true }
                                }
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .frame(height: 76)
            .padding(.vertical, 10)
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(Format.money(model.total)).font(.display(28)).tracking(-0.8).monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(model.picks.isEmpty ? "Total value" : "\(model.picks.count) matched").font(.geist(12)).foregroundStyle(Theme.muted)
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

    private func shoot() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeOut(duration: 0.05)) { flash = true }
        withAnimation(.easeOut(duration: 0.25).delay(0.05)) { flash = false }
        Task {
            do {
                let jpeg = try await camera.capture()
                await MainActor.run { model.add(photo: jpeg) }
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
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

/// A compact scan in the strip: what it matched and its price, or what it still needs.
struct ScanChip: View {
    var entry: ScanModel.Entry
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                thumb.frame(width: 36, height: 48).clipShape(RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    detail.font(.system(size: 12)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(width: 188, height: 64)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var thumb: some View {
        if let p = entry.picked?.product {
            ProductImage(product: p, cornerRadius: 5)
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
            Label("Try again", systemImage: "arrow.clockwise").foregroundStyle(.white.opacity(0.7))
        case .done:
            if entry.rejected, let note = entry.note {
                Text(note).foregroundStyle(Theme.down)
            } else if let p = entry.picked {
                (Text(p.product.number.map { "#\($0) · " } ?? "").foregroundStyle(.white.opacity(0.7))
                    + Text(Format.money(entry.value)).bold().foregroundStyle(.white))
                    .monospacedDigit()
            } else {
                Text(entry.result?.status == "ambiguous" ? "Tap to pick" : "Tap for details").foregroundStyle(Theme.warn)
            }
        }
    }
}
