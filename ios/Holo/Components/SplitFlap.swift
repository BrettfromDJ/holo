import SwiftUI

/// A number on a split-flap board, like a station departures sign: each character sits on a
/// small dark card split across the middle, and when it appears or changes the top half of the
/// old character folds down and the bottom half of the new one falls into place.
///
/// Takes its font and color from the environment (`.font(.display(60))`, `.foregroundStyle`).
/// Cheap: each flap is one `rotation3DEffect` animated twice per change; nothing is laid out per
/// frame. Reduce Motion shows plain text.
struct SplitFlap: View {
    var text: String
    var tile: Color = Theme.surface2
    var cornerRadius: CGFloat = 8
    /// How much of the font's line box to trim top and bottom (Anton's is tall: size × 0.06).
    var trim: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Slot: Hashable {
        /// Counted from the right, so "10" → "9" flips the ones and drops the tens.
        var place: Int
        var char: Character
    }

    var body: some View {
        Group {
            if reduceMotion {
                Text(text).padding(.vertical, -trim)
            } else {
                let chars = Array(text)
                let slots = chars.enumerated().map { Slot(place: chars.count - 1 - $0.offset, char: $0.element) }
                HStack(spacing: 3) {
                    ForEach(slots, id: \.place) { slot in
                        FlapCell(char: slot.char, delay: Double(chars.count - 1 - slot.place) * 0.08,
                                 tile: tile, cornerRadius: cornerRadius, trim: trim)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// One character's card: two static halves (new on top, old below) and two flaps that fold
/// over them, hinged on the middle line.
private struct FlapCell: View {
    var char: Character
    var delay: Double
    var tile: Color
    var cornerRadius: CGFloat
    var trim: CGFloat
    @State private var old: String
    @State private var new: String
    /// The falling top flap (old character): 0 flat, -90 edge-on (gone).
    @State private var topAngle: Double = 0
    /// The landing bottom flap (new character): 90 edge-on (not yet down), 0 flat.
    @State private var bottomAngle: Double = 90

    init(char: Character, delay: Double, tile: Color, cornerRadius: CGFloat, trim: CGFloat) {
        self.char = char
        self.delay = delay
        self.tile = tile
        self.cornerRadius = cornerRadius
        self.trim = trim
        // Starts on a blank card and flips to the character on appear.
        _old = State(initialValue: " ")
        _new = State(initialValue: String(char))
    }

    var body: some View {
        // Sized by a hidden digit, so every card is the same size whatever it shows.
        Text("0")
            .padding(.vertical, -trim)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .hidden()
            .overlay {
                ZStack {
                    half(new, top: true)
                    half(old, top: false)
                    half(old, top: true)
                        .rotation3DEffect(.degrees(topAngle), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.5)
                    half(new, top: false)
                        .rotation3DEffect(.degrees(bottomAngle), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.5)
                    // The split between the halves.
                    Rectangle().fill(Color.black.opacity(0.6)).frame(height: 1)
                }
            }
            .onAppear { flip(from: " ", to: String(char)) }
            .onChange(of: char) { was, now in flip(from: String(was), to: String(now)) }
    }

    /// Half of a card showing `s`: the whole card, masked to its top or bottom half.
    private func half(_ s: String, top: Bool) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(tile)
            .overlay { Text(s).fixedSize() }
            .mask {
                VStack(spacing: 0) {
                    if top {
                        Rectangle()
                        Color.clear
                    } else {
                        Color.clear
                        Rectangle()
                    }
                }
            }
    }

    private func flip(from a: String, to b: String) {
        // Set the cards up without animating, then fold the flaps on the next turn of the run
        // loop (so the reset isn't merged into the animation).
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            old = a
            new = b
            topAngle = 0
            bottomAngle = 90
        }
        DispatchQueue.main.async {
            withAnimation(.easeIn(duration: 0.16).delay(delay)) { topAngle = -90 }
            withAnimation(.easeOut(duration: 0.24).delay(delay + 0.16)) { bottomAngle = 0 }
        }
    }
}
