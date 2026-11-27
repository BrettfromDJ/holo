import Foundation
import Observation
import UIKit

/// Rapid scanning: every photo is queued and read in the background, a couple at a time,
/// so you can keep shooting. Clear matches are accepted straight away; others wait for you.
/// Cards the live scanner already recognised come in through `add(matched:photo:thumbnail:)`,
/// done and picked, without being read again.
@Observable
final class ScanModel {
    struct Entry: Identifiable, Equatable {
        enum State { case queued, reading, done, failed }

        let id = UUID()
        let photo: Data
        /// The whole photo for the server scan when `photo` is a crop of one card (CardSight
        /// finds every card in the whole photo); nil sends `photo`.
        var upload: Data?
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
        /// The printing (Normal, Holofoil, Reverse Holofoil); the matched one until you change it.
        var printing: String?
        /// What it's worth in this condition and printing (see `reprice`), and where that came from.
        var value: Double?
        var priceNote: String?
        /// In a deal: what happened when it was added ("Added to coming in", "Not in your inventory").
        var note: String?
        var rejected = false
        /// Its own details (portfolio, graded, bought or pulled, price, shipping…), set from its page.
        var draft: ScanDraft?

        var isSlab: Bool { result?.read?.kind == "slab" }
        /// Picked as the best of several close matches, not a clear match: worth a glance.
        var isBestGuess: Bool { result?.status == "ambiguous" && picked != nil }
    }

    var entries: [Entry] = []
    /// The scan's default: bought at market (false) or pulled from packs (true). A card's own
    /// purchase details override it.
    var defaultPulled = false
    /// Where the last scan's seconds went ("4.8s · camera 0.1 · request 4.2 · ..."), printed to
    /// the console (and kept here for a debugger); the server logs its own split on Vercel.
    @ObservationIgnored var lastTiming: String?
    var scansLeft: Int?
    /// Stops new scans: the balance is empty or the account can't scan.
    var blocked: String?

    private let parallel = 2
    /// Per product, fetched once a scan matches it: TCGplayer's prices by condition, and the
    /// market price of each printing. Used by `reprice`.
    private var conditionRows: [String: [ConditionPrice]] = [:]
    private var printingPrices: [String: [Price]] = [:]
    private var fetching: Set<String> = []
    /// Scans found in the phone's own card list (no price yet) waiting for their price before
    /// they're handed to a deal, which needs the market price when a card is added.
    private var handLater: Set<UUID> = []
    /// Try reading the card on the phone before the paid scan (off in demo, where the catalog search isn't real).
    var onDeviceFirst = !Demo.isOn

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
            // CardSight reads what the phone can't; the phone still goes first (instant, free).
            if info.provider == "cardsight" { cardSight = true }
        }
    }

    @MainActor
    func add(photo: Data, upload: Data? = nil, tappedAt: Date = Date()) {
        var e = Entry(photo: photo)
        e.upload = upload
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
        e.printing = e.picked?.printing
        entries.insert(e, at: 0)
        reprice(0)
        if e.picked != nil { hand(0) }
    }

    // MARK: What each scan is worth

    /// Works out `value` for one entry: a slab at its grade's price; otherwise the market price
    /// of the chosen printing in the chosen condition, the way the Owned sheet does it
    /// (TCGplayer's price for that condition, then eBay sales in it, then a share of Near Mint).
    @MainActor
    private func reprice(_ i: Int) {
        guard entries.indices.contains(i) else { return }
        var e = entries[i]
        guard let c = e.picked else {
            e.value = nil
            e.priceNote = nil
            entries[i] = e
            return
        }
        let id = c.product.id
        prefetch(c.product)
        if e.isSlab, let slab = c.slabMarket {
            e.value = slab
            e.priceNote = "eBay sales at this grade"
        } else {
            let printing = e.printing ?? c.printing
            // A card found in the phone's own list comes without a printing or price: once the
            // prices arrive, take the first printing that has one.
            if printing == nil, let first = printingPrices[id].flatMap(Self.defaultPrice) {
                e.printing = first.printing
            }
            let nm = printingPrices[id]?.first(where: { $0.printing == (e.printing ?? printing) })?.market ?? (printing == c.printing ? c.market : nil) ?? c.market
            if let nm, !c.product.isSealed {
                let condition = CardCondition(rawValue: e.condition) ?? .nearMint
                let worth = WorthCalc.raw(nm: nm, condition: condition, ebay: EbaySalesCache.cached(id, printing: printing, market: nm),
                                          conditions: conditionRows[id] ?? [], printing: printing)
                e.value = worth.price
                e.priceNote = worth.detail
            } else {
                e.value = nm
                e.priceNote = nm == nil ? nil : "TCGplayer market price"
            }
        }
        if e.value != entries[i].value || e.priceNote != entries[i].priceNote { entries[i] = e }
    }

    /// The printing a scan starts on when none was picked: the first priced one, Unlimited before
    /// 1st Edition (the everyday print; it showed 1st Edition on old Base Set cards).
    static func defaultPrice(_ prices: [Price]) -> Price? {
        let order = Editions.ordered(prices.compactMap(\.printing))
        func rank(_ p: Price) -> Int { order.firstIndex(of: p.printing ?? "") ?? 99 }
        // Never 1st Edition by default (only the stamp read on the card picks it, see
        // `OnDeviceScan.applyMarks`): old holos often have a price only for 1st Edition, and
        // the scan landed on it. An everyday printing without a price still wins; the card's
        // own market price stands in.
        let everyday = prices.filter { Editions.of(printing: $0.printing) == .unlimited }
        if let priced = everyday.filter({ $0.market != nil }).min(by: { rank($0) < rank($1) }) { return priced }
        if let any = everyday.min(by: { rank($0) < rank($1) }) { return any }
        return prices.filter { $0.market != nil }.min { rank($0) < rank($1) }
    }

    /// Fetches a product's prices by condition and by printing once, then reprices its scans,
    /// so the scan sheet opens with the numbers already there.
    @MainActor
    private func prefetch(_ product: Product) {
        let id = product.id
        guard !product.isSealed, !fetching.contains(id), conditionRows[id] == nil else { return }
        fetching.insert(id)
        Task { [weak self] in
            async let rows = try? Backend.shared.api.conditionPrices(id, printing: nil)
            async let catalog = try? Backend.shared.api.catalogProduct(id)
            let (conditions, prices) = await (rows ?? [], catalog?.prices ?? [])
            await MainActor.run {
                guard let self else { return }
                self.conditionRows[id] = conditions
                if !prices.isEmpty { self.printingPrices[id] = prices }
                self.fetching.remove(id)
                for i in self.entries.indices where self.entries[i].picked?.product.id == id { self.reprice(i) }
                // Scans waiting on this price for a deal: give them it, then hand them over.
                for i in self.entries.indices where self.handLater.contains(self.entries[i].id) && self.entries[i].picked?.product.id == id {
                    self.handLater.remove(self.entries[i].id)
                    let chosen = self.entries[i].printing
                    let price = prices.first { $0.printing == chosen && $0.market != nil } ?? Self.defaultPrice(prices)
                    self.entries[i].picked?.market = price?.market
                    if self.entries[i].picked?.printing == nil { self.entries[i].picked?.printing = price?.printing }
                    self.hand(i)
                }
            }
        }
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
        entries[i].printing = candidate.printing
        reprice(i)
        hand(i)
    }

    @MainActor
    private func hand(_ i: Int) {
        guard let onPick, var c = entries[i].picked else { return }
        // Its price already fetched (the same card scanned before): fill it in.
        if c.market == nil, let prices = printingPrices[c.product.id],
           let price = prices.first(where: { $0.printing == (entries[i].printing ?? c.printing) && $0.market != nil }) ?? Self.defaultPrice(prices) {
            c.market = price.market
            if c.printing == nil { c.printing = price.printing }
            entries[i].picked = c
        }
        // Found in the phone's card list: no price yet. Wait for it (a moment), then hand over.
        if c.market == nil, c.slabMarket == nil, !c.product.isSealed, fetching.contains(c.product.id) {
            handLater.insert(entries[i].id)
            return
        }
        let result = onPick(c, entries[i].result?.read)
        entries[i].note = result.note
        entries[i].rejected = !result.ok
        UINotificationFeedbackGenerator().notificationOccurred(result.ok ? .success : .warning)
    }

    /// The scan matched the wrong card: this is the right one (picked from search). Its photo
    /// stays. In a deal it's handed over if the wrong one wasn't yet (the wrong one, if it was,
    /// is removed from the deal by hand).
    @MainActor
    func replace(_ id: UUID, with hit: SearchHit) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        let result = OnDeviceScan.result(for: hit)
        entries[i].state = .done
        entries[i].error = nil
        entries[i].result = result
        entries[i].picked = result.candidates.first
        entries[i].printing = entries[i].picked?.printing
        entries[i].rejected = false
        reprice(i)
        if onPick != nil, entries[i].note == nil { hand(i) }
    }

    /// What you paid for one scan, as typed.
    @MainActor
    func setPaid(_ id: UUID, _ text: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }), entries[i].paid != text else { return }
        entries[i].paid = text
    }

    @MainActor
    func setCondition(_ id: UUID, _ value: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }), entries[i].condition != value else { return }
        entries[i].condition = value
        if entries[i].draft?.purchase.gradeCompany == nil, entries[i].draft != nil {
            entries[i].draft?.purchase.condition = value
            entries[i].draft?.prefill.condition = value
        }
        reprice(i)
    }

    @MainActor
    func setPrinting(_ id: UUID, _ value: String?) {
        guard let i = entries.firstIndex(where: { $0.id == id }), entries[i].printing != value else { return }
        entries[i].printing = value
        if entries[i].draft != nil {
            entries[i].draft?.purchase.printing = value
            entries[i].draft?.prefill.printing = value
        }
        reprice(i)
    }

    @MainActor
    func setDraft(_ id: UUID, _ draft: ScanDraft?) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].draft = draft
        // The row shows what was picked in the purchase details: its condition and printing
        // (and the price for them).
        if let p = draft?.purchase {
            if p.gradeCompany == nil, p.condition != "Sealed", CardCondition(rawValue: p.condition) != nil { entries[i].condition = p.condition }
            if let printing = p.printing { entries[i].printing = printing }
            reprice(i)
        }
    }

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
            let upload = entry.upload ?? entry.photo
            let onDevice = onDeviceFirst
            let testing = ScanTestLog.isOn && !Demo.isOn
            let tappedAt = entry.tappedAt
            let queuedAt = Date()
            Task {
                // First the phone reads the card's name and number and finds it in the stored
                // catalog (instant and free). Only when that isn't a clear single match does the
                // photo go to the paid server scan.
                var phone: TimeInterval?
                var quick: ScanResult?
                var readText: String?
                if onDevice {
                    let began = Date()
                    let found = await OnDeviceScan.identifyWithReading(jpeg: photo)
                    quick = found.result
                    readText = found.reading.map { [$0.name, $0.number.isEmpty ? nil : $0.number, found.note].compactMap { $0 }.joined(separator: " · ") }
                    phone = Date().timeIntervalSince(began)
                    if let quick {
                        let line = ScanModel.timingLine(tappedAt: tappedAt, queuedAt: queuedAt, phone: phone, request: nil, server: nil, bytes: photo.count)
                        await MainActor.run { self.lastTiming = line; self.finish(id, result: quick) }
                        // Test-photo mode: CardSight reads it too, so the two can be compared.
                        if testing {
                            let (server, request) = (try? await Backend.shared.api.scan(jpeg: upload)) ?? (nil, nil)
                            ScanTestLog.save(photo: photo, phone: ScanTestLog.answer(quick, seconds: phone), phoneRead: readText,
                                             cardSight: ScanTestLog.answer(server, seconds: request))
                        }
                        return
                    }
                }
                do {
                    let (result, request) = try await Backend.shared.api.scan(jpeg: upload)
                    if testing {
                        ScanTestLog.save(photo: photo, phone: nil, phoneRead: readText, cardSight: ScanTestLog.answer(result, seconds: request))
                    }
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
        // A clear match, or the best of several close ones (shown as a best guess, with the
        // others a tap away under Wrong card?), rather than asking which it is.
        if first.status == "matched" || first.status == "ambiguous", let top = first.candidates.first {
            entries[i].picked = top
            entries[i].printing = top.printing
            reprice(i)
            hand(i)
        }
        // Every other card in the same photo gets its own entry, right after this one.
        for (n, other) in others.enumerated() {
            var e = Entry(photo: entries[i].photo)
            e.thumbnail = entries[i].thumbnail
            e.state = .done
            e.result = other
            if other.status == "matched" || other.status == "ambiguous", let top = other.candidates.first {
                e.picked = top
                e.printing = top.printing
            }
            let at = min(i + 1 + n, entries.count)
            entries.insert(e, at: at)
            reprice(at)
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
        picks.compactMap { purchase(for: $0, pulled: pulled, date: date) }
    }

    /// One scan as a purchase from the batch's defaults (its own details, if set, are used instead by the review).
    func purchase(for e: Entry, pulled: Bool, date: String) -> CollectionStore.Purchase? {
            guard let c = e.picked else { return nil }
            let typed = Double(e.paid.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ""))
            let slab = e.result?.read?.kind == "slab" ? e.result?.read?.grade : nil
            return CollectionStore.Purchase(
                product: c.product,
                printing: e.printing ?? c.printing,
                condition: c.product.isSealed ? "Sealed" : (slab != nil ? CardCondition.nearMint.rawValue : e.condition),
                gradeCompany: slab?.company,
                grade: slab?.grade,
                quantity: 1,
                unitPrice: typed ?? (pulled ? 0 : (e.value ?? 0)),
                date: date,
                // Pulled cards are marked as pulls (the Pulled badge, the pull reveal, Pulls).
                source: pulled ? Txn.pulledSource : "ios-scan"
            )
    }
}
