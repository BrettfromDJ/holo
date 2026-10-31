import SwiftUI

/// A slab coming home: it slides up out of its sleeve, the sleeve drops away and the grade
/// stamps on with a heavy tap. Shown over the page after a submission is marked returned (and
/// for the newest returned slab the first time Grading opens in a session). Tap anywhere to
/// close. Under Reduce Motion the slab and its grade just appear.
struct SlabUnboxing: View {
    var product: Product?
    var company: String
    var grade: String
    /// Wait before playing (e.g. while a sheet slides down).
    var delay: Double = 0
    var onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var risen = false
    @State private var sleeveGone = false
    @State private var stamped = false

    private static let stageWidth: CGFloat = 240
    private static let stageHeight: CGFloat = 440
    private static let slabWidth: CGFloat = 180
    private static let slabHeight: CGFloat = 288
    private static let sleeveHeight: CGFloat = 170
    /// Where the slab sits once it's out: centered on the stage.
    private static let restOffset: CGFloat = (stageHeight - slabHeight) / 2 - 20
    /// Where it starts: tucked below the sleeve's lip.
    private static let startOffset: CGFloat = stageHeight - sleeveHeight

    var body: some View {
        ZStack {
            Color.black.opacity(0.84).ignoresSafeArea()
            VStack(spacing: 22) {
                MonoLabel(text: "Back from \(company)")
                stage
                Text("Tap to close").font(.mono(11)).foregroundStyle(Theme.muted)
            }
            .padding(16)
        }
        .opacity(shown ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture { onDone() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(product?.name ?? "Card"), \(company) \(grade). Tap to close.")
        .accessibilityAddTraits(.isButton)
        .sensoryFeedback(.impact(weight: .heavy), trigger: stamped) { _, now in now }
        .task { await play() }
    }

    /// The slab behind the sleeve's front, on a stage that clips anything below its floor.
    private var stage: some View {
        ZStack(alignment: .top) {
            Slab(product: product, company: company, grade: grade)
                .frame(width: Self.slabWidth, height: Self.slabHeight)
                .overlay(alignment: .bottomTrailing) { stamp }
                .padding(.top, 20)
                .offset(y: risen ? (sleeveGone ? Self.restOffset : 0) : Self.startOffset)
            sleeve
                .frame(maxHeight: .infinity, alignment: .bottom)
                .offset(y: sleeveGone ? Self.sleeveHeight + 20 : 0)
                .opacity(sleeveGone ? 0 : 1)
        }
        .frame(width: Self.stageWidth, height: Self.stageHeight, alignment: .top)
        .clipped()
    }

    /// A card sleeve: a dark pouch with a lit lip and a thumb notch.
    private var sleeve: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return shape
            .fill(LinearGradient(colors: [Theme.surface3, Theme.surface], startPoint: .top, endPoint: .bottom))
            .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 1))
            .overlay(alignment: .top) {
                Capsule().fill(Color.black.opacity(0.55)).frame(width: 64, height: 14).offset(y: -7)
            }
            .overlay(alignment: .top) {
                Rectangle().fill(.white.opacity(0.22)).frame(height: 1).padding(.horizontal, 14).padding(.top, 1)
            }
            .overlay {
                Text("HOLO").font(.mono(11)).tracking(2).foregroundStyle(.white.opacity(0.25))
            }
            .frame(width: Self.stageWidth - 10, height: Self.sleeveHeight)
    }

    /// The grade, stamped onto the slab's corner.
    private var stamp: some View {
        Text("\(company) \(grade)")
            .font(.display(34)).tracking(-0.8).monospacedDigit()
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Theme.lime, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .rotationEffect(.degrees(-8))
            .scaleEffect(stamped ? 1 : 2.4)
            .opacity(stamped ? 1 : 0)
            .offset(x: 18, y: -18)
    }

    private func play() async {
        if reduceMotion {
            shown = true; risen = true; sleeveGone = true; stamped = true
            return
        }
        if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        withAnimation(.easeOut(duration: 0.25)) { shown = true }
        try? await Task.sleep(nanoseconds: 280_000_000)
        withAnimation(.spring(response: 0.75, dampingFraction: 0.84)) { risen = true }
        try? await Task.sleep(nanoseconds: 700_000_000)
        withAnimation(.easeInOut(duration: 0.45)) { sleeveGone = true }
        try? await Task.sleep(nanoseconds: 380_000_000)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { stamped = true }
    }
}
