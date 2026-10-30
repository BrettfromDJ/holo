import SwiftUI
import UIKit

// The website's design language, in SwiftUI: Geist for text, Anton (tall condensed caps) for
// headlines and big numbers, Geist Mono for small caps labels, lime accents, 3D buttons,
// hairline-bordered surfaces and slanted tags.

// MARK: - Type

extension Font {
    /// Anton: page titles, section headers and the big numbers.
    static func display(_ size: CGFloat) -> Font { .custom("Anton-Regular", size: size) }

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
        let large = UIFont(name: "Anton-Regular", size: 34) ?? .systemFont(ofSize: 34, weight: .bold)
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.backgroundColor = UIColor(Theme.background)
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
                Text(title.uppercased()).font(.display(size)).tracking(0.2).lineLimit(2).minimumScaleFactor(0.7).displayTrim(size)
                if let subtitle {
                    Text(subtitle).font(.geist(15)).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
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

    func body(content: Content) -> some View {
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

/// 3D buttons: lit top, solid bottom edge; pressing sinks onto the edge.
struct Button3D: ButtonStyle {
    enum Kind { case light, lime, dark, blue, pink }

    var kind: Kind = .lime
    var fullWidth = true
    var height: CGFloat = 50

    private var fill: Color {
        switch kind {
        case .light: return Color(hex: 0xF5F5F7)
        case .lime: return Theme.lime
        case .dark: return Theme.surface2
        case .blue: return Theme.planBlue
        case .pink: return Theme.planPink
        }
    }

    private var edge: Color {
        switch kind {
        case .light: return Color(hex: 0x8A8A8E)
        case .lime: return Color(hex: 0x7A9200)
        case .dark: return Color(hex: 0x0D0D0F)
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

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.geist(16, .semibold))
            .foregroundStyle(text)
            .padding(.horizontal, 18)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(edge).offset(y: pressed ? 0 : 3)
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(kind == .dark ? 0.06 : 0.16), .clear], startPoint: .top, endPoint: .center))
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(kind == .dark ? 0.08 : 0.35), .clear], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    if kind == .lime || kind == .blue || kind == .pink {
                        Sheen(strength: 0.5).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            )
            .offset(y: pressed ? 2 : -1)
            .scaleEffect(pressed ? 0.97 : 1)
            .shadow(color: .black.opacity(0.5), radius: 9, y: 6)
            .modifier(ElectricGlow(color: fill, on: kind == .lime || kind == .blue || kind == .pink))
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
                .onAppear {
                    withAnimation(.linear(duration: 4.5).repeatForever(autoreverses: false)) { across = true }
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

    func body(content: Content) -> some View {
        if on && !reduceMotion {
            content
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(color)
                        .blur(radius: 14)
                        .opacity(bright ? 0.55 : 0.15)
                        .allowsHitTesting(false)
                )
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) { bright = true }
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
            .animation(.easeOut(duration: 0.12), value: pressed)
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
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .black)) }
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
        .liquidGlass(in: Capsule())
    }
}

/// A selectable chip; the selected one is lime with a 3D edge (website segmented controls).
/// Put chips in a track (`ChipPicker`, or `.liquidGlass(in: Capsule())` on their row).
struct Chip: View {
    var title: String
    var selected: Bool
    var count: Int?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.geist(14, .semibold))
                if let count { Text("\(count)").font(.geist(14, .medium)).opacity(0.6).monospacedDigit() }
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .foregroundStyle(selected ? Theme.ink : Theme.muted)
            .background(
                ZStack {
                    if selected {
                        Capsule().fill(Color(hex: 0x7A9200)).offset(y: 2)
                        Capsule().fill(Theme.lime)
                    } else {
                        // Unselected chips are just text; the track behind them shows through.
                        Capsule().fill(Color.clear)
                    }
                }
            )
            .shadow(color: selected ? Theme.lime.opacity(0.35) : .clear, radius: 8)
        }
        .buttonStyle(.plain)
    }
}

/// A row of chips for picking one value, inside a dark track like the website's.
struct ChipPicker<T: Hashable>: View {
    var options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, label in
                Chip(title: label, selected: selection == value) { selection = value }
            }
        }
        .padding(4)
        .liquidGlass(in: Capsule())
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

/// A graded slab: a glassy case with the grading company's label on top.
struct SlabFrame<Content: View>: View {
    var company: String
    var grade: String
    var product: Product?
    @ViewBuilder var content: Content

    private var labelColor: Color {
        switch company.uppercased() {
        case "PSA": return Color(hex: 0xD7282F)
        case "CGC": return Color(hex: 0x1E5BB8)
        case "BGS": return Color(hex: 0x8C8C8C)
        case "SGC": return Color(hex: 0x111111)
        default: return Color(hex: 0x333333)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            // The label: set and name on the left, grade on the right.
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text((product?.setName ?? "").uppercased()).font(.geist(6.5, .bold)).lineLimit(1)
                    Text((product?.name ?? "").uppercased()).font(.geist(6.5, .bold)).lineLimit(1)
                    Rectangle().fill(.black.opacity(0.7)).frame(height: 5).padding(.top, 2).padding(.trailing, 18)
                }
                Spacer(minLength: 2)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(company.uppercased()).font(.geist(6, .heavy)).foregroundStyle(labelColor)
                    Text(grade).font(.display(15)).foregroundStyle(.black)
                }
            }
            .foregroundStyle(.black)
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 3).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(labelColor, lineWidth: 2))
            content
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x3A3A3E), Color(hex: 0x1C1C1F)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
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

extension View {
    /// Anton's line box is about 1.5× its size, with a third of an em of air above the capitals
    /// and below the baseline. This trims that air so headings sit as tight as the website's.
    func displayTrim(_ size: CGFloat) -> some View { padding(.vertical, -size * 0.27) }
}

/// A multi-line Anton heading with the website's tight leading (about 0.98), wrapped in
/// balanced lines like the website's `text-wrap: balance`, so a lone word never hangs on the last line.
struct DisplayText: View {
    var text: String
    var size: CGFloat
    var color: Color = .white

    var body: some View {
        WordFlow(spacing: size * 0.2, lineGap: size * 0.08) {
            ForEach(Array(text.split(separator: " ").enumerated()), id: \.offset) { _, word in
                Text(word).font(.display(size)).foregroundStyle(color).displayTrim(size)
            }
        }
    }
}

/// Lays words out left to right, wrapping onto new lines of balanced length: the narrowest width
/// that still needs no more lines than the full width does.
private struct WordFlow: Layout {
    var spacing: CGFloat
    var lineGap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = balanced(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map { $0.height }.reduce(0, +) + lineGap * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in balanced(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineGap
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func balanced(width: CGFloat, subviews: Subviews) -> [Row] {
        let full = arrange(width: width, subviews: subviews)
        guard full.count > 1, width.isFinite else { return full }
        var low = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        var high = width
        guard low < high else { return full }
        while high - low > 1 {
            let mid = (low + high) / 2
            if arrange(width: mid, subviews: subviews).count > full.count { low = mid } else { high = mid }
        }
        return arrange(width: high, subviews: subviews)
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
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
    func insideYAxis(count: Int = 4) -> some View {
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
                            Text(ChartTicks.label(v))
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
        return max(0, lo - span * 0.18) ... hi + span * 0.08
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

/// A bolt of lime light that runs around a rounded border, over a steady neon edge.
struct ElectricBorder: View {
    var radius: CGFloat
    var color: Color = Theme.lime
    @State private var spin = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        GeometryReader { geo in
            let side = hypot(geo.size.width, geo.size.height)
            let bolt = Rectangle()
                .fill(AngularGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.6),
                        .init(color: color.opacity(0.5), location: 0.8),
                        .init(color: color, location: 0.9),
                        .init(color: .white, location: 0.95),
                        .init(color: .clear, location: 1),
                    ],
                    center: .center
                ))
                .frame(width: side, height: side)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                shape.strokeBorder(color.opacity(0.5), lineWidth: 1.5)
                bolt.mask(shape.strokeBorder(lineWidth: 3))
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) { spin = true }
        }
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
