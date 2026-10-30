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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session).ignoresSafeArea()
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
        .onDisappear { camera.stop() }
        .task {
            model.onPick = onPick
            await model.refreshBalance()
        }
        .sheet(isPresented: $reviewing) {
            ScanReviewSheet(model: model, focus: focused, onAdded: { dismiss() })
        }
    }

    // MARK: Top: close, what you're scanning, scans left (all Liquid Glass)

    private var topBar: some View {
        HStack(spacing: 8) {
            glassCircle("xmark", label: "Close") { dismiss() }
            Spacer()
            HStack(spacing: 8) {
                Circle().fill(dealSide == .outgoing ? Theme.planPink : Theme.lime).frame(width: 7, height: 7)
                Text(dealSide == nil ? "SCAN CARDS" : (dealSide == .incoming ? "COMING IN" : "GOING OUT"))
                    .font(.display(16)).tracking(0.6)
            }
            .padding(.horizontal, 16).frame(height: 40)
            .liquidGlass(in: Capsule())
            Spacer()
            Group {
                if let left = model.scansLeft {
                    Text("\(left.formatted()) left").font(.mono(12)).monospacedDigit()
                        .padding(.horizontal, 12).frame(height: 40)
                        .liquidGlass(in: Capsule())
                } else {
                    Color.clear.frame(width: 44, height: 40)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: The card outline: lime corners with a light sweeping down

    private var guide: some View {
        GeometryReader { geo in
            let h = min(geo.size.height * 0.88, geo.size.width * 0.8 * 88 / 63)
            let w = h * 63 / 88
            ZStack {
                ScanCorners(radius: 18)
                    .stroke(Theme.lime, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .shadow(color: Theme.lime.opacity(0.7), radius: 8)
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
                    Text("CAMERA IS OFF FOR HOLO").font(.display(22))
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

    // MARK: Bottom: the scans so far, then the glass tray with the shutter

    private var bottom: some View {
        VStack(spacing: 12) {
            if let blocked = model.blocked {
                Label(blocked, systemImage: "exclamationmark.triangle.fill")
                    .font(.geist(13, .medium)).foregroundStyle(.white)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), tint: Theme.planPink.opacity(0.4))
                    .padding(.horizontal, 16)
            }
            if !model.entries.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(Array(model.entries.reversed())) { e in
                            ScanChip(entry: e) {
                                if e.state == .failed { model.retry(e.id) } else { focused = e.id; reviewing = true }
                            }
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 64)
            }
            tray
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: model.entries.count)
    }

    private var tray: some View {
        HStack {
            // How many so far and their total.
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.entries.count)").font(.display(26)).monospacedDigit().foregroundStyle(.white).displayTrim(26)
                    .contentTransition(.numericText())
                Text(model.picks.isEmpty ? "scanned" : Format.money(model.total)).font(.geist(12, .semibold)).monospacedDigit()
                    .foregroundStyle(model.picks.isEmpty ? Theme.muted : Theme.lime)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(width: 84, alignment: .leading)
            Spacer()
            Button(action: shoot) {
                ZStack {
                    Circle().strokeBorder(.white, lineWidth: 4).frame(width: 80, height: 80)
                    Circle().fill(Theme.lime).frame(width: 64, height: 64)
                        .shadow(color: Theme.lime.opacity(0.6), radius: 12)
                    Image(systemName: "viewfinder").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.ink)
                }
            }
            .buttonStyle(ShutterStyle())
            .disabled(camera.state != .running || model.blocked != nil)
            .opacity(camera.state != .running || model.blocked != nil ? 0.5 : 1)
            .accessibilityLabel("Scan")
            Spacer()
            Button {
                // In a deal, scans are already in it: Done just closes the camera.
                if dealSide != nil {
                    dismiss()
                } else {
                    focused = nil
                    reviewing = true
                }
            } label: {
                HStack(spacing: 4) {
                    Text(dealSide == nil ? "Next" : "Done")
                    if dealSide == nil { Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold)) }
                }
            }
            .buttonStyle(Button3D(kind: .lime, fullWidth: false, height: 44))
            .frame(width: 84, alignment: .trailing)
            .opacity(model.entries.isEmpty ? 0 : 1)
            .disabled(model.entries.isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 36, style: .continuous))
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
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { down = true }
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
