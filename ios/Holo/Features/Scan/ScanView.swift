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
            if flash { Color.white.ignoresSafeArea().transition(.opacity) }

            // Shading so the controls read over any picture.
            VStack {
                LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom).frame(height: 160)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom).frame(height: 300)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                guide
                bottom
            }
        }
        .statusBarHidden()
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

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).frame(width: 40, height: 40).background(.black.opacity(0.45), in: Circle())
            }
            .accessibilityLabel("Close")
            Spacer()
            if let dealSide {
                Text(dealSide == .incoming ? "Coming in" : "Going out")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Theme.lime.opacity(0.9), in: Capsule())
                    .foregroundStyle(Theme.ink)
            }
            if let left = model.scansLeft {
                Text("\(left.formatted()) scans left")
                    .font(.footnote.weight(.medium)).monospacedDigit()
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.black.opacity(0.45), in: Capsule())
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// The card outline, in the open space between the top bar and the controls.
    private var guide: some View {
        GeometryReader { geo in
            let h = min(geo.size.height * 0.9, geo.size.width * 0.86 * 88 / 63)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.lime.opacity(0.9), lineWidth: 2)
                    .frame(width: h * 63 / 88, height: h)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.busy > 0 {
                    Label("\(model.busy) scanning", systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(12)
                }
            }
        }
        .overlay {
            if camera.state == .denied {
                VStack(spacing: 10) {
                    Text("Camera access is off").font(.headline)
                    Text("Turn it on in Settings to scan cards.").font(.callout).foregroundStyle(.white.opacity(0.7))
                    Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                }
                .foregroundStyle(.white)
            }
        }
    }

    private var bottom: some View {
        VStack(spacing: 12) {
            if let blocked = model.blocked {
                Text(blocked).font(.footnote).foregroundStyle(.white).padding(10).frame(maxWidth: .infinity)
                    .background(Theme.down.opacity(0.35), in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 16)
            }
            if !model.entries.isEmpty {
                HStack {
                    Text("\(model.entries.count) scanned")
                    Spacer()
                    if !model.picks.isEmpty {
                        Text("Total ").foregroundStyle(.white.opacity(0.7)) + Text(Format.money(model.total)).bold().foregroundStyle(.white)
                    }
                }
                .font(.footnote).monospacedDigit().foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(model.entries) { e in
                            ScanChip(entry: e) {
                                if e.state == .failed { model.retry(e.id) } else { focused = e.id; reviewing = true }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 64)
            }

            HStack {
                Color.clear.frame(width: 88, height: 44)
                Spacer()
                Button(action: shoot) {
                    ZStack {
                        Circle().fill(Theme.lime).frame(width: 72, height: 72)
                        Circle().stroke(Theme.ink.opacity(0.8), lineWidth: 3).frame(width: 58, height: 58)
                    }
                    .padding(5)
                    .background(Theme.lime.opacity(0.25), in: Circle())
                }
                .disabled(camera.state != .running || model.blocked != nil)
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
                        if dealSide == nil { Image(systemName: "arrow.right") }
                    }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 88, height: 44)
                        .background(.black.opacity(0.45), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.25)))
                }
                .opacity(model.entries.isEmpty ? 0 : 1)
                .disabled(model.entries.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
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
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.15)))
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
