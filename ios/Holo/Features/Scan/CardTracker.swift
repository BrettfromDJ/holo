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
        } else {
            misses += 1
            missQuad = read
            missAt = CACurrentMediaTime()
        }
    }
}
