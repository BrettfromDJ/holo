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

    /// Roughly how much of the frame it covers (shoelace formula), for picking the biggest card.
    var area: CGFloat {
        let c = corners
        var sum: CGFloat = 0
        for i in 0..<4 {
            let a = c[i], b = c[(i + 1) % 4]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    /// Upright and card-shaped (63:88, allowing for tilt) in a frame of `size` pixels. A card's
    /// picture box or attack box is wide, not tall, so it's turned away (the scanner kept locking
    /// onto those and cropping into the middle of the card).
    func isCardShaped(in size: CGSize) -> Bool {
        func px(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }
        func len(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(px(a).x - px(b).x, px(a).y - px(b).y) }
        let w = (len(topLeft, topRight) + len(bottomLeft, bottomRight)) / 2
        let h = (len(topLeft, bottomLeft) + len(topRight, bottomRight)) / 2
        guard h > 0 else { return false }
        let ratio = w / h
        guard ratio >= 0.58 && ratio <= 0.85 else { return false }
        // A card seen at an angle still has corners near square and opposite sides of similar
        // length; a lopsided outline (a corner of the desk, a keyboard edge) doesn't.
        let ring = [topLeft, topRight, bottomRight, bottomLeft].map(px)
        for i in 0..<4 {
            let a = ring[(i + 3) % 4], b = ring[i], c = ring[(i + 1) % 4]
            let u = CGVector(dx: a.x - b.x, dy: a.y - b.y), v = CGVector(dx: c.x - b.x, dy: c.y - b.y)
            let lu = hypot(u.dx, u.dy), lv = hypot(v.dx, v.dy)
            guard lu > 0, lv > 0 else { return false }
            let degrees = acos(max(-1, min(1, (u.dx * v.dx + u.dy * v.dy) / (lu * lv)))) * 180 / .pi
            if abs(degrees - 90) > 30 { return false }
        }
        let top = len(topLeft, topRight), bottom = len(bottomLeft, bottomRight)
        let left = len(topLeft, bottomLeft), right = len(topRight, bottomRight)
        return min(top, bottom) / max(top, bottom) > 0.6 && min(left, right) / max(left, right) > 0.6
    }

    /// Whether `other` sits inside this one (its middle within this one's bounds).
    func contains(_ other: CardQuad) -> Bool {
        let xs = corners.map(\.x), ys = corners.map(\.y)
        let mid = CGPoint(x: other.corners.map(\.x).reduce(0, +) / 4, y: other.corners.map(\.y).reduce(0, +) / 4)
        return mid.x > (xs.min() ?? 0) && mid.x < (xs.max() ?? 0) && mid.y > (ys.min() ?? 0) && mid.y < (ys.max() ?? 0)
    }

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
/// twice. A match (`liveMatch`) lets a tap add it with no paid scan. Only the border view
/// reads `quad`; the scanner reads just `isTracking` (which changes rarely), so nothing else
/// redraws per frame.
/// Used on the main thread only.
@Observable
final class CardTracker {
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
    /// When the card now followed was first seen (the outline waits a moment before showing).
    @ObservationIgnored private var firstSeen: CFTimeInterval?
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
            // Lost for a moment (a glint, a wobble): keep the outline where it was; only after
            // 0.8 s is the card gone and the still frame comes back (no flicker between the two).
            if quad != nil, now - lastSeen > 0.8 { reset() }
            return
        }
        lastSeen = now
        if firstSeen == nil { firstSeen = now }
        // The card moved since it was read (a hand swapping in the next card): its answer is
        // stale. It stuck around when the next card landed in the same spot, so every tap added
        // the previous card again.
        if let m = liveMatch, m.quad.distance(to: raw) > 0.06 { liveMatch = nil }
        if frameSize != frame { frameSize = frame }
        if let current = quad, current.distance(to: raw) < 0.12 {
            quad = current.blended(toward: raw, by: 0.5)
        } else {
            quad = raw
        }
        // Shown once it's held a quarter of a second, so a passing edge doesn't flash an outline.
        if !isTracking, let first = firstSeen, now - first >= 0.25 { isTracking = true }

        // Held still for a quarter second: read it (once per steady card). Was half a second;
        // sooner means it's more often read by the time you tap.
        if let ref = steadyRef, ref.distance(to: raw) < 0.03 {
            if now - steadySince >= 0.25 { identifyIfNeeded(raw, now: now) }
        } else {
            steadyRef = raw
            steadySince = now
        }
    }

    /// A read of the card in view is under way (a tap can wait for it instead of starting over).
    var isReading: Bool { identifying && quad != nil }

    /// Waits for the read under way (at most `timeout` seconds), then the match for the card in
    /// view, if it found one.
    func awaitMatch(timeout: Double) async -> LiveMatch? {
        let gen = generation
        let start = CACurrentMediaTime()
        while identifying, gen == generation, CACurrentMediaTime() - start < timeout {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return gen == generation ? readyMatch : nil
    }

    /// A shot was taken: what was read is used up, and anything being read now is dropped.
    /// The next tap reads afresh (it's usually another card).
    func consume() {
        generation += 1
        liveMatch = nil
        steadyRef = nil
        missQuad = nil
    }

    /// The card is gone (or the scanner paused): forget it and anything read in flight.
    func reset() {
        generation += 1
        if quad != nil { quad = nil }
        if isTracking { isTracking = false }
        firstSeen = nil
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
                    hit = await OnDeviceScan.lookUp(reading, jpeg: crop.jpeg)
                    self?.cache[key] = .some(hit)
                }
            }
            self?.finish(gen, hit: hit, crop: crop, quad: current)
        }
    }

    private func finish(_ gen: Int, hit: SearchHit?, crop: CardCrop?, quad read: CardQuad) {
        identifying = false
        // Dropped too when the card moved while it was being read (another card now).
        guard gen == generation, let now = quad, now.distance(to: read) < 0.06 else { return }
        if let hit, let crop {
            liveMatch = LiveMatch(hit: hit, crop: crop, quad: read)
            missQuad = nil
        } else {
            misses += 1
            missQuad = read
            missAt = CACurrentMediaTime()
        }
    }
}

// MARK: - The border

/// The lime border that follows the card, and the tap that adds it.
/// The only view that reads the corners, so it's the only one that redraws per frame.
struct CardTrackingOverlay: View {
    let tracker: CardTracker
    var onTap: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            // Only once tracking has settled: the still frame and this are never on screen together.
            if tracker.isTracking, let quad = tracker.quad {
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
                }
            }
        }
        .ignoresSafeArea()
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

    /// Rounded corners like a real card's (the owner's call), sized to the card.
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count == 4 else { return path }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        let side = min(hypot(points[0].x - points[1].x, points[0].y - points[1].y),
                       hypot(points[1].x - points[2].x, points[1].y - points[2].y))
        let radius = max(4, side * 0.07)
        path.move(to: mid(points[3], points[0]))
        for i in 0..<4 {
            path.addArc(tangent1End: points[i], tangent2End: mid(points[i], points[(i + 1) % 4]), radius: radius)
            path.addLine(to: mid(points[i], points[(i + 1) % 4]))
        }
        path.closeSubpath()
        return path
    }
}
