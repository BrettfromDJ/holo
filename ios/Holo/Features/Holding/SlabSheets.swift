import SwiftUI

/// The certification number printed on a slab's label, like the website's Cert number dialog.
struct CertSheet: View {
    var holding: HoldingView
    @Environment(GradingStore.self) private var grading
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @FocusState private var focused: Bool

    var body: some View { sheetBody.glassSheet() }

    @ViewBuilder private var sheetBody: some View {
        NavigationStack {
            GlassForm {
                Section {
                    TextField("Cert number", text: $value)
                        .keyboardType(.numberPad)
                        .font(.mono(17))
                        .focused($focused)
                        .onChange(of: value) { _, v in if v.count > 20 { value = String(v.prefix(20)) } }
                } footer: {
                    Text("The certification number printed on the \(holding.identity.gradeCompany ?? "") label. Used to verify the slab, with a link to look it up.")
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Cert number")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        grading.setCert(holding.identity.key, value)
                        dismiss()
                    }
                }
            }
            .onAppear {
                value = grading.certs[holding.identity.key] ?? ""
                focused = true
            }
        }
        .presentationDetents([.medium])
    }
}

/// Pick a bumper guard for a slab, with a live preview, like the website's Bumper dialog.
struct BumperSheet: View {
    var holding: HoldingView
    @Environment(GradingStore.self) private var grading
    @Environment(\.dismiss) private var dismiss
    @State private var pick: String?
    /// The first bumper on this slab: a full-screen moment before the sheet closes.
    @State private var celebrating: String?

    var body: some View { sheetBody.presentationDetents([.fraction(0.93)]).glassSheet() }

    @ViewBuilder private var sheetBody: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let company = holding.identity.gradeCompany, let grade = holding.identity.grade {
                        Slab(product: holding.product, company: company, grade: grade, bumper: Bumper.byId(pick),
                             cert: grading.certs[holding.identity.key], pristine: grading.pristine.contains(holding.identity.key))
                            .frame(height: 260)
                            .frame(maxWidth: .infinity)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: pick)
                    }
                    group(.glitter, "Glitter")
                    group(.solid, "Solid")
                    Button("No bumper") { pick = nil }
                        .font(.geist(14, .medium)).foregroundStyle(pick == nil ? .white : Theme.muted)
                }
                .padding(20)
            }
            .navigationTitle(Bumper.byId(pick)?.name ?? "Bumper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let first = grading.bumpers[holding.identity.key] == nil
                        grading.setBumper(holding.identity.key, pick)
                        if first, let pick { celebrating = pick } else { dismiss() }
                    }
                }
            }
            .onAppear { pick = grading.bumpers[holding.identity.key] }
            .fullScreenCover(item: Binding(get: { celebrating.map(BumperMoment.Item.init) }, set: { if $0 == nil { celebrating = nil } })) { item in
                BumperMoment(holding: holding, bumperId: item.id) {
                    celebrating = nil
                    dismiss()
                }
                .presentationBackground(.clear)
            }
            .sensoryFeedback(.selection, trigger: pick)
        }
    }

    private func group(_ kind: Bumper.Kind, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(text: title)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                ForEach(Bumper.all.filter { $0.kind == kind }) { b in
                    Button { pick = b.id } label: {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(b.fill)
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.15)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(pick == b.id ? Color.white : .clear, lineWidth: 2)
                                    .padding(-4)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(b.name)
                }
            }
        }
    }
}

/// The first bumper on a slab, shown big: the slab rises into place in its new bumper with a
/// soft glow in the bumper's colour behind it. Tap anywhere or Done to close. No confetti; under
/// Reduce Motion it simply fades in.
struct BumperMoment: View {
    struct Item: Identifiable { var id: String }

    var holding: HoldingView
    var bumperId: String
    var onDone: () -> Void
    @Environment(GradingStore.self) private var grading
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        let bumper = Bumper.byId(bumperId)
        let glow = bumper?.colors.first ?? Theme.lime
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Theme.background.opacity(0.6).ignoresSafeArea()
            RadialGradient(colors: [glow.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 300)
                .ignoresSafeArea()
                .opacity(shown ? 1 : 0)
                .allowsHitTesting(false)
            VStack(spacing: 22) {
                Spacer(minLength: 0)
                if let company = holding.identity.gradeCompany, let grade = holding.identity.grade {
                    Slab(product: holding.product, company: company, grade: grade, bumper: bumper,
                         cert: grading.certs[holding.identity.key], pristine: grading.pristine.contains(holding.identity.key))
                        .frame(width: 250, height: 400)
                        .shadow(color: .black.opacity(0.5), radius: 24, y: 16)
                        .scaleEffect(shown || reduceMotion ? 1 : 0.86)
                        .rotation3DEffect(.degrees(shown || reduceMotion ? 0 : 14), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                        .offset(y: shown || reduceMotion ? 0 : 30)
                }
                VStack(spacing: 6) {
                    MonoLabel(text: "Bumper on")
                    Text(bumper?.name ?? "Bumper").font(.display(30)).tracking(-0.8)
                    Text(holding.product?.name ?? "").font(.geist(14)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                .multilineTextAlignment(.center)
                .opacity(shown ? 1 : 0)
                Spacer(minLength: 0)
                Button("Done", action: onDone)
                    .buttonStyle(Button3D(kind: .lime))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                    .opacity(shown ? 1 : 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDone)
        .sensoryFeedback(.success, trigger: shown) { _, now in now }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .spring(response: 0.6, dampingFraction: 0.78)) { shown = true }
        }
        .accessibilityAddTraits(.isModal)
    }
}
