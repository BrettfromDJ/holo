import CoreMotion
import SwiftUI

// MARK: - Replaying when a page comes back

private struct ReplayKey: EnvironmentKey { static let defaultValue = 0 }

extension EnvironmentValues {
    /// Goes up each time the page comes back into view (switching tabs, or back from a pushed
    /// page). Animations watch it and play again. 0 means the page hasn't appeared yet.
    var replay: Int {
        get { self[ReplayKey.self] }
        set { self[ReplayKey.self] = newValue }
    }
}

extension View {
    /// Put on a page: its count-ups, reveals, charts and entrances replay every time it reappears.
    func replaysAnimations() -> some View { modifier(ReplayOnAppear()) }

    /// Runs `action` when the page comes back (not on its first appearance).
    func onReplay(_ action: @escaping () -> Void) -> some View { modifier(OnReplay(action: action)) }
}

private struct ReplayOnAppear: ViewModifier {
    @State private var token = 0

    func body(content: Content) -> some View {
        content
            .environment(\.replay, token)
            .onAppear { token += 1 }
    }
}

private struct OnReplay: ViewModifier {
    var action: () -> Void
    @Environment(\.replay) private var replay

    func body(content: Content) -> some View {
        content.onChange(of: replay) { old, _ in if old > 0 { action() } }
    }
}

// MARK: - Counting numbers

/// A number that counts to its value: up from 85% when it first appears, and from the old
/// value to the new one whenever it changes (a refresh), easing out like the website's. A soft
/// tap lands when the count settles (once per count, never per frame; see `CountTap`).
struct CountingText: View {
    var value: Double
    var format: (Double) -> String
    var duration: Double = 1.3
    /// Wait before counting (e.g. until a sheet has slid up).
    var delay: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double?
    /// Goes up when a count settles and wins the shared throttle: plays the soft tap.
    @State private var taps = 0

    var body: some View {
        CountingLabel(value: shown ?? value * 0.85, format: format)
            .onAppear {
                guard shown == nil else { return }
                if reduceMotion { shown = value; return }
                shown = value * 0.85
                withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: duration).delay(delay)) { shown = value } completion: { settled() }
            }
            .onChange(of: value) { _, new in
                if reduceMotion { shown = new; return }
                withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.9)) { shown = new } completion: { settled() }
            }
            .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: taps)
            .onReplay {
                guard !reduceMotion else { return }
                shown = value * 0.85
                withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: duration)) { shown = value }
            }
    }
}

extension CountingText {
    private func settled() {
        if CountTap.claim() { taps += 1 }
    }
}

/// One soft tap for counters that settle together: a page full of count-ups finishing at once
/// gives a single tap, not a burst.
enum CountTap {
    private static var last = Date.distantPast

    /// True (and starts the quiet window) when no counter has tapped in the last half second.
    static func claim() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(last) > 0.5 else { return false }
        last = now
        return true
    }
}

/// Text whose number is animatable, so SwiftUI redraws it at every step of the count.
private struct CountingLabel: View, Animatable {
    var value: Double
    var format: (Double) -> String
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View { Text(format(value)) }
}

/// Flashes a colored number once when it appears: a quick glow in its own color.
struct FlashOnAppear: ViewModifier {
    var color: Color
    var delay: Double = 0.9
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(lit ? 0.9 : 0), radius: lit ? 14 : 0)
            .brightness(lit ? 0.12 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.25).delay(delay)) { lit = true }
                withAnimation(.easeIn(duration: 0.6).delay(delay + 0.3)) { lit = false }
            }
            .onReplay {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.25).delay(delay)) { lit = true }
                withAnimation(.easeIn(duration: 0.6).delay(delay + 0.3)) { lit = false }
            }
    }
}

extension View {
    func flashOnAppear(_ color: Color, delay: Double = 0.9) -> some View { modifier(FlashOnAppear(color: color, delay: delay)) }
}

// MARK: - Reveal on scroll

extension View {
    /// Runs once when the view first scrolls into sight (iOS 18), or when it appears on iOS 17.
    @ViewBuilder func onFirstVisible(_ action: @escaping () -> Void) -> some View {
        if #available(iOS 18, *) {
            onScrollVisibilityChange(threshold: 0.01) { visible in if visible { action() } }
        } else {
            onAppear(perform: action)
        }
    }

    /// Lifts and fades a section in the first time it scrolls into view, like the website.
    func reveal() -> some View { modifier(Reveal()) }
}

private struct Reveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 28)
            .scaleEffect(shown || reduceMotion ? 1 : 0.98, anchor: .top)
            .onFirstVisible {
                guard !shown else { return }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { shown = true }
            }
            .onReplay {
                guard shown, !reduceMotion else { return }
                shown = false
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.05)) { shown = true }
            }
    }
}

// MARK: - Charts drawing in

extension View {
    /// Draws a chart in left to right the first time it scrolls into view (and again whenever
    /// `replay` changes, e.g. a new range), like the Performance chart.
    func drawIn<T: Equatable>(replay: T, duration: Double = 1.2) -> some View { modifier(DrawIn(replay: replay, duration: duration, delay: 0)) }
    func drawIn(duration: Double = 1.2, delay: Double = 0) -> some View { modifier(DrawIn(replay: 0, duration: duration, delay: delay)) }
}

private struct DrawIn<T: Equatable>: ViewModifier {
    var replay: T
    var duration: Double
    var delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .mask(alignment: .leading) {
                GeometryReader { geo in Rectangle().frame(width: geo.size.width * (reduceMotion ? 1 : drawn)) }
            }
            .onFirstVisible {
                guard drawn == 0 else { return }
                withAnimation(.easeInOut(duration: duration).delay(delay)) { drawn = 1 }
            }
            .onChange(of: replay) { _, _ in
                drawn = 0
                withAnimation(.easeInOut(duration: duration * 0.7)) { drawn = 1 }
            }
            .onReplay {
                guard drawn > 0, !reduceMotion else { return }
                drawn = 0
                withAnimation(.easeInOut(duration: duration)) { drawn = 1 }
            }
    }
}

// MARK: - Tilt

/// The phone's tilt, smoothed, for cards that lean as you move it. Runs only while something
/// on screen is listening, at 30 updates a second.
@Observable
final class Tilt {
    static let shared = Tilt()

    /// -1...1 left/right and up/down from where the phone was held when it started.
    private(set) var x: Double = 0
    private(set) var y: Double = 0
    /// The same reading, without making the reader redraw when it changes: for views that
    /// already redraw on their own timeline (HoloCard), so a tilt doesn't redraw them twice.
    @ObservationIgnored private(set) var quietX: Double = 0
    @ObservationIgnored private(set) var quietY: Double = 0

    private let manager = CMMotionManager()
    private var listeners = 0
    private var origin: CMAttitude?

    func start() {
        listeners += 1
        guard listeners == 1, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            // Hold still under a sheet: moving cards behind glass make it re-blur every frame.
            if SheetCover.shared.isOpen { return }
            if self.origin == nil { self.origin = motion.attitude.copy() as? CMAttitude }
            let att = motion.attitude
            if let origin = self.origin { att.multiply(byInverseOf: origin) }
            let nx = max(-1, min(1, att.roll / 0.5))
            let ny = max(-1, min(1, att.pitch / 0.5))
            // Ease toward the reading so the cards glide rather than jitter.
            let ex = self.quietX + (nx - self.quietX) * 0.2
            let ey = self.quietY + (ny - self.quietY) * 0.2
            self.quietX = ex
            self.quietY = ey
            // Only tell the views when the lean has visibly moved: easing never quite settles,
            // so without this every tilting card redrew 30 times a second while the phone sat still.
            if abs(ex - self.x) > 0.001 { self.x = ex }
            if abs(ey - self.y) > 0.001 { self.y = ey }
        }
    }

    func stop() {
        listeners = max(0, listeners - 1)
        guard listeners == 0 else { return }
        manager.stopDeviceMotionUpdates()
        origin = nil
        x = 0
        y = 0
        quietX = 0
        quietY = 0
    }
}

/// Leans a card with the phone's tilt; with `foil`, a rainbow sheen slides across it as it
/// moves, like light on a holo card.
struct TiltCard: ViewModifier {
    var amount: Double = 10
    var foil = false
    var cornerRadius: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var tilt: Tilt { Tilt.shared }

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .overlay {
                    if foil {
                        LinearGradient(
                            colors: [.clear, Color(hex: 0xFF6AD5).opacity(0.35), Color(hex: 0x8AF5FF).opacity(0.35),
                                     Color(hex: 0xD4FF3A).opacity(0.35), .clear],
                            startPoint: UnitPoint(x: 0.0 + tilt.x * 0.6, y: 0.0 + tilt.y * 0.6),
                            endPoint: UnitPoint(x: 1.0 + tilt.x * 0.6, y: 1.0 + tilt.y * 0.6)
                        )
                        .blendMode(.overlay)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .allowsHitTesting(false)
                    }
                }
                .rotation3DEffect(.degrees(tilt.x * amount), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .rotation3DEffect(.degrees(-tilt.y * amount * 0.7), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                .onAppear { Tilt.shared.start() }
                .onDisappear { Tilt.shared.stop() }
        }
    }
}

extension View {
    func tiltCard(_ amount: Double = 10, foil: Bool = false, cornerRadius: CGFloat = 8) -> some View {
        modifier(TiltCard(amount: amount, foil: foil, cornerRadius: cornerRadius))
    }
}

// MARK: - On screen or not

extension View {
    /// Tells `action` whether this view is on screen: scrolled into view and on the tab you're
    /// looking at. Looping animations use it to stop while nobody can see them.
    func onVisibilityChange(_ action: @escaping (Bool) -> Void) -> some View {
        modifier(VisibilityChange(action: action))
    }
}

private struct VisibilityChange: ViewModifier {
    var action: (Bool) -> Void
    @Environment(\.onGlassSheet) private var onGlass
    @State private var seen = false

    /// Loops run only when seen, not inside a glass sheet, and not under one: anything moving
    /// behind or on a glass sheet makes iOS redraw its blur every frame, and taps feel slow.
    private func report() { action(seen && !onGlass && !SheetCover.shared.isOpen) }

    func body(content: Content) -> some View {
        let covered = SheetCover.shared.isOpen
        if #available(iOS 18, *) {
            content
                .onScrollVisibilityChange(threshold: 0.01) { seen = $0; report() }
                .onAppear { seen = true; report() }
                .onDisappear { seen = false; report() }
                .onChange(of: covered) { _, _ in report() }
        } else {
            content
                .onAppear { seen = true; report() }
                .onDisappear { seen = false; report() }
                .onChange(of: covered) { _, _ in report() }
        }
    }
}

/// How many glass sheets are up. Looping animations pause while any is (see VisibilityChange).
@Observable
final class SheetCover {
    static let shared = SheetCover()
    private(set) var count = 0
    var isOpen: Bool { count > 0 }
    @MainActor func opened() { count += 1 }
    @MainActor func closed() { count = max(0, count - 1) }
}

/// Stop a looping animation at once, without animating back.
func stopLoop(_ change: () -> Void) {
    var t = Transaction()
    t.disablesAnimations = true
    withTransaction(t, change)
}

// MARK: - Back to the top on a tab tap

/// A tab's main scroll view: when its tab-bar button is tapped (from anywhere, even itself),
/// any pages pushed on top close and the page scrolls back to the top.
struct TabTopReset: ViewModifier {
    let tab: String
    @Binding var path: NavigationPath

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.modifier(TabTopReset18(tab: tab, path: $path))
        } else {
            content.onChange(of: Router.shared.tabTap) { _, tap in
                if tap.name == tab, !path.isEmpty { path = NavigationPath() }
            }
        }
    }
}

@available(iOS 18, *)
private struct TabTopReset18: ViewModifier {
    let tab: String
    @Binding var path: NavigationPath
    @State private var position = ScrollPosition(edge: .top)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onChange(of: Router.shared.tabTap) { _, tap in
                guard tap.name == tab else { return }
                if !path.isEmpty { path = NavigationPath() }
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.35)) { position.scrollTo(edge: .top) }
            }
    }
}

extension View {
    func tabTopReset(_ tab: String, path: Binding<NavigationPath>) -> some View {
        modifier(TabTopReset(tab: tab, path: path))
    }
}
