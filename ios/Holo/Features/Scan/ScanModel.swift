import Foundation
import Observation
import UIKit

/// Rapid scanning: every photo is queued and read in the background, a couple at a time,
/// so you can keep shooting. Clear matches are accepted straight away; others wait for you.
/// Cards the live scanner already recognised come in through `add(matched:photo:thumbnail:)`,
/// done and picked, without being read again.
@Observable
final class ScanModel {
    struct Entry: Identifiable {
        enum State { case queued, reading, done, failed }

        let id = UUID()
        let photo: Data
        /// When the shutter was tapped, for the timing line.
        var tappedAt = Date()
        var thumbnail: UIImage?
        var state: State = .queued
        var result: ScanResult?
        var error: String?
        /// The match you're adding (picked automatically on a clear match).
        var picked: ScanCandidate?
        /// What you paid each, as typed; blank uses the default below.
        var paid = ""
        var condition = CardCondition.nearMint.rawValue
        /// In a deal: what happened when it was added ("Added to coming in", "Not in your inventory").
        var note: String?
        var rejected = false

        var value: Double? { picked?.value(for: result?.read) }
    }

    var entries: [Entry] = []
    /// Where the last scan's seconds went ("4.8s · camera 0.1 · request 4.2 · ..."), for the
    /// timing line in the scanner while scanning is being made faster.
    var lastTiming: String?
    var scansLeft: Int?
    /// Stops new scans: the balance is empty or the account can't scan.
    var blocked: String?

    private let parallel = 2
    /// Try reading the card on the phone before the paid scan (off in demo, where the catalog search isn't real).
    var onDeviceFirst = !Demo.isOn

    /// Told each scan's answer as soon as it arrives (the scanner shows it on the card).
    var onResult: (@MainActor (ScanResult) -> Void)?

    /// Set when scanning into a deal: each confirmed match is handed over straight away.
    var onPick: (@MainActor (ScanCandidate, ScanRead?) -> (ok: Bool, note: String))?

    var picks: [Entry] { entries.filter { $0.picked != nil && !$0.rejected } }
    var busy: Int { entries.filter { $0.state == .queued || $0.state == .reading }.count }
    var total: Double { picks.reduce(0) { $0 + ($1.value ?? 0) } }

    /// The server scans with CardSight: it reads every card itself (several per photo, under a
    /// second), so the phone's own read is skipped and photos aren't cropped to one card.
    var cardSight = false

    func refreshBalance() async {
        let info = await Backend.shared.api.scanInfo()
        await MainActor.run {
            scansLeft = info.left
            if info.provider == "cardsight" {
                cardSight = true
                onDeviceFirst = false
            }
        }
    }

    @MainActor
    func add(photo: Data, tappedAt: Date = Date()) {
        var e = Entry(photo: photo)
        e.tappedAt = tappedAt
        entries.insert(e, at: 0)
        pump()
        // The strip's thumbnail is decoded off the main thread, so the shutter never stutters.
        let id = e.id
        Task {
            let thumb = await UIImage(data: photo)?.byPreparingThumbnail(ofSize: CGSize(width: 96, height: 128))
            if let i = entries.firstIndex(where: { $0.id == id }) { entries[i].thumbnail = thumb }
        }
    }

    /// A card the live scanner already identified on the phone (`CardTracker`): it goes in
    /// matched and picked, with no paid scan. `photo` is the flattened crop, kept so a retry
    /// or a later look has the picture.
    @MainActor
    func add(matched result: ScanResult, photo: Data, thumbnail: UIImage?) {
        var e = Entry(photo: photo)
        e.state = .done
        e.result = result
        e.thumbnail = thumbnail?.preparingThumbnail(of: CGSize(width: 96, height: 128)) ?? thumbnail
        e.picked = result.candidates.first
        entries.insert(e, at: 0)
        if e.picked != nil { hand(0) }
    }

    @MainActor
    func retry(_ id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].state = .queued
        entries[i].error = nil
        pump()
    }

    @MainActor
    func pick(_ candidate: ScanCandidate, for id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        // In a deal, each scan is handed over once.
        if onPick != nil, entries[i].picked != nil, !entries[i].rejected { return }
        entries[i].picked = candidate
        hand(i)
    }

    @MainActor
    private func hand(_ i: Int) {
        guard let onPick, let c = entries[i].picked else { return }
        let result = onPick(c, entries[i].result?.read)
        entries[i].note = result.note
        entries[i].rejected = !result.ok
        UINotificationFeedbackGenerator().notificationOccurred(result.ok ? .success : .warning)
    }

    @MainActor
    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// Start reading queued photos, oldest first, up to `parallel` at once.
    @MainActor
    private func pump() {
        guard blocked == nil else { return }
        let reading = entries.filter { $0.state == .reading }.count
        let waiting = entries.filter { $0.state == .queued }.reversed()
        for entry in waiting.prefix(max(0, parallel - reading)) {
            guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { continue }
            entries[i].state = .reading
            let id = entry.id
            let photo = entry.photo
            let onDevice = onDeviceFirst
            let tappedAt = entry.tappedAt
            let queuedAt = Date()
            Task {
                // First the phone reads the card's name and number and finds it in the stored
                // catalog (instant and free). Only when that isn't a clear single match does the
                // photo go to the paid server scan.
                var phone: TimeInterval?
                if onDevice {
                    let began = Date()
                    let quick = await OnDeviceScan.identify(jpeg: photo)
                    phone = Date().timeIntervalSince(began)
                    if let quick {
                        let line = ScanModel.timingLine(tappedAt: tappedAt, queuedAt: queuedAt, phone: phone, request: nil, server: nil, bytes: photo.count)
                        await MainActor.run { self.lastTiming = line; self.finish(id, result: quick) }
                        return
                    }
                }
                do {
                    let (result, request) = try await Backend.shared.api.scan(jpeg: photo)
                    let line = ScanModel.timingLine(tappedAt: tappedAt, queuedAt: queuedAt, phone: phone, request: request, server: result.timing, bytes: photo.count)
                    await MainActor.run { self.lastTiming = line; self.finish(id, result: result) }
                } catch {
                    await MainActor.run { self.fail(id, error: error) }
                }
            }
        }
    }

    /// One line saying where a scan's time went: the whole wait, then the camera (tap to
    /// photo), the phone's own read, the request round trip, and inside it the server's steps.
    /// Also printed, for the Xcode console.
    static func timingLine(tappedAt: Date, queuedAt: Date, phone: TimeInterval?, request: TimeInterval?, server: ScanTiming?, bytes: Int) -> String {
        func s(_ t: TimeInterval) -> String { String(format: "%.1f", t) }
        var parts = ["\(s(Date().timeIntervalSince(tappedAt)))s", "camera \(s(queuedAt.timeIntervalSince(tappedAt)))"]
        if let phone { parts.append("phone \(s(phone))") }
        if let request { parts.append("request \(s(request))") }
        if let server {
            let steps: [(String, Double?)] = [("sign-in", server.auth ?? server.checks), ("photo", server.form), ("CardSight", server.cardsight), ("TCG", server.identify), ("catalog", server.catalog)]
            for (name, ms) in steps { if let ms { parts.append("\(name) \(s(ms / 1000))") } }
            if let total = server.server ?? server.total, let request { parts.append("network \(s(max(0, request - total / 1000)))") }
            if server.cold == true { parts.append("cold start") }
        }
        parts.append("\(bytes / 1024) KB")
        let line = parts.joined(separator: " · ")
        print("scan timing:", line)
        return line
    }

    @MainActor
    private func finish(_ id: UUID, result: ScanResult) {
        if let left = result.scansRemaining { scansLeft = left }
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return pump() }
        entries[i].state = .done
        var first = result
        let others = first.others ?? []
        first.others = nil
        entries[i].result = first
        onResult?(first)
        if first.status == "matched", let top = first.candidates.first {
            entries[i].picked = top
            hand(i)
        }
        // Every other card in the same photo gets its own entry, right after this one.
        for (n, other) in others.enumerated() {
            var e = Entry(photo: entries[i].photo)
            e.thumbnail = entries[i].thumbnail
            e.state = .done
            e.result = other
            if other.status == "matched", let top = other.candidates.first { e.picked = top }
            let at = min(i + 1 + n, entries.count)
            entries.insert(e, at: at)
            if e.picked != nil { hand(at) }
        }
        pump()
    }

    @MainActor
    private func fail(_ id: UUID, error: Error) {
        let code = (error as? HoloError)?.code
        if ["scan_balance_empty", "unauthorized", "not_configured"].contains(code ?? "") {
            blocked = error.localizedDescription
        }
        if let i = entries.firstIndex(where: { $0.id == id }) {
            entries[i].state = .failed
            entries[i].error = error.localizedDescription
        }
        pump()
    }

    /// Everything picked, as purchases. A blank price uses market, or $0 for cards you pulled.
    func purchases(pulled: Bool, date: String) -> [CollectionStore.Purchase] {
        picks.compactMap { e -> CollectionStore.Purchase? in
            guard let c = e.picked else { return nil }
            let typed = Double(e.paid.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ""))
            let slab = e.result?.read?.kind == "slab" ? e.result?.read?.grade : nil
            return CollectionStore.Purchase(
                product: c.product,
                printing: c.printing,
                condition: c.product.isSealed ? "Sealed" : (slab != nil ? CardCondition.nearMint.rawValue : e.condition),
                gradeCompany: slab?.company,
                grade: slab?.grade,
                quantity: 1,
                unitPrice: typed ?? (pulled ? 0 : (e.value ?? 0)),
                date: date,
                source: "ios-scan"
            )
        }
    }
}
