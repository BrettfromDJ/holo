import SwiftUI

/// The certification number printed on a slab's label, like the website's Cert number dialog.
struct CertSheet: View {
    var holding: HoldingView
    @Environment(GradingStore.self) private var grading
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
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
            .background(Theme.background)
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let company = holding.identity.gradeCompany, let grade = holding.identity.grade {
                        Slab(product: holding.product, company: company, grade: grade, bumper: Bumper.byId(pick))
                            .frame(height: 260)
                            .frame(maxWidth: .infinity)
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: pick)
                    }
                    group(.glitter, "Glitter")
                    group(.solid, "Solid")
                    Button("No bumper") { pick = nil }
                        .font(.geist(14, .medium)).foregroundStyle(pick == nil ? .white : Theme.muted)
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle(Bumper.byId(pick)?.name ?? "Bumper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        grading.setBumper(holding.identity.key, pick)
                        dismiss()
                    }
                }
            }
            .onAppear { pick = grading.bumpers[holding.identity.key] }
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
