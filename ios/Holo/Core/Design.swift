import SwiftUI
import UIKit

// The website's design language, in SwiftUI: Geist for text, (in Lucent, Geist too, sentence case) for
// headlines and big numbers, Geist Mono for small caps labels, lime accents, 3D buttons,
// hairline-bordered surfaces and slanted tags.

// MARK: - Type

extension Font {
    /// Headlines and big numbers. Lucent: Geist in sentence case, matching the glow cards
    /// (was Anton, tall condensed caps), SemiBold so big numbers have weight; sizes come down a
    /// fifth since Geist is wider than Anton.
    static func display(_ size: CGFloat) -> Font {
        .custom("Geist-SemiBold", size: (size * 0.8).rounded())
    }

    /// Geist, the body face.
    static func geist(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "Geist-Bold"
        case .semibold: name = "Geist-SemiBold"
        case .medium: name = "Geist-Medium"
        default: name = "Geist-Regular"
        }
        return .custom(name, size: size)
    }

    /// Geist Mono, for small uppercase labels ("TODAY", "COMING IN").
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(weight == .regular ? "GeistMono-Regular" : "GeistMono-Medium", size: size)
    }

    /// Roboto Mono, for the small all-caps card headings.
    static func roboto(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .custom(weight == .regular ? "RobotoMono-Regular" : "RobotoMono-Medium", size: size)
    }
}

enum Fonts {
    /// Use Geist in UIKit-drawn chrome too (navigation bars, segmented controls).
    static func applyAppearance() {
        let title = UIFont(name: "Geist-SemiBold", size: 17) ?? .systemFont(ofSize: 17, weight: .semibold)
        let large = UIFont(name: "Geist-SemiBold", size: 32) ?? .systemFont(ofSize: 32, weight: .semibold)
        let nav = UINavigationBarAppearance()
        // No bar behind the navigation: pages scroll up under the status bar and the floating
        // buttons, like the website on a phone.
        nav.configureWithTransparentBackground()
        nav.backgroundColor = .clear
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.font: title, .foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [.font: large, .foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        let item = UIFont(name: "Geist-Medium", size: 17) ?? .systemFont(ofSize: 17)
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: item], for: .normal)
        let seg = UIFont(name: "Geist-Medium", size: 13) ?? .systemFont(ofSize: 13, weight: .medium)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: seg], for: .normal)
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(Theme.lime)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: seg, .foregroundColor: UIColor(Theme.ink)], for: .selected)
        UISegmentedControl.appearance().backgroundColor = UIColor(Theme.surface2)
        // Pull to refresh spins in lime.
        UIRefreshControl.appearance().tintColor = UIColor(Theme.lime)
    }
}

// MARK: - Colors used by the website's plan cards and tags

extension Theme {
    static let planBlue = Color(hex: 0x2F5BFF)
    static let planPink = Color(hex: 0xFF2E9A)
    static let azure = Color(hex: 0x4A72FF)
    static let subtle = Color(hex: 0x636366)
    static let border = Color.white.opacity(0.07)
    static let borderStrong = Color.white.opacity(0.12)
    static let well = Color(hex: 0x18181A)
}

// MARK: - Page and section headers

/// "▍COLLECTION": a glowing lime bar and the title in Anton caps, with an optional subtitle.
struct PageHeader<Trailing: View>: View {
    var title: String
    var subtitle: String?
    var size: CGFloat = 34
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.display(size)).tracking(size * -0.03).lineLimit(2).minimumScaleFactor(0.7).displayTrim(size)
                if let subtitle {
                    Text(subtitle).font(.geist(15)).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension View {
    /// The page's title, small and centered in the top bar (Geist SemiBold).
    func pageTitle(_ title: String) -> some View {
        toolbar {
            ToolbarItem(placement: .principal) {
                // Long titles (a set's full name) shrink a little, then end in "…" on one line.
                Text(title).font(.geist(17, .semibold)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.85).truncationMode(.tail)
            }
        }
        // Never a bar behind the top: every page's header is fully transparent.
        .toolbarBackground(.hidden, for: .navigationBar)
        .clearTopEdge()
    }

    /// No tinted blur behind the top bar on iOS 26: content scrolls under a fully clear header.
    @ViewBuilder func clearTopEdge() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, size: CGFloat = 34) {
        self.init(title: title, subtitle: subtitle, size: size, trailing: { EmptyView() })
    }
}

/// A small uppercase mono label ("TODAY", "COST BASIS").
struct MonoLabel: View {
    var text: String
    var color: Color = Theme.muted

    var body: some View {
        Text(text.uppercased()).font(.mono(11)).tracking(1.2).foregroundStyle(color)
    }
}

// MARK: - Surfaces

/// The website's card: dark surface, hairline border, a faint sheen at the top.
struct Surface: ViewModifier {
    var radius: CGFloat = 20
    var padding: CGFloat? = 16
    @Environment(\.onGlassSheet) private var onGlass

    func body(content: Content) -> some View {
        if onGlass {
            content
                .padding(padding ?? 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .sheetPanel(radius: radius)
        } else {
            solid(content)
        }
    }

    private func solid(_ content: Content) -> some View {
        content
            .padding(padding ?? 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(0.035), .clear], startPoint: .top, endPoint: .center))
                    )
            )
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.border))
    }
}

/// A tinted card: the color washes down from the top edge (website "tint-*" cards).
struct Tinted: ViewModifier {
    var tint: Color
    var radius: CGFloat = 20
    var border = true

    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(RadialGradient(colors: [tint.opacity(0.30), .clear], center: .top, startRadius: 0, endRadius: 260))
                    )
            )
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(border ? tint.opacity(0.28) : .clear))
    }
}

extension View {
    func surface(radius: CGFloat = 20, padding: CGFloat? = 16) -> some View { modifier(Surface(radius: radius, padding: padding)) }
    func tinted(_ tint: Color, radius: CGFloat = 20, border: Bool = true) -> some View { modifier(Tinted(tint: tint, radius: radius, border: border)) }
}

// MARK: - Buttons

private struct OnGlassSheetKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// True inside a glass bottom sheet: panels and dark buttons draw as a faint white fill
    /// instead of a solid color, which reads cleanly on glass.
    var onGlassSheet: Bool {
        get { self[OnGlassSheetKey.self] }
        set { self[OnGlassSheetKey.self] = newValue }
    }
}

extension View {
    /// The app's bottom sheet look: Apple's glass (frosted on older iOS) under a dark wash, with
    /// see-through scroll and form backgrounds and glass-friendly panels and buttons.
    func glassSheet() -> some View {
        environment(\.onGlassSheet, true)
            .scrollContentBackground(.hidden)
            // No bar or blur behind a sheet's top either.
            .toolbarBackground(.hidden, for: .navigationBar)
            .clearTopEdge()
            .nativeGlassSheet()
            // While it's up, the page behind stops its looping motion (see SheetCover).
            .onAppear { SheetCover.shared.opened() }
            .onDisappear { SheetCover.shared.closed() }
    }

    /// A panel on a glass sheet: faint white fill, hairline white edge.
    func sheetPanel(radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(shape.fill(Color.white.opacity(0.07)))
            .overlay(shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }
}

/// A List for glass sheets: rows are a faint white fill instead of solid gray.
struct GlassList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        List {
            Group { content }
                .listRowBackground(Color.white.opacity(0.07))
        }
        .scrollContentBackground(.hidden)
    }
}

/// A Form for glass sheets: rows are a faint white fill instead of solid gray.
struct GlassForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            Group { content }
                .listRowBackground(Color.white.opacity(0.07))
        }
        .scrollContentBackground(.hidden)
    }
}

extension View {
    /// Apple's own Liquid Glass sheet background on iOS 26 (see-through, blurring the page
    /// behind); frosted material on older iOS and older Xcode.
    /// A dark wash over the glass keeps the blur and see-through but lets what's on it pop.
    @ViewBuilder func nativeGlassSheet() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            background(Color.black.opacity(0.65).ignoresSafeArea())
        } else {
            presentationBackground(.ultraThinMaterial)
                .background(Color.black.opacity(0.65).ignoresSafeArea())
        }
        #else
        presentationBackground(.ultraThinMaterial)
            .background(Color.black.opacity(0.65).ignoresSafeArea())
        #endif
    }
}

/// A full-width translucent capsule button, for buttons on glass sheets.
struct GlassButton: ButtonStyle {
    var height: CGFloat = 46

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.geist(16, .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: height)
            .contentShape(Capsule())
            // Sits on glass sheets: a faint fill reads better than glass on glass.
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.14 : 0.09)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// 3D buttons: lit top, solid bottom edge; pressing sinks onto the edge.
struct Button3D: ButtonStyle {
    enum Kind { case light, lime, dark, blue, pink }

    var kind: Kind = .lime
    var fullWidth = true
    var height: CGFloat = 50
    @Environment(\.onGlassSheet) private var onGlass

    private var fill: Color {
        switch kind {
        case .light: return Color(hex: 0xF5F5F7)
        case .lime: return Theme.lime
        case .dark: return onGlass ? Color.white.opacity(0.1) : Theme.surface2
        case .blue: return Theme.planBlue
        case .pink: return Theme.planPink
        }
    }

    private var edge: Color {
        switch kind {
        case .light: return Color(hex: 0x8A8A8E)
        case .lime: return Theme.limeEdge
        case .dark: return onGlass ? Color.white.opacity(0.04) : Color(hex: 0x0D0D0F)
        case .blue: return Color(hex: 0x1A2F9E)
        case .pink: return Color(hex: 0xA3175F)
        }
    }

    private var text: Color {
        switch kind {
        case .light, .lime: return Theme.ink
        case .dark, .blue, .pink: return .white
        }
    }

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if kind == .dark {
            // Dark buttons are Liquid Glass in the same rounded shape as the lime ones (a faint
            // white fill on glass sheets).
            glass(configuration)
        } else {
            solid(configuration)
        }
    }

    private func glass(_ configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(.geist(16, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background {
                if onGlass {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(pressed ? 0.14 : 0.09))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                } else {
                    Color.clear.liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: pressed)
            .sensoryFeedback(.impact(weight: .light), trigger: pressed) { _, isDown in isDown }
    }

    private func solid(_ configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shines = kind == .lime || kind == .blue || kind == .pink
        return configuration.label
            .font(.geist(16, .semibold))
            .foregroundStyle(text)
            .padding(.horizontal, 18)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            // The drop shadow falls from the label and the button's body as before, but not from
            // the sweeping sheen: a shadow on moving content is re-rendered every frame.
            .shadow(color: .black.opacity(0.5), radius: 9, y: 6)
            .background {
                if shines {
                    Sheen(strength: 0.5).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(edge).offset(y: pressed ? 0 : 3)
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(kind == .lime ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(fill))
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(kind == .dark ? 0.06 : 0.16), .clear], startPoint: .top, endPoint: .center))
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(kind == .dark ? 0.08 : 0.35), .clear], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.5), radius: 9, y: 6)
            )
            .offset(y: pressed ? 2 : -1)
            .scaleEffect(pressed ? 0.97 : 1)
            .modifier(ElectricGlow(color: fill, on: shines))
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pressed)
            .sensoryFeedback(.impact(weight: .light), trigger: pressed) { _, isDown in isDown }
    }
}

/// A streak of light that sweeps across a button every few seconds. One looping offset
/// animation set once on appear: nothing is laid out or redrawn per frame, the band just
/// slides, and it spends most of each loop off the button so the sweep reads as occasional.
struct Sheen: View {
    var strength: Double = 0.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var across = false

    var body: some View {
        if !reduceMotion {
            LinearGradient(colors: [.clear, .white.opacity(strength), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 44)
                .scaleEffect(x: 1, y: 2.4)
                .rotationEffect(.degrees(20))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(x: across ? 600 : -600)
                .allowsHitTesting(false)
                // Only runs while on screen.
                .onVisibilityChange { on in
                    if on {
                        withAnimation(.linear(duration: 4.5).repeatForever(autoreverses: false)) { across = true }
                    } else {
                        stopLoop { across = false }
                    }
                }
        }
    }
}

/// A slow breathing glow in a button's own color: a blurred copy of the shape behind it whose
/// opacity rises and falls. The blur is drawn once; only the opacity animates.
struct ElectricGlow: ViewModifier {
    var color: Color
    var on = true
    var radius: CGFloat = 14
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bright = false
    /// Room around the shape for the blur to spread into inside its flattened layer.
    private static let spread: CGFloat = 40

    func body(content: Content) -> some View {
        if on && !reduceMotion {
            content
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(color)
                        .padding(Self.spread)
                        .blur(radius: 14)
                        // Flattened into one layer once, so the breathing only fades that layer
                        // instead of re-blurring the shape on every frame.
                        .drawingGroup()
                        .padding(-Self.spread)
                        .opacity(bright ? 0.55 : 0.15)
                        .allowsHitTesting(false)
                )
                // Only breathes while on screen.
                .onVisibilityChange { on in
                    if on {
                        withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) { bright = true }
                    } else {
                        stopLoop { bright = false }
                    }
                }
        } else {
            content
        }
    }
}

/// A round 3D icon button (the website's action row).
struct IconButton3D: ButtonStyle {
    var size: CGFloat = 44
    var active = false
    /// One of a set of tabs in a track: when not active it's just the icon, no button behind it.
    var inTrack = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let bare = inTrack && !active
        configuration.label
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(active ? Theme.ink : (inTrack ? Theme.muted : .white))
            .frame(width: size, height: size)
            .background(
                ZStack {
                    if !bare {
                        Circle().fill(Color(hex: active ? 0x7A9200 : 0x0D0D0F)).offset(y: pressed ? 0 : 3)
                        Circle().fill(active ? Theme.lime : Theme.surface2)
                        Circle().fill(LinearGradient(colors: [.white.opacity(0.07), .clear], startPoint: .top, endPoint: .center))
                    }
                }
            )
            .offset(y: pressed ? 2 : -1)
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: pressed)
    }
}

// MARK: - Tags, pills and chips

/// The website's slanted tag: italic caps on a parallelogram ("STAR OF THE COLLECTION").
struct SkewTag: View {
    var text: String
    var color: Color = Theme.lime
    var textColor: Color = Theme.ink
    var icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .medium)) }
            Text(text.uppercased()).font(.geist(11, .bold)).italic().tracking(0.2).lineLimit(1)
        }
        .fixedSize()
        .foregroundStyle(textColor)
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 3)
        .background(Parallelogram(inset: 5).fill(color))
    }
}

struct Parallelogram: Shape {
    var inset: CGFloat

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + inset, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - inset, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// "TODAY  +$156.28 +1.11%": a pill with a mono label and a value.
struct StatPill: View {
    var label: String
    var value: String
    var tint: Color = .white
    var extra: String?

    var body: some View {
        HStack(spacing: 8) {
            MonoLabel(text: label)
            Text(value).font(.geist(15, .semibold)).monospacedDigit().foregroundStyle(tint)
            if let extra { Text(extra).font(.geist(15, .medium)).monospacedDigit().foregroundStyle(tint.opacity(0.85)) }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 14)
        .frame(height: 38)
        .trackGlass(in: Capsule())
    }
}

/// A selectable chip; the selected one is lime with a 3D edge (website segmented controls).
/// Put chips in a track (`ChipPicker`, or `.liquidGlass(in: Capsule())` on their row).
struct Chip: View {
    var title: String
    var selected: Bool
    var count: Int?
    /// Takes an equal share of the track's width (a full-width picker).
    var fills = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.geist(14, .semibold))
                if let count { Text("\(count)").font(.geist(14, .medium)).opacity(0.6).monospacedDigit() }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: fills ? .infinity : nil)
            .frame(height: 36)
            .foregroundStyle(selected ? Theme.ink : Theme.muted)
            .background(
                ZStack {
                    if selected {
                        // Only the selected chip glows (a clear shadow on every other chip still
                        // costs a render pass, on glass).
                        ZStack {
                            Capsule().fill(Theme.limeEdge).offset(y: 2)
                            Capsule().fill(Theme.lime)
                        }
                        .shadow(color: Theme.lime.opacity(0.35), radius: 8)
                    } else {
                        // Unselected chips are just text; the track behind them shows through.
                        Capsule().fill(Color.clear)
                    }
                }
            )
        }
        .buttonStyle(ChipPress())
    }
}

/// A plain button that presses in a touch (scale and a small sink) with a quick spring.
/// Used by `Chip`; keeps the chip's look and only adds the press.
struct ChipPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .contentShape(Capsule())
            .offset(y: pressed ? 1 : 0)
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: pressed)
    }
}

/// A row of chips for picking one value, inside a dark track like the website's.
extension View {
    /// Fades the last stretch of the right edge to clear (for rows that run on past it).
    func fadeTrailingEdge(_ length: CGFloat = 44) -> some View {
        mask {
            HStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: length)
            }
        }
    }
}

struct ChipPicker<T: Hashable>: View {
    var options: [(T, String)]
    @Binding var selection: T
    /// When the chips may not fit: the track stays inside its space and the chips scroll in it.
    var scrolls = false
    /// The track spans the full width, the chips sharing it equally.
    var fills = false

    var body: some View {
        if scrolls {
            // Fits: as is. Doesn't: the chips scroll inside the track and its right edge fades.
            ViewThatFits(in: .horizontal) {
                chips.padding(4)
                ScrollView(.horizontal, showsIndicators: false) { chips.padding(4) }
                    .fadeTrailingEdge()
            }
            .clipShape(Capsule())
            .trackGlass(in: Capsule())
        } else {
            chips.padding(4).trackGlass(in: Capsule())
        }
    }

    private var chips: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, label in
                Chip(title: label, selected: selection == value, fills: fills) { selection = value }
            }
        }
    }
}

/// A gain or loss in a tinted pill ("+83.33%").
struct DeltaPill: View {
    var ratio: Double?
    var size: CGFloat = 13

    var body: some View {
        let t = Theme.tone(ratio)
        Text(Format.signedPercent(ratio))
            .font(.geist(size, .semibold)).monospacedDigit()
            .foregroundStyle(t)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(t.opacity(0.12)))
    }
}

/// A plain colored "+$12.34".
struct Delta: View {
    var value: Double?
    var size: CGFloat = 13

    var body: some View {
        Text(Format.signedMoney(value)).font(.geist(size, .medium)).monospacedDigit().foregroundStyle(Theme.tone(value))
    }
}

// MARK: - Placeholders (the website's line-art silhouettes)

/// Lime line art for a product without a photo: a card, a box, a pack… with its type and set below.
struct Silhouette: View {
    enum Kind { case card, box, pack, tin }

    var product: Product?
    var showCaption = true

    private var shape: Kind {
        guard let p = product, p.isSealed else { return .card }
        let t = (p.productType ?? p.name).lowercased()
        if t.contains("pack") && !t.contains("box") { return .pack }
        if t.contains("tin") { return .tin }
        return .box
    }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            VStack(spacing: s * 0.06) {
                art.frame(width: s * 0.62, height: s * 0.72)
                if showCaption && s > 120 {
                    VStack(spacing: 3) {
                        Text(caption).font(.mono(max(8, s * 0.045))).tracking(1).foregroundStyle(Theme.muted).lineLimit(1)
                        if let set = product?.setName {
                            Text(set).font(.geist(max(9, s * 0.055))).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.surface2)
    }

    private var caption: String {
        guard let p = product, p.isSealed else { return "CARD" }
        return (p.productType ?? "Sealed").uppercased()
    }

    @ViewBuilder private var art: some View {
        let line = Theme.lime
        switch shape {
        case .card:
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(line.opacity(0.08))
                RoundedRectangle(cornerRadius: 6).stroke(line, lineWidth: 2)
                VStack(alignment: .leading, spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).stroke(line, lineWidth: 1.5).frame(maxHeight: .infinity).padding(.bottom, 4)
                    Rectangle().fill(line).frame(height: 1.5)
                    Rectangle().fill(line).frame(width: 30, height: 1.5)
                    Rectangle().fill(line).frame(height: 1.5)
                }
                .padding(8)
            }
            .aspectRatio(63.0 / 88.0, contentMode: .fit)
        case .box, .tin:
            Image(systemName: shape == .tin ? "cylinder" : "shippingbox").resizable().scaledToFit().fontWeight(.light).foregroundStyle(line)
        case .pack:
            Image(systemName: "rectangle.portrait.on.rectangle.portrait").resizable().scaledToFit().fontWeight(.light).foregroundStyle(line)
        }
    }
}

// MARK: - Category colors (Sealed blue, Singles pink, Graded lime, as on the website)

enum HoldingCategory: String, CaseIterable, Identifiable {
    case sealed = "Sealed", singles = "Singles", graded = "Graded"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .sealed: return Theme.planBlue
        case .singles: return Theme.planPink
        case .graded: return Theme.lime
        }
    }

    var button: Button3D.Kind {
        switch self {
        case .sealed: return .blue
        case .singles: return .pink
        case .graded: return .lime
        }
    }

    var blurb: String {
        switch self {
        case .sealed: return "Boxes, ETBs, packs & collections"
        case .singles: return "Raw cards, straight from the pack"
        case .graded: return "Slabbed and certified"
        }
    }
}

extension HoldingView {
    var category: HoldingCategory {
        if identity.isGraded { return .graded }
        return product?.isSealed == true ? .sealed : .singles
    }
}

// MARK: - Display type

// A big number with tight tracking needs `.padding(.trailing, <the tracking>)` after `.tracking`:
// tracking shortens the measured line by that much, so the last digit's right edge otherwise
// falls outside the text's box and is cut off (seen on the deal card's $735.00).
extension View {
    /// Anton's line box is about 1.5× its size, with a third of an em of air above the capitals
    /// and below the baseline. This trims that air so headings sit as tight as the website's.
    func displayTrim(_ size: CGFloat) -> some View { padding(.vertical, -size * 0.06) }
}

/// A multi-line Anton heading with the website's tight leading (about 0.98), wrapped in
/// balanced lines like the website's `text-wrap: balance`, so a lone word never hangs on the last line.
struct DisplayText: View {
    var text: String
    var size: CGFloat
    var color: Color = .white
    /// Air between lines as a share of `size`; a little negative sits lines tight, like Deal's
    /// "Trade / recorded" heading.
    var lineGap: CGFloat = 0.08
    /// Lines flow from the left by default; `.center` centres each line (the welcome titles).
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        WordFlow(spacing: size * 0.2, lineGap: size * lineGap, alignment: alignment) {
            ForEach(Array(text.split(separator: " ").enumerated()), id: \.offset) { _, word in
                Text(word).font(.display(size)).tracking(size * -0.03).foregroundStyle(color).displayTrim(size)
            }
        }
    }
}

/// Lays words out left to right, wrapping onto new lines of balanced length: the narrowest width
/// that still needs no more lines than the full width does.
private struct WordFlow: Layout {
    var spacing: CGFloat
    var lineGap: CGFloat
    var alignment: HorizontalAlignment = .leading

    /// Each word's natural size, measured once instead of on every step of the balancing search.
    func makeCache(subviews: Subviews) -> [CGSize] {
        subviews.map { $0.sizeThatFits(.unspecified) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]) -> CGSize {
        let rows = balanced(width: proposal.width ?? .infinity, sizes: cache)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map { $0.height }.reduce(0, +) + lineGap * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]) {
        var y = bounds.minY
        for row in balanced(width: bounds.width, sizes: cache) {
            var x = bounds.minX
            if alignment == .center { x += max(bounds.width - row.width, 0) / 2 }
            if alignment == .trailing { x += max(bounds.width - row.width, 0) }
            for i in row.items {
                let size = cache[i]
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineGap
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func balanced(width: CGFloat, sizes: [CGSize]) -> [Row] {
        let full = arrange(width: width, sizes: sizes)
        guard full.count > 1, width.isFinite else { return full }
        var low = sizes.map { $0.width }.max() ?? 0
        var high = width
        guard low < high else { return full }
        while high - low > 1 {
            let mid = (low + high) / 2
            if arrange(width: mid, sizes: sizes).count > full.count { low = mid } else { high = mid }
        }
        return arrange(width: high, sizes: sizes)
    }

    private func arrange(width: CGFloat, sizes: [CGSize]) -> [Row] {
        var rows: [Row] = [Row()]
        for i in sizes.indices {
            let size = sizes[i]
            let extra = rows[rows.count - 1].items.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            let isFirst = rows[rows.count - 1].items.isEmpty
            rows[rows.count - 1].items.append(i)
            rows[rows.count - 1].width += isFirst ? size.width : size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}

// MARK: - Charts

extension View {
    /// The website's chart axis: value labels inside the plot along the right edge, just above
    /// a faint gridline, so the line runs the full width with no gutter. Use on a Chart.
    func insideYAxis(count: Int = 4, label: @escaping (Double) -> String = ChartTicks.label) -> some View {
        chartYAxis(.hidden).chartOverlay { proxy in
            GeometryReader { geo in
                if let anchor = proxy.plotFrame {
                    let frame = geo[anchor]
                    let top = proxy.value(atY: frame.minY, as: Double.self) ?? 0
                    let bottom = proxy.value(atY: frame.maxY, as: Double.self) ?? 0
                    ForEach(ChartTicks.values(from: bottom, to: top, count: count), id: \.self) { v in
                        if let y = proxy.position(forY: v), y > 14, y <= frame.height {
                            Rectangle().fill(Color.white.opacity(0.05)).frame(width: frame.width, height: 1)
                                .position(x: frame.midX, y: frame.minY + y)
                            Text(label(v))
                                .font(.geist(11)).monospacedDigit().foregroundStyle(Theme.subtle)
                                .frame(width: frame.width - 4, alignment: .trailing)
                                .position(x: frame.midX - 2, y: frame.minY + y - 9)
                        }
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

enum ChartTicks {
    /// Round values between two ends: 1, 2, 2.5 or 5 times a power of ten.
    static func values(from low: Double, to high: Double, count: Int) -> [Double] {
        guard high > low, low.isFinite, high.isFinite else { return [] }
        let raw = (high - low) / Double(max(count, 1))
        let power = pow(10, floor(log10(raw)))
        let step = [1, 2, 2.5, 5, 10].map { $0 * power }.first { $0 >= raw } ?? raw
        var v = ceil(low / step) * step
        var out: [Double] = []
        while v < high { out.append(v); v += step }
        return out
    }

    /// The chart's vertical range: the data with a little room below and above, never to zero,
    /// so the line uses the height instead of hugging the top.
    static func domain(_ values: [Double]) -> ClosedRange<Double> {
        guard let lo = values.min(), let hi = values.max() else { return 0 ... 1 }
        let span = max(hi - lo, max(abs(hi) * 0.02, 1))
        return max(0, lo - span * 0.18) ... hi + span * 0.14
    }

    /// "$1,234" under ten thousand, "$12.3K" above, like the website.
    static func label(_ v: Double) -> String {
        let v = abs(v) < 0.5 ? 0 : v
        if abs(v) < 10000 { return Format.moneyWhole(v) }
        let (scaled, suffix) = abs(v) >= 1_000_000 ? (v / 1_000_000, "M") : (v / 1000, "K")
        let digits = abs(scaled) >= 100 ? "%.0f" : "%.1f"
        let number = String(format: digits, abs(scaled)).replacingOccurrences(of: ".0", with: "")
        return (v < 0 ? "−$" : "$") + number + suffix
    }
}

// MARK: - Backdrops

/// A faint square grid, the website's hero and spotlight backdrop.
struct GridPattern: View {
    var step: CGFloat = 32
    var opacity: Double = 0.035

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            stride(from: 0, through: size.width, by: step).forEach { x in path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)) }
            stride(from: 0, through: size.height, by: step).forEach { y in path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)) }
            ctx.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: 1)
        }
    }
}

/// A comet of lime light travelling round a rounded border at a steady pace, over a steady neon
/// edge: one slow, unbroken loop (it follows the border itself, so it never rushes the corners).
struct ElectricBorder: View {
    var radius: CGFloat
    var color: Color = Theme.lime
    /// Seconds for one trip round the border.
    var period: Double = 7
    @State private var phase: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.strokeBorder(color.opacity(0.5), lineWidth: 1.5)
            if !reduceMotion {
                // A soft tail, a brighter body and a white-hot head, all riding the same phase.
                BorderComet(radius: radius, phase: phase, start: 0, length: 0.26)
                    .stroke(color.opacity(0.25), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                BorderComet(radius: radius, phase: phase, start: 0.1, length: 0.16)
                    .stroke(color.opacity(0.8), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                BorderComet(radius: radius, phase: phase, start: 0.22, length: 0.04)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
        .padding(0.75)
        .allowsHitTesting(false)
        // Only moves while on screen.
        .onVisibilityChange { on in
            if on {
                phase = 0
                withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) { phase = 1 }
            } else {
                stopLoop { phase = 0 }
            }
        }
    }
}

/// A stretch of a rounded rectangle's outline, `length` long (as a share of the whole), starting
/// `start` behind the comet's tail at `phase`, wrapping past the outline's start without a seam.
struct BorderComet: Shape {
    var radius: CGFloat
    var phase: Double
    var start: Double
    var length: Double

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let outline = RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        let from = (phase + start).truncatingRemainder(dividingBy: 1)
        let to = from + length
        if to <= 1 { return outline.trimmedPath(from: from, to: to) }
        var p = outline.trimmedPath(from: from, to: 1)
        p.addPath(outline.trimmedPath(from: 0, to: to - 1))
        return p
    }
}

/// A card's heading: a glowing lime dot and faded all-caps Roboto Mono.
struct CardLabel: View {
    var text: String
    var color: Color = Theme.lime

    var body: some View {
        // The website's card title: plain, no dot.
        Text(text).font(.geist(15, .semibold)).foregroundStyle(.white).lineLimit(1)
    }
}

// MARK: - Liquid glass

extension View {
    /// Liquid Glass over a real blur of what's behind (Liquid Glass alone bends the background
    /// but barely blurs it, so busy backdrops like the grid show straight through).
    func blurredGlass<S: InsettableShape>(in shape: S) -> some View {
        background(shape.fill(.ultraThinMaterial))
            .liquidGlass(in: shape)
    }

    /// iOS 26's Liquid Glass in a shape, tinted dark so it sits in the app's palette. Older iOS,
    /// and builds with an older Xcode, get frosted material with a fine light edge instead.
    @ViewBuilder
    func liquidGlass<S: InsettableShape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            frosted(in: shape, tint: tint)
        }
        #else
        frosted(in: shape, tint: tint)
        #endif
    }

    /// Liquid Glass for chip tracks and pills, except on a glass sheet, where they take the
    /// sheet's faint white fill instead (like dark buttons there): glass on glass makes iOS blur
    /// twice over, which made taps in sheets feel slow.
    func trackGlass<S: InsettableShape>(in shape: S) -> some View {
        modifier(TrackGlass(shape: shape))
    }

    private func frosted<S: InsettableShape>(in shape: S, tint: Color?) -> some View {
        background(
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill((tint ?? Theme.background).opacity(0.35))
                shape.fill(LinearGradient(colors: [.white.opacity(0.08), .clear], startPoint: .top, endPoint: .center))
            }
        )
        .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}


private struct TrackGlass<S: InsettableShape>: ViewModifier {
    var shape: S
    @Environment(\.onGlassSheet) private var onGlass

    func body(content: Content) -> some View {
        if onGlass {
            content
                .background(shape.fill(Color.white.opacity(0.07)))
                .overlay(shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 1).allowsHitTesting(false))
        } else {
            content.liquidGlass(in: shape)
        }
    }
}

/// A tappable card, the same everywhere: one you own opens Your copy (a sheet with "View card
/// details"), one you don't opens its card page.
struct CardLink<Label: View>: View {
    var productId: String
    /// The exact copy, when the row is about one (a purchase, a slab); else your most valuable.
    var identity: HoldingIdentity? = nil
    @ViewBuilder var label: Label
    @Environment(CollectionStore.self) private var store

    var body: some View {
        if let owned = ownedIdentity {
            Button { Router.shared.holding = owned } label: { label }
                .buttonStyle(.plain)
        } else {
            NavigationLink(value: productId) { label }
        }
    }

    /// One pass over the holdings (this runs for every card on screen whenever they change):
    /// the exact copy if you hold it, else your most valuable copy of the product.
    private var ownedIdentity: HoldingIdentity? {
        let wanted = identity
        let wantedKey = wanted?.key
        var exact = false
        var best: HoldingView?
        for h in store.allHoldings {
            if let wanted, !exact, h.identity.productId == wanted.productId, h.identity.key == wantedKey { exact = true }
            if h.identity.productId == productId, best == nil || (best?.value ?? 0) < (h.value ?? 0) { best = h }
        }
        if exact, let wanted { return wanted }
        return best?.identity
    }
}


extension View {
    /// Shows the latest undoable change ("Entry deleted · Undo") for a few seconds at the
    /// bottom. Put on the main tabs and on sheets where you can delete or sell.
    func undoToast(bottom: CGFloat = 24) -> some View { modifier(UndoToast(bottom: bottom)) }
}

private struct UndoToast: ViewModifier {
    var bottom: CGFloat
    @State private var router = Router.shared
    @State private var working = false

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let item = router.undo {
                HStack(spacing: 14) {
                    Text(item.message).font(.geist(14, .medium)).foregroundStyle(.white)
                    Spacer(minLength: 8)
                    Button {
                        guard !working else { return }
                        working = true
                        Task {
                            await item.action()
                            working = false
                            if router.undo?.id == item.id { withAnimation(.snappy) { router.undo = nil } }
                        }
                    } label: {
                        Text(working ? "Undoing…" : "Undo").font(.geist(14, .semibold)).foregroundStyle(Theme.lime)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .frame(height: 50)
                .liquidGlass(in: Capsule())
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                .padding(.horizontal, 16)
                .padding(.bottom, bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: item.id) {
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    if router.undo?.id == item.id, !working { withAnimation(.snappy) { router.undo = nil } }
                }
                .sensoryFeedback(.success, trigger: item.id)
            }
        }
        .animation(.snappy, value: router.undo?.id)
    }
}

/// The small "Pulled" badge on a copy you pulled from a pack: a skewed tag in a hot gradient
/// with a sparkle, so it reads as a pull at a glance.
struct PulledBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles").font(.system(size: 9, weight: .bold))
            Text("PULLED").font(.geist(11, .bold)).italic().tracking(0.2)
        }
        .fixedSize()
        .foregroundStyle(Theme.ink)
        .padding(.leading, 8).padding(.trailing, 10).padding(.vertical, 3)
        .background(Parallelogram(inset: 5).fill(LinearGradient(colors: [Color(hex: 0xFFD23F), Color(hex: 0xFF8A3D)], startPoint: .leading, endPoint: .trailing)))
        .accessibilityLabel("Pulled from a pack")
    }
}

/// A form section's heading: white, in the heading font, clearly above its rows and note.
struct SectionTitle: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.display(20)).tracking(-0.5).foregroundStyle(.white).textCase(nil)
            .padding(.bottom, 2)
    }
}

/// The quiet note under a form section's rows.
struct SectionNote: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.geist(12)).foregroundStyle(Theme.subtle).textCase(nil) }
}
