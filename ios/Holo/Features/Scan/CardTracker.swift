import Foundation
import Observation
import QuartzCore
import SwiftUI
import UIKit

/// A card's four corners, 0...1 in Vision's space (origin bottom-left) of the upright frame.
struct CardQuad: Equatable, Sendable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    var corners: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    /// The furthest any corner moved, in frame widths/heights.
    func distance(to other: CardQuad) -> CGFloat {
        zip(corners, other.corners).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0
    }

    /// Each corner moved `amount` of the way toward `other`.
    func blended(toward other: CardQuad, by amount: CGFloat) -> CardQuad {
        func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * amount, y: a.y + (b.y - a.y) * amount) }
        return CardQuad(topLeft: mix(topLeft, other.topLeft), topRight: mix(topRight, other.topRight),
                        bottomRight: mix(bottomRight, other.bottomRight), bottomLeft: mix(bottomLeft, other.bottomLeft))
    }

    /// Pushed out from the middle by `fraction` (0.03 = 3% bigger), kept inside the frame.
    func expanded(by fraction: CGFloat) -> CardQuad {
        let cx = corners.map(\.x).reduce(0, +) / 4, cy = corners.map(\.y).reduce(0, +) / 4
        func push(_ p: CGPoint) -> CGPoint {
            CGPoint(x: min(1, max(0, cx + (p.x - cx) * (1 + fraction))), y: min(1, max(0, cy + (p.y - cy) * (1 + fraction))))
        }
        return CardQuad(topLeft: push(topLeft), topRight: push(topRight), bottomRight: push(bottomRight), bottomLeft: push(bottomLeft))
    }

    /// The corners on screen (top-left origin) for a preview of `view` size that shows a frame
    /// of `frame` pixels aspect-filled and centred (`.resizeAspectFill`), in the order
    /// top-left, top-right, bottom-right, bottom-left.
    func viewPoints(frame: CGSize, view: CGSize) -> [CGPoint] {
        guard frame.width > 0, frame.height > 0 else { return [] }
        let scale = max(view.width / frame.width, view.height / frame.height)
        let w = frame.width * scale, h = frame.height * scale
        let dx = (view.width - w) / 2, dy = (view.height - h) / 2
        return corners.map { CGPoint(x: dx + $0.x * w, y: dy + (1 - $0.y) * h) }
    }
}

/// Follows the card the camera sees and reads it before you tap.
///
/// Flow: `Camera` hands each processed frame's corners to `update` (main queue, ~10 a second).
/// They're smoothed (half-way toward each new reading; a big jump snaps) and dropped after
/// 0.4 s without a card. When the card has held still (corners within 3% for 0.5 s), one
/// identification runs: `snapshot` (the camera's flattened crop) → `OnDeviceScan.read` →
/// `OnDeviceScan.lookUp`, cached by the read number so the same card never asks the catalog
/// twice. The result shows as `label` above the border, and `liveMatch` lets a tap add it
/// with no paid scan. Only the border view reads `quad`/`label`; the scanner reads just
/// `isTracking` (which changes rarely), so nothing else redraws per frame.
/// Used on the main thread only.
@Observable
final class CardTracker {
    enum LiveRead: Equatable {
        case reading
        case matched(name: String, number: String?, price: Double?)
    }

    struct LiveMatch {
        var hit: SearchHit
        var crop: CardCrop
        /// Where the card was when it was read (a big move means it's another card).
        var quad: CardQuad
    }

    /// The smoothed corners of the card in view, or nil.
    private(set) var quad: CardQuad?
    /// The upright frame's size in pixels, for mapping the corners onto the preview.
    private(set) var frameSize: CGSize = .zero
    /// Whether a card is being followed. Stored (and only set on change) so the scanner,
    /// which reads it to hide the guide, doesn't redraw with every corner update.
    private(set) var isTracking = false
    private(set) var label: LiveRead?

    /// Takes a flattened crop of the card in the next frame (set by the scanner).
    @ObservationIgnored var snapshot: (() async -> CardCrop?)?
    /// Off in a demo, where the catalog search isn't real.
    @ObservationIgnored var identifies = !Demo.isOn
    /// False while the scanner is covered or closed: late frames are ignored, so a card can't
    /// stay drawn after tracking stopped.
    @ObservationIgnored var active = false {
        didSet { if !active { reset() } }
    }

    @ObservationIgnored private(set) var liveMatch: LiveMatch?
    @ObservationIgnored private var lastSeen: CFTimeInterval = 0
    @ObservationIgnored private var steadyRef: CardQuad?
    @ObservationIgnored private var steadySince: CFTimeInterval = 0
    @ObservationIgnored private var identifying = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var missQuad: CardQuad?
    @ObservationIgnored private var missAt: CFTimeInterval = 0
    @ObservationIgnored private var misses = 0
    /// Read numbers already looked up: the match, or nil for "no clear match".
    @ObservationIgnored private var cache: [String: SearchHit?] = [:]

    /// The live match, when it is for the card in view now.
    var readyMatch: LiveMatch? {
        guard let m = liveMatch, let q = quad, m.quad.distance(to: q) < 0.15 else { return nil }
        return m
    }

    func update(_ raw: CardQuad?, frame: CGSize) {
        guard active else { return }
        let now = CACurrentMediaTime()
        guard let raw else {
            if quad != nil, now - lastSeen > 0.4 { reset() }
            return
        }
        lastSeen = now
        if frameSize != frame { frameSize = frame }
        if let current = quad, current.distance(to: raw) < 0.12 {
            quad = current.blended(toward: raw, by: 0.5)
        } else {
            quad = raw
        }
        if !isTracking { isTracking = true }

        // Held still for half a second: read it (once per steady card).
        if let ref = steadyRef, ref.distance(to: raw) < 0.03 {
            if now - steadySince >= 0.5 { identifyIfNeeded(raw, now: now) }
        } else {
            steadyRef = raw
            steadySince = now
        }
    }

    /// The card is gone (or the scanner paused): forget it and anything read in flight.
    func reset() {
        generation += 1
        if quad != nil { quad = nil }
        if isTracking { isTracking = false }
        if label != nil { label = nil }
        liveMatch = nil
        steadyRef = nil
        missQuad = nil
        misses = 0
    }

    private func identifyIfNeeded(_ current: CardQuad, now: CFTimeInterval) {
        guard identifies, !identifying, let snapshot else { return }
        // Already read this card.
        if let m = liveMatch, m.quad.distance(to: current) < 0.12 { return }
        // Couldn't read it here a moment ago: wait for a move or two seconds.
        if let miss = missQuad, miss.distance(to: current) < 0.05, now - missAt < 2 { return }
        identifying = true
        if misses == 0, liveMatch == nil, label == nil { label = .reading }
        let gen = generation
        // On the main actor, but each step's work runs elsewhere (the frame queue, Vision's
        // queue, the network); only the cache and the result are touched here.
        Task { @MainActor [weak self] in
            var hit: SearchHit?
            let crop = await snapshot()
            if let crop, let reading = await OnDeviceScan.read(jpeg: crop.jpeg) {
                let key = OnDeviceScan.cacheKey(reading)
                if let known = self?.cache[key] {
                    hit = known
                } else {
                    hit = await OnDeviceScan.lookUp(reading)
                    self?.cache[key] = .some(hit)
                }
            }
            self?.finish(gen, hit: hit, crop: crop, quad: current)
        }
    }

    private func finish(_ gen: Int, hit: SearchHit?, crop: CardCrop?, quad read: CardQuad) {
        identifying = false
        guard gen == generation, quad != nil else { return }
        if let hit, let crop {
            liveMatch = LiveMatch(hit: hit, crop: crop, quad: read)
            missQuad = nil
            label = .matched(name: hit.product.name, number: hit.product.number, price: hit.market)
        } else {
            misses += 1
            missQuad = read
            missAt = CACurrentMediaTime()
            // Nothing on failure, unless an earlier match for this card is still showing.
            if case .reading = label { label = nil }
        }
    }
}

// MARK: - The border

/// The lime border that follows the card, the live read above it, and the tap that adds it.
/// The only view that reads the corners, so it's the only one that redraws per frame.
struct CardTrackingOverlay: View {
    let tracker: CardTracker
    var onTap: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            if let quad = tracker.quad {
                let points = quad.viewPoints(frame: tracker.frameSize, view: geo.size)
                if points.count == 4 {
                    let shape = CardQuadShape(points: points)
                    ZStack {
                        // A soft glow done cheaply: a wide faint stroke under the line.
                        shape.stroke(Theme.lime.opacity(0.22), style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                        shape.stroke(Theme.lime, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                    // Glides between the ~10 readings a second (just this one path).
                    .animation(reduceMotion ? nil : .linear(duration: 0.1), value: points)
                    .contentShape(shape)
                    .onTapGesture { onTap() }
                    .accessibilityElement()
                    .accessibilityLabel("Add this card")
                    .accessibilityAddTraits(.isButton)

                    if let label = tracker.label {
                        let top = CGPoint(x: (points[0].x + points[1].x) / 2, y: min(points[0].y, points[1].y))
                        LiveLabel(label: label)
                            .fixedSize()
                            .position(x: min(max(top.x, 120), geo.size.width - 120), y: max(top.y - 26, 80))
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// The card's name, number and market price (or "Reading…") in a small glass pill.
private struct LiveLabel: View {
    var label: CardTracker.LiveRead

    var body: some View {
        HStack(spacing: 6) {
            switch label {
            case .reading:
                Text("Reading…").font(.geist(13, .semibold)).foregroundStyle(.white)
            case let .matched(name, number, price):
                Text(name.count > 24 ? String(name.prefix(23)) + "…" : name).font(.geist(13, .semibold)).foregroundStyle(.white).lineLimit(1)
                if let number { Text("#\(number)").font(.mono(11)).foregroundStyle(Theme.muted).lineLimit(1) }
                Text(Format.money(price)).font(.geist(13, .bold)).monospacedDigit().foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        // A solid dark pill: it moves with the card, and glass would re-blur every frame.
        .background(Capsule().fill(Color.black.opacity(0.72)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }
}

/// A closed four-sided outline through view points (top-left, top-right, bottom-right,
/// bottom-left), animatable corner by corner.
struct CardQuadShape: Shape {
    var points: [CGPoint]

    typealias Pair = AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData>
    var animatableData: AnimatablePair<Pair, Pair> {
        get {
            guard points.count == 4 else { return AnimatablePair(Pair(.zero, .zero), Pair(.zero, .zero)) }
            return AnimatablePair(Pair(points[0].animatableData, points[1].animatableData),
                                  Pair(points[2].animatableData, points[3].animatableData))
        }
        set {
            var p = [CGPoint](repeating: .zero, count: 4)
            p[0].animatableData = newValue.first.first
            p[1].animatableData = newValue.first.second
            p[2].animatableData = newValue.second.first
            p[3].animatableData = newValue.second.second
            points = p
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count == 4 else { return path }
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}
